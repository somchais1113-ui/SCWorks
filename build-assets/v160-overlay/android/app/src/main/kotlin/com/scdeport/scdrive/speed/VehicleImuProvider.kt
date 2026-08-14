package com.scdeport.scdrive.speed

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import kotlin.math.abs
import kotlin.math.sqrt

class VehicleImuProvider(
    context: Context,
    looper: Looper,
    private val onSample: (ImuSample) -> Unit,
) : SensorEventListener {
    data class ImuSample(
        val elapsedRealtimeNanos: Long,
        val forwardAccelerationMps2: Double,
        val rawAccelerationMps2: Double,
        val gyroMagnitudeRadS: Double,
        val rateHz: Double,
        val available: Boolean,
        val calibrated: Boolean,
    )

    private val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val linearSensor = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
    private val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyro = sensorManager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
    private val prefs = context.getSharedPreferences("scdrive_speed_engine", Context.MODE_PRIVATE)
    private val handler = Handler(looper)
    private val useLinearSensor = linearSensor != null
    private val gravity = DoubleArray(3)
    private val latestLinear = DoubleArray(3)
    private var gyroMagnitude = 0.0
    private var lastAccelTimestamp = 0L
    private var imuRateHz = 0.0
    private var bias = 0.0
    private var stopped = false

    private var axisX = prefs.getFloat("forward_axis_x", 0f).toDouble()
    private var axisY = prefs.getFloat("forward_axis_y", 0f).toDouble()
    private var axisZ = prefs.getFloat("forward_axis_z", 0f).toDouble()
    private var calibrationSamples = prefs.getInt("forward_axis_samples", 0)
    private var corrX = 0.0
    private var corrY = 0.0
    private var corrZ = 0.0

    val available: Boolean get() = linearSensor != null || accelerometer != null
    val calibrated: Boolean get() = calibrationSamples >= 8 && axisNorm() > 0.7

    fun start() {
        val accelerationSource = linearSensor ?: accelerometer
        if (accelerationSource != null) {
            sensorManager.registerListener(
                this,
                accelerationSource,
                SpeedEngineConfig.imuSamplingPeriodUs,
                handler,
            )
        }
        gyro?.let {
            sensorManager.registerListener(
                this,
                it,
                SpeedEngineConfig.imuSamplingPeriodUs,
                handler,
            )
        }
    }

    fun stop() {
        sensorManager.unregisterListener(this)
    }

    fun setStopped(value: Boolean) {
        stopped = value
    }

    fun learnForwardAxis(gnssAccelerationMps2: Double, turning: Boolean) {
        if (!available || turning) return
        if (abs(gnssAccelerationMps2) < 0.18 || abs(gnssAccelerationMps2) > 4.5) return
        val energy = sqrt(
            latestLinear[0] * latestLinear[0] +
                latestLinear[1] * latestLinear[1] +
                latestLinear[2] * latestLinear[2],
        )
        if (energy < 0.08 || energy > 8.0) return
        corrX = corrX * 0.90 + gnssAccelerationMps2 * latestLinear[0] * 0.10
        corrY = corrY * 0.90 + gnssAccelerationMps2 * latestLinear[1] * 0.10
        corrZ = corrZ * 0.90 + gnssAccelerationMps2 * latestLinear[2] * 0.10
        val norm = sqrt(corrX * corrX + corrY * corrY + corrZ * corrZ)
        if (norm < 0.02) return
        axisX = corrX / norm
        axisY = corrY / norm
        axisZ = corrZ / norm
        calibrationSamples++
        if (calibrationSamples % 4 == 0) {
            prefs.edit()
                .putFloat("forward_axis_x", axisX.toFloat())
                .putFloat("forward_axis_y", axisY.toFloat())
                .putFloat("forward_axis_z", axisZ.toFloat())
                .putInt("forward_axis_samples", calibrationSamples)
                .apply()
        }
    }

    override fun onSensorChanged(event: SensorEvent) {
        when (event.sensor.type) {
            Sensor.TYPE_GYROSCOPE -> {
                val x = event.values[0].toDouble()
                val y = event.values[1].toDouble()
                val z = event.values[2].toDouble()
                gyroMagnitude = sqrt(x * x + y * y + z * z)
            }
            Sensor.TYPE_LINEAR_ACCELERATION, Sensor.TYPE_ACCELEROMETER -> {
                val values = DoubleArray(3) { event.values[it].toDouble() }
                if (!useLinearSensor && event.sensor.type == Sensor.TYPE_ACCELEROMETER) {
                    for (i in 0..2) {
                        gravity[i] = gravity[i] * 0.92 + values[i] * 0.08
                        latestLinear[i] = values[i] - gravity[i]
                    }
                } else {
                    for (i in 0..2) latestLinear[i] = values[i]
                }
                if (lastAccelTimestamp != 0L) {
                    val dt = (event.timestamp - lastAccelTimestamp) / 1_000_000_000.0
                    if (dt in 0.002..0.5) {
                        val instantRate = 1.0 / dt
                        imuRateHz = if (imuRateHz == 0.0) instantRate else imuRateHz * 0.90 + instantRate * 0.10
                    }
                }
                lastAccelTimestamp = event.timestamp
                val norm = sqrt(
                    latestLinear[0] * latestLinear[0] +
                        latestLinear[1] * latestLinear[1] +
                        latestLinear[2] * latestLinear[2],
                )
                var forward = if (calibrated) {
                    latestLinear[0] * axisX + latestLinear[1] * axisY + latestLinear[2] * axisZ
                } else 0.0
                if (stopped && calibrated && abs(forward) < 0.9) {
                    bias = bias * 0.97 + forward * 0.03
                }
                forward -= bias
                val turnFactor = (1.0 - gyroMagnitude / 1.25).coerceIn(0.15, 1.0)
                forward = (forward * turnFactor).coerceIn(
                    SpeedEngineConfig.maxBrakingMps2,
                    SpeedEngineConfig.maxAccelerationMps2,
                )
                onSample(
                    ImuSample(
                        elapsedRealtimeNanos = event.timestamp,
                        forwardAccelerationMps2 = forward,
                        rawAccelerationMps2 = norm,
                        gyroMagnitudeRadS = gyroMagnitude,
                        rateHz = imuRateHz,
                        available = available,
                        calibrated = calibrated,
                    ),
                )
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    private fun axisNorm(): Double = sqrt(axisX * axisX + axisY * axisY + axisZ * axisZ)
}
