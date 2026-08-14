package com.scdeport.scdrive.speed

import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

object GpsConfidenceCalculator {
    private fun quality(value: Double, excellent: Double, poor: Double, floor: Double): Double {
        if (!value.isFinite()) return floor
        if (value <= excellent) return 1.0
        if (value >= poor) return floor
        val t = (value - excellent) / (poor - excellent)
        return 1.0 - t * (1.0 - floor)
    }

    fun calculate(
        positionAccuracyM: Double,
        speedAccuracyMps: Double?,
        gpsAgeMs: Double,
        predictionErrorMps: Double,
        usedFallbackSpeed: Boolean,
        impossibleJump: Boolean,
    ): Double {
        if (impossibleJump) return 0.0
        val positionQ = quality(positionAccuracyM, 4.0, 35.0, 0.08)
        val speedQ = speedAccuracyMps?.let { quality(it, 0.20, 2.50, 0.10) } ?: 0.55
        val ageQ = quality(gpsAgeMs, 120.0, 2_500.0, 0.08)
        val consistencyQ = quality(abs(predictionErrorMps), 0.35, 5.0, 0.12)
        var confidence = 0.36 * speedQ + 0.27 * positionQ + 0.23 * ageQ + 0.14 * consistencyQ
        if (usedFallbackSpeed) confidence *= 0.55
        return min(1.0, max(0.0, confidence))
    }
}
