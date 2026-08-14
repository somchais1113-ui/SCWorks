package com.scdeport.scdrive.speed

import android.content.Context
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel
import kotlin.math.max

class VehicleSpeedEngine(context: Context) : EventChannel.StreamHandler {
    private val appContext = context.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private val thread = HandlerThread("SCDriveVehicleSpeed").apply { start() }
    private val handler = Handler(thread.looper)
    private val filter = AlphaBetaSpeedFilter()
    private val stopDetector = StopDetector()
    private val logger = SpeedDebugLogger(appContext)

    private var eventSink: EventChannel.EventSink? = null
    private var running = false
    private var debugEnabled = false
    private var lastTickNanos = 0L
    private var engineRateHz = 0.0

    private var imuSample = VehicleImuProvider.ImuSample(
        elapsedRealtimeNanos = 0L,
        forwardAccelerationMps2 = 0.0,
        rawAccelerationMps2 = 0.0,
        gyroMagnitudeRadS = 0.0,
        rateHz = 0.0,
        available = false,
        calibrated = false,
    )
    private lateinit var imuProvider: VehicleImuProvider
    private lateinit var gnssProvider: GnssLocationProvider

    private var hasGpsFix = false
    private var lastAcceptedGpsNanos = 0L
    private var lastGpsMeasurementNanos = 0L
    private var lastAcceptedGpsSpeedMps = 0.0
    private var lastGpsRateNanos = 0L
    private var gpsRateHz = 0.0
    private var gpsAccuracyM = 999.0
    private var speedAccuracyMps = Double.NaN
    private var gpsConfidence = 0.0
    private var latitude = 0.0
    private var longitude = 0.0
    private var headingDeg = 0.0
    private var rawGpsSpeedMps = 0.0

    init {
        imuProvider = VehicleImuProvider(appContext, thread.looper) { sample -> imuSample = sample }
        gnssProvider = GnssLocationProvider(
            appContext,
            thread.looper,
            onLocation = ::handleLocation,
            onError = { _ -> Unit },
        )
    }

    fun start() {
        handler.post {
            if (running) return@post
            running = true
            lastTickNanos = SystemClock.elapsedRealtimeNanos()
            imuProvider.start()
            gnssProvider.start()
            handler.post(tickRunnable)
        }
    }

    fun stop() {
        handler.post {
            if (!running) return@post
            running = false
            handler.removeCallbacks(tickRunnable)
            gnssProvider.stop()
            imuProvider.stop()
            logger.stop()
        }
    }

    fun setDebugEnabled(enabled: Boolean) {
        debugEnabled = enabled
        if (enabled) logger.start() else logger.stop()
    }

    fun logPath(): String? = logger.path

    fun destroy() {
        stop()
        handler.post {
            logger.destroy()
            thread.quitSafely()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun handleLocation(measurement: GnssLocationProvider.GnssMeasurement) {
        val now = SystemClock.elapsedRealtimeNanos()
        val ageMs = max(0.0, (now - measurement.elapsedRealtimeNanos) / 1_000_000.0)
        val gpsDt = if (lastAcceptedGpsNanos == 0L) 0.8 else
            ((measurement.elapsedRealtimeNanos - lastAcceptedGpsNanos) / 1_000_000_000.0).coerceIn(0.05, 5.0)

        if (lastGpsRateNanos != 0L) {
            val rateDt = (measurement.elapsedRealtimeNanos - lastGpsRateNanos) / 1_000_000_000.0
            if (rateDt in 0.05..5.0) {
                val instant = 1.0 / rateDt
                gpsRateHz = if (gpsRateHz == 0.0) instant else gpsRateHz * 0.82 + instant * 0.18
            }
        }
        lastGpsRateNanos = measurement.elapsedRealtimeNanos

        val raw = measurement.speedMps.coerceIn(0.0, SpeedEngineConfig.maxSpeedMps)
        val impliedAccel = if (lastAcceptedGpsNanos == 0L) 0.0 else
            (raw - lastAcceptedGpsSpeedMps) / gpsDt
        val impossibleJump = lastAcceptedGpsNanos != 0L &&
            (impliedAccel > SpeedEngineConfig.maxAccelerationMps2 * 1.35 ||
                impliedAccel < SpeedEngineConfig.maxBrakingMps2 * 1.35)
        val predictionError = raw - filter.velocityMps
        val confidence = GpsConfidenceCalculator.calculate(
            positionAccuracyM = measurement.positionAccuracyM,
            speedAccuracyMps = measurement.speedAccuracyMps,
            gpsAgeMs = ageMs,
            predictionErrorMps = predictionError,
            usedFallbackSpeed = measurement.usedFallbackSpeed,
            impossibleJump = impossibleJump,
        )

        latitude = measurement.latitude
        longitude = measurement.longitude
        headingDeg = measurement.bearingDeg
        gpsAccuracyM = measurement.positionAccuracyM
        speedAccuracyMps = measurement.speedAccuracyMps ?: Double.NaN
        rawGpsSpeedMps = raw
        gpsConfidence = confidence
        hasGpsFix = true
        lastGpsMeasurementNanos = measurement.elapsedRealtimeNanos

        if (!impossibleJump && confidence > 0.06) {
            if (lastAcceptedGpsNanos != 0L && gpsDt in 0.15..2.5) {
                val gnssAcceleration = (raw - lastAcceptedGpsSpeedMps) / gpsDt
                imuProvider.learnForwardAxis(
                    gnssAcceleration,
                    imuSample.gyroMagnitudeRadS > SpeedEngineConfig.turnGyroThresholdRadS,
                )
            }
            filter.correctGps(raw, confidence, gpsDt)
            lastAcceptedGpsSpeedMps = raw
            lastAcceptedGpsNanos = measurement.elapsedRealtimeNanos
        }
    }

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            val tickStart = SystemClock.elapsedRealtimeNanos()
            val dt = if (lastTickNanos == 0L) SpeedEngineConfig.enginePeriodMs / 1000.0 else
                ((tickStart - lastTickNanos) / 1_000_000_000.0).coerceIn(0.005, 0.20)
            lastTickNanos = tickStart
            val instantEngineRate = 1.0 / dt
            engineRateHz = if (engineRateHz == 0.0) instantEngineRate else
                engineRateHz * 0.90 + instantEngineRate * 0.10

            val gpsAgeMs = if (lastGpsMeasurementNanos == 0L) Double.POSITIVE_INFINITY else
                max(0.0, (tickStart - lastGpsMeasurementNanos) / 1_000_000.0)
            val acceptedGpsAgeMs = if (lastAcceptedGpsNanos == 0L) Double.POSITIVE_INFINITY else
                max(0.0, (tickStart - lastAcceptedGpsNanos) / 1_000_000.0)
            val predictionAgeFactor = if (acceptedGpsAgeMs <= SpeedEngineConfig.predictionMaxDurationMs) 1.0 else
                (1.0 - (acceptedGpsAgeMs - SpeedEngineConfig.predictionMaxDurationMs) / 1_500.0)
                    .coerceIn(0.0, 1.0)
            val turnFactor = (1.0 - imuSample.gyroMagnitudeRadS / 1.25).coerceIn(0.15, 1.0)
            val imuTrust = if (imuSample.available && imuSample.calibrated) {
                predictionAgeFactor * turnFactor
            } else 0.0

            filter.predict(dt, imuSample.forwardAccelerationMps2, imuTrust)
            val freshGps = hasGpsFix && gpsAgeMs < SpeedEngineConfig.gpsSignalLostAgeMs
            val reliableGps = freshGps && gpsConfidence >= 0.35
            val stopState = stopDetector.update(
                gpsSpeedMps = if (reliableGps) rawGpsSpeedMps else null,
                estimatedSpeedMps = filter.velocityMps,
                forwardAccelerationMps2 = imuSample.forwardAccelerationMps2,
                nowNanos = tickStart,
            )
            imuProvider.setStopped(stopState == StopState.STOPPED)
            if (stopState == StopState.STOPPED) filter.forceStopped()

            val motionState = when {
                stopState == StopState.STOPPED -> "STOPPED"
                imuSample.forwardAccelerationMps2 > 0.32 -> "ACCELERATING"
                imuSample.forwardAccelerationMps2 < -0.32 -> "BRAKING"
                else -> "CONSTANT_SPEED"
            }
            val stale = acceptedGpsAgeMs > SpeedEngineConfig.predictionMaxDurationMs
            val displayMps = if (stopState == StopState.STOPPED) 0.0 else filter.velocityMps
            val processingMs = (SystemClock.elapsedRealtimeNanos() - tickStart) / 1_000_000.0
            val state = VehicleSpeedState(
                rawGpsSpeedKmh = rawGpsSpeedMps * 3.6,
                predictedSpeedKmh = filter.predictedVelocityMps * 3.6,
                estimatedSpeedKmh = filter.velocityMps * 3.6,
                displaySpeedKmh = displayMps * 3.6,
                accelerationMps2 = filter.accelerationMps2,
                forwardAccelerationMps2 = imuSample.forwardAccelerationMps2,
                gpsAccuracyM = gpsAccuracyM,
                gpsSpeedAccuracyMps = if (speedAccuracyMps.isFinite()) speedAccuracyMps else -1.0,
                gpsConfidence = gpsConfidence,
                gpsAgeMs = if (gpsAgeMs.isFinite()) gpsAgeMs else -1.0,
                gpsRateHz = gpsRateHz,
                imuRateHz = imuSample.rateHz,
                engineRateHz = engineRateHz,
                rawAccelMps2 = imuSample.rawAccelerationMps2,
                filterGain = filter.lastGain,
                state = motionState,
                hasGpsFix = hasGpsFix,
                isGpsReliable = reliableGps,
                isStale = stale,
                imuAvailable = imuSample.available,
                imuCalibrated = imuSample.calibrated,
                latitude = latitude,
                longitude = longitude,
                headingDeg = headingDeg,
                emittedElapsedRealtimeNanos = tickStart,
                nativeProcessingMs = processingMs,
                logPath = logger.path,
            )
            if (debugEnabled) logger.log(state)
            mainHandler.post { eventSink?.success(state.toMap()) }

            val elapsedMs = (SystemClock.elapsedRealtimeNanos() - tickStart) / 1_000_000L
            val delay = (SpeedEngineConfig.enginePeriodMs - elapsedMs).coerceAtLeast(1L)
            handler.postDelayed(this, delay)
        }
    }
}
