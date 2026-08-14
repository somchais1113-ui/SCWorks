package com.scdeport.scdrive.speed

import android.content.Context
import java.io.BufferedWriter
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class SpeedDebugLogger(private val context: Context) {
    private val executor = Executors.newSingleThreadExecutor()
    @Volatile private var writer: BufferedWriter? = null
    @Volatile var path: String? = null
        private set
    private var rows = 0

    fun start() {
        if (writer != null) return
        executor.execute {
            if (writer != null) return@execute
            val root = context.getExternalFilesDir("speed_logs") ?: context.filesDir
            root.mkdirs()
            val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            val file = File(root, "scdrive_speed_$stamp.csv")
            writer = BufferedWriter(FileWriter(file, false)).also {
                it.write("elapsed_nanos,gps_speed_kmh,predicted_speed_kmh,estimated_speed_kmh,display_speed_kmh,gps_age_ms,gps_rate_hz,gps_accuracy_m,speed_accuracy_mps,gps_confidence,filter_accel_mps2,forward_accel_mps2,raw_accel_mps2,imu_rate_hz,engine_rate_hz,filter_gain,state,native_processing_ms\n")
                it.flush()
            }
            path = file.absolutePath
        }
    }

    fun stop() {
        executor.execute {
            writer?.flush()
            writer?.close()
            writer = null
            rows = 0
        }
    }

    fun log(state: VehicleSpeedState) {
        val line = listOf(
            state.emittedElapsedRealtimeNanos,
            state.rawGpsSpeedKmh,
            state.predictedSpeedKmh,
            state.estimatedSpeedKmh,
            state.displaySpeedKmh,
            state.gpsAgeMs,
            state.gpsRateHz,
            state.gpsAccuracyM,
            state.gpsSpeedAccuracyMps,
            state.gpsConfidence,
            state.accelerationMps2,
            state.forwardAccelerationMps2,
            state.rawAccelMps2,
            state.imuRateHz,
            state.engineRateHz,
            state.filterGain,
            state.state,
            state.nativeProcessingMs,
        ).joinToString(",") + "\n"
        executor.execute {
            val output = writer ?: return@execute
            output.write(line)
            rows++
            if (rows % 25 == 0) output.flush()
        }
    }

    fun destroy() {
        stop()
        executor.shutdown()
    }
}
