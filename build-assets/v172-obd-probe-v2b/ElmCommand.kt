package com.scdeport.scdrive.obd

import java.io.IOException

enum class ElmCommandPriority {
    CONTROL,
    HIGH,
    MEDIUM,
    LOW,
}

data class ElmCommand(
    val command: String,
    val priority: ElmCommandPriority = ElmCommandPriority.MEDIUM,
    val timeoutMs: Long = 2500L,
    val retryCount: Int = 0,
)

data class ElmCommandResult(
    val command: String,
    val rawResponse: String,
    val requestElapsedRealtimeNanos: Long,
    val responseElapsedRealtimeNanos: Long,
    val latencyMs: Double,
    val estimatedMeasurementElapsedRealtimeNanos: Long,
    val firstByteElapsedRealtimeNanos: Long = 0L,
) {
    val firstByteLatencyMs: Double
        get() = if (firstByteElapsedRealtimeNanos <= 0L) -1.0 else
            (firstByteElapsedRealtimeNanos - requestElapsedRealtimeNanos) / 1_000_000.0
}

class ElmCommandTimeoutException(
    val elmCommand: String,
    val partialResponse: String = "",
    val requestElapsedRealtimeNanos: Long = 0L,
    val firstByteElapsedRealtimeNanos: Long = 0L,
) : IOException("ELM command timed out: $elmCommand")
