package com.scdeport.scdrive.speed

import kotlin.math.abs
import kotlin.math.min

class AlphaBetaSpeedFilter {
    var velocityMps: Double = 0.0
        private set
    var accelerationMps2: Double = 0.0
        private set
    var predictedVelocityMps: Double = 0.0
        private set
    var lastGain: Double = 0.0
        private set
    private var initialized = false

    fun predict(dtSeconds: Double, imuAccelerationMps2: Double, imuTrust: Double) {
        val dt = dtSeconds.coerceIn(0.005, 0.20)
        val trust = imuTrust.coerceIn(0.0, 1.0)
        val targetAcceleration = imuAccelerationMps2.coerceIn(
            SpeedEngineConfig.maxBrakingMps2,
            SpeedEngineConfig.maxAccelerationMps2,
        )
        val blend = 0.10 + 0.55 * trust
        accelerationMps2 += (targetAcceleration - accelerationMps2) * blend
        if (trust < 0.05) accelerationMps2 *= 0.90
        velocityMps = (velocityMps + accelerationMps2 * dt)
            .coerceIn(0.0, SpeedEngineConfig.maxSpeedMps)
        predictedVelocityMps = velocityMps
    }

    fun correctGps(measuredSpeedMps: Double, confidence: Double, secondsSinceLastGps: Double) {
        val measured = measuredSpeedMps.coerceIn(0.0, SpeedEngineConfig.maxSpeedMps)
        if (!initialized) {
            velocityMps = measured
            predictedVelocityMps = measured
            accelerationMps2 = 0.0
            lastGain = 1.0
            initialized = true
            return
        }
        val c = confidence.coerceIn(0.0, 1.0)
        var gain = SpeedEngineConfig.filterGainMin +
            (SpeedEngineConfig.filterGainMax - SpeedEngineConfig.filterGainMin) * c
        val error = measured - velocityMps
        if (c > 0.80 && abs(error) > 3.0) gain = min(0.90, gain + 0.10)
        lastGain = gain
        velocityMps = (velocityMps + gain * error)
            .coerceIn(0.0, SpeedEngineConfig.maxSpeedMps)
        val dt = secondsSinceLastGps.coerceIn(0.15, 2.5)
        val beta = 0.04 + 0.18 * c
        accelerationMps2 = (accelerationMps2 + beta * error / dt)
            .coerceIn(SpeedEngineConfig.maxBrakingMps2, SpeedEngineConfig.maxAccelerationMps2)
    }

    fun forceStopped() {
        velocityMps = 0.0
        predictedVelocityMps = 0.0
        accelerationMps2 = 0.0
    }
}
