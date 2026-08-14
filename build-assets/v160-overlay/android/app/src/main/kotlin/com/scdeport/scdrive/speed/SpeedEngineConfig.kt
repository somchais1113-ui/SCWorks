package com.scdeport.scdrive.speed

object SpeedEngineConfig {
    const val locationIntervalMs = 200L
    const val locationMinIntervalMs = 100L
    const val enginePeriodMs = 40L // 25 Hz
    const val imuSamplingPeriodUs = 20_000 // target 50 Hz

    const val badGpsAccuracyM = 30.0
    const val gpsMaxUsefulAgeMs = 2_000.0
    const val gpsSignalLostAgeMs = 6_000.0
    const val predictionMaxDurationMs = 2_000.0

    const val stopEnterSpeedMps = 2.0 / 3.6
    const val stopExitSpeedMps = 4.0 / 3.6
    const val stopConfirmMs = 400L
    const val stopAccelThresholdMps2 = 0.28
    const val startAccelThresholdMps2 = 0.38

    const val maxSpeedMps = 260.0 / 3.6
    const val maxAccelerationMps2 = 5.5
    const val maxBrakingMps2 = -8.0

    const val filterGainMin = 0.12
    const val filterGainMax = 0.78
    const val turnGyroThresholdRadS = 0.55
}
