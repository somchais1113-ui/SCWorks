package com.scdeport.scdrive.speed

import kotlin.math.abs

enum class StopState { MOVING, POSSIBLY_STOPPED, STOPPED }

class StopDetector {
    var state: StopState = StopState.MOVING
        private set
    private var possibleSinceNanos: Long = 0L

    fun update(
        gpsSpeedMps: Double?,
        estimatedSpeedMps: Double,
        forwardAccelerationMps2: Double,
        nowNanos: Long,
    ): StopState {
        val gpsLow = gpsSpeedMps == null || gpsSpeedMps < SpeedEngineConfig.stopEnterSpeedMps
        val estimatedLow = estimatedSpeedMps < SpeedEngineConfig.stopEnterSpeedMps
        val quiet = abs(forwardAccelerationMps2) < SpeedEngineConfig.stopAccelThresholdMps2
        val moveEvidence =
            estimatedSpeedMps > SpeedEngineConfig.stopExitSpeedMps ||
                (gpsSpeedMps ?: 0.0) > SpeedEngineConfig.stopExitSpeedMps ||
                forwardAccelerationMps2 > SpeedEngineConfig.startAccelThresholdMps2

        state = when (state) {
            StopState.MOVING -> {
                if (gpsLow && estimatedLow && quiet) {
                    possibleSinceNanos = nowNanos
                    StopState.POSSIBLY_STOPPED
                } else StopState.MOVING
            }
            StopState.POSSIBLY_STOPPED -> {
                if (moveEvidence) {
                    possibleSinceNanos = 0L
                    StopState.MOVING
                } else if (gpsLow && estimatedLow && quiet &&
                    (nowNanos - possibleSinceNanos) / 1_000_000L >= SpeedEngineConfig.stopConfirmMs
                ) {
                    StopState.STOPPED
                } else StopState.POSSIBLY_STOPPED
            }
            StopState.STOPPED -> {
                if (moveEvidence) {
                    possibleSinceNanos = 0L
                    StopState.MOVING
                } else StopState.STOPPED
            }
        }
        return state
    }
}
