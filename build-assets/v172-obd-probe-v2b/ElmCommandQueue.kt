package com.scdeport.scdrive.obd

import android.os.SystemClock
import java.nio.charset.StandardCharsets
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/** Strict single-command-in-flight executor for generic ELM327-compatible adapters. */
class ElmCommandQueue(private val transport: ObdTransport) {
    private val lock = ReentrantLock(true)

    val isExecuting: Boolean
        get() = lock.isLocked

    fun drainInput() {
        lock.withLock {
            if (transport.isConnected) transport.clearInput()
        }
    }

    fun execute(command: ElmCommand): ElmCommandResult = lock.withLock {
        if (!transport.isConnected) throw IllegalStateException("OBD transport not connected")
        val normalized = command.command.trim().uppercase()
        if (normalized.isBlank()) throw IllegalArgumentException("ELM command must not be blank")

        transport.clearInput()
        val requestNs = SystemClock.elapsedRealtimeNanos()
        transport.write((normalized + "\r").toByteArray(StandardCharsets.US_ASCII))

        val response = StringBuilder()
        val deadlineNs = requestNs + command.timeoutMs.coerceAtLeast(50) * 1_000_000L
        var promptSeen = false
        var firstByteNs = 0L

        while (SystemClock.elapsedRealtimeNanos() < deadlineNs) {
            val nowNs = SystemClock.elapsedRealtimeNanos()
            val remainingMs = ((deadlineNs - nowNs) / 1_000_000L).coerceAtLeast(1)
            val value = transport.readByte(remainingMs.coerceAtMost(100)) ?: continue
            val byteNs = SystemClock.elapsedRealtimeNanos()
            if (firstByteNs == 0L) firstByteNs = byteNs
            val char = value.toChar()
            if (char == '>') {
                promptSeen = true
                break
            }
            response.append(char)
            if (response.length > 32768) throw IllegalStateException("ELM response exceeded safety limit")
        }

        if (!promptSeen) {
            throw ElmCommandTimeoutException(
                elmCommand = normalized,
                partialResponse = response.toString(),
                requestElapsedRealtimeNanos = requestNs,
                firstByteElapsedRealtimeNanos = firstByteNs,
            )
        }

        val responseNs = SystemClock.elapsedRealtimeNanos()
        val latencyMs = (responseNs - requestNs) / 1_000_000.0
        val midpointNs = requestNs + ((responseNs - requestNs) / 2L)
        ElmCommandResult(
            command = normalized,
            rawResponse = response.toString(),
            requestElapsedRealtimeNanos = requestNs,
            firstByteElapsedRealtimeNanos = firstByteNs,
            responseElapsedRealtimeNanos = responseNs,
            latencyMs = latencyMs,
            estimatedMeasurementElapsedRealtimeNanos = midpointNs,
        )
    }
}
