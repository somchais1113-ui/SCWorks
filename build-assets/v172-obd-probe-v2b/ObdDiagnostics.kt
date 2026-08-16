package com.scdeport.scdrive.obd

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.ceil
import kotlin.math.max

object ObdDiagnostics {
    data class ProbeEntry(val command: String, val rawResponse: String, val latencyMs: Double?, val error: String? = null)

    fun buildReportV2(state: ObdTelemetryState, probe: ObdProbeResult): String {
        val date = SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date(probe.probeStartWallClockMs))
        fun last(command: String) = probe.records.lastOrNull { it.command == command }
        val ati = last("ATI")
        val atdp = last("ATDP")
        val atdpn = last("ATDPN")
        val pid00 = probe.records.lastOrNull { it.command == "0100" && it.label.contains("PASS", true) } ?: last("0100")
        val rpmRecord = last("010C")
        val speedRecord = last("010D")
        val commandLatency = probe.records.filter { it.completedNs > it.requestStartNs }.map { it.roundTripLatencyMs }
        val speedLatency = probe.records.filter { it.command == "010D" && it.pidMeasurementValid }.map { it.roundTripLatencyMs }
        val rpmLatency = probe.records.filter { it.command == "010C" && it.pidMeasurementValid }.map { it.roundTripLatencyMs }
        val speedRate = successfulPidRateHz(probe.records.filter { it.command == "010D" && it.pidMeasurementValid })
        val rpmRate = successfulPidRateHz(probe.records.filter { it.command == "010C" && it.pidMeasurementValid })
        val overallRate = commandCompletionRateHz(probe.records.filter { it.completedNs > it.requestStartNs })
        val timeouts = probe.records.count { it.errorType == ObdProbeErrorType.TIMEOUT }
        val parserErrors = probe.records.count { it.errorType == ObdProbeErrorType.PARSER_ERROR || it.errorType == ObdProbeErrorType.INVALID_PID_RESPONSE }
        val transportErrors = probe.records.count { it.errorType == ObdProbeErrorType.TRANSPORT_ERROR }

        return buildString {
            appendLine("SC DRIVE OBD DIAGNOSTIC REPORT V2")
            appendLine("Date: $date")
            appendLine("Bluetooth Name: ${state.deviceName ?: "UNKNOWN"}")
            appendLine("MAC Address: ${state.deviceMac ?: "UNKNOWN"}")
            appendLine("Probe Result: ${if (probe.probeCompletedSuccessfully) "COMPLETED" else "FAILED"}")
            appendLine("Connection State At Probe Start: ${probe.connectionStateAtProbeStart}")
            appendLine("Transport During Probe: ${probe.connectionStateDuringProbe}")
            appendLine("Connection State At Probe End: ${probe.connectionStateAtProbeEnd}")
            appendLine("Transport After Probe: ${if (probe.transportClosedAfterProbe) "DISCONNECTED_BY_PROBE_OR_ERROR" else "CONNECTED / PRESERVED"}")
            appendLine("Second Pass Protocol Test: ${if (probe.secondPassExecuted) "RUN" else "NOT REQUIRED"}")
            appendLine("ENGINE TEST CONDITION REQUIRED: ENGINE RUNNING • TRANSMISSION P • PARKING BRAKE ENGAGED")
            appendLine()
            section("ELM")
            appendLine("ATZ RAW:"); appendRaw(last("ATZ"))
            appendLine("ATI RAW:"); appendRaw(ati)
            appendLine("Reported Firmware: ${probe.reportedFirmware ?: ati?.normalizedResponse?.ifBlank { null } ?: "UNKNOWN"}")
            appendLine("NOTE: ATI is a reported firmware string only; it does not verify the physical ELM chipset revision.")
            appendLine()
            section("PROTOCOL")
            appendLine("ATDP RAW:"); appendRaw(atdp)
            appendLine("Protocol: ${probe.protocolInfo.description ?: "UNKNOWN"}")
            appendLine("ATDPN RAW:"); appendRaw(atdpn)
            appendLine("Protocol Number Raw: ${probe.protocolInfo.numberRaw ?: "UNKNOWN"}")
            appendLine("Protocol Number: ${probe.protocolInfo.number ?: "UNKNOWN"}")
            appendLine("Protocol Selection: ${if (probe.protocolInfo.autoSelected) "AUTO" else "MANUAL / NOT VERIFIED"}")
            appendLine()
            section("CAN")
            appendLine("Responding CAN IDs: ${if (probe.respondingCanIds.isEmpty()) "NOT DETECTED" else probe.respondingCanIds.joinToString(", ")}")
            appendLine("NOTE: No CAN request/responder address is hardcoded by the probe.")
            appendLine()
            section("CAPABILITY")
            appendLine("0100 RAW:"); appendRaw(pid00)
            appendLine("0100 NORMALIZED: ${pid00?.normalizedResponse?.ifBlank { "<empty>" } ?: "NOT RUN"}")
            appendLine("PID Capability State: ${probe.capabilityState.name}")
            if (probe.capabilityState == ObdCapabilityState.SUSPICIOUS_ZERO_CAPABILITY_BITMAP) {
                appendLine("Interpretation: 410000000000 is suspicious and is NOT accepted as proof that all Mode 01 PIDs are unsupported.")
            }
            appendLine()
            section("RPM")
            appendLine("010C RAW:"); appendRaw(rpmRecord)
            appendLine("010C NORMALIZED: ${rpmRecord?.normalizedResponse?.ifBlank { "<empty>" } ?: "NOT RUN"}")
            appendLine("RPM PID: ${probe.rpmPidStatus.name}")
            appendLine("RPM: ${probe.rpm?.let { String.format(Locale.US, "%.0f rpm", it) } ?: "NOT MEASURED"}")
            appendLine("RPM Rate: ${formatHz(rpmRate)}")
            appendLine("RPM Average Latency: ${formatMs(average(rpmLatency))}")
            appendLine("RPM P50 Latency: ${formatMs(percentile(rpmLatency, 0.50))}")
            appendLine("RPM P95 Latency: ${formatMs(percentile(rpmLatency, 0.95))}")
            appendLine("RPM P99 Latency: ${formatMs(percentile(rpmLatency, 0.99))}")
            appendLine()
            section("SPEED")
            appendLine("010D RAW:"); appendRaw(speedRecord)
            appendLine("010D NORMALIZED: ${speedRecord?.normalizedResponse?.ifBlank { "<empty>" } ?: "NOT RUN"}")
            appendLine("Vehicle Speed PID: ${probe.speedPidStatus.name}")
            appendLine("OBD Speed: ${probe.speedKmh?.let { String.format(Locale.US, "%.0f km/h", it) } ?: "NOT MEASURED"}")
            appendLine("Speed PID Rate: ${formatHz(speedRate)}")
            appendLine("Speed Average Latency: ${formatMs(average(speedLatency))}")
            appendLine("Speed P50 Latency: ${formatMs(percentile(speedLatency, 0.50))}")
            appendLine("Speed P95 Latency: ${formatMs(percentile(speedLatency, 0.95))}")
            appendLine("Speed P99 Latency: ${formatMs(percentile(speedLatency, 0.99))}")
            appendLine()
            section("PERFORMANCE")
            appendLine("Overall ELM Command Completion Rate: ${formatHz(overallRate)}")
            appendLine("Average Command Latency: ${formatMs(average(commandLatency))}")
            appendLine("P50 Command Latency: ${formatMs(percentile(commandLatency, 0.50))}")
            appendLine("P95 Command Latency: ${formatMs(percentile(commandLatency, 0.95))}")
            appendLine("P99 Command Latency: ${formatMs(percentile(commandLatency, 0.99))}")
            appendLine("Timeouts: $timeouts")
            appendLine("Parser Errors: $parserErrors")
            appendLine("Transport Errors: $transportErrors")
            appendLine("Runtime Historical Average Latency: ${formatMs(state.averageLatencyMs)}")
            appendLine("IMPORTANT: Overall command rate is NOT the adapter's maximum realtime PID rate.")
            appendLine()
            section("RAW COMMAND RECORDS")
            for (record in probe.records) {
                appendLine("[${record.label}] COMMAND: ${record.command}")
                appendLine("Request Start ns: ${record.requestStartNs}")
                appendLine("First Byte ns: ${if (record.firstByteNs > 0) record.firstByteNs else -1}")
                appendLine("Completed ns: ${if (record.completedNs > 0) record.completedNs else -1}")
                appendLine("First Byte Latency: ${formatMs(record.firstByteLatencyMs)}")
                appendLine("Round Trip Latency: ${formatMs(record.roundTripLatencyMs)}")
                appendLine("Success: ${record.success}")
                appendLine("Error Type: ${record.errorType.name}")
                if (!record.errorMessage.isNullOrBlank()) appendLine("Error: ${record.errorMessage}")
                appendLine("RAW:"); appendLine(record.rawResponse.ifBlank { "<empty>" })
                appendLine("NORMALIZED:"); appendLine(record.normalizedResponse.ifBlank { "<empty>" })
                appendLine("---")
            }
            appendLine()
            section("DEBUG TERMINAL")
            for (record in probe.records) {
                appendLine("[${wallTimestamp(probe, record.requestStartNs)}] TX ${record.command}")
                if (record.firstByteNs > 0) {
                    val lines = record.rawResponse.replace('\r', '\n').split('\n').map { it.trim() }.filter { it.isNotEmpty() }
                    if (lines.isEmpty()) appendLine("[${wallTimestamp(probe, record.firstByteNs)}] RX <empty>")
                    else for (line in lines) appendLine("[${wallTimestamp(probe, record.firstByteNs)}] RX $line")
                }
                if (record.completedNs > 0) appendLine("[${wallTimestamp(probe, record.completedNs)}] RX >")
            }
            appendLine()
            section("SAFETY / FUSION GATE")
            appendLine("Probe is READ-ONLY telemetry/diagnostics. No Mode 04, ECU write, actuator command, coding, or CAN injection is issued.")
            appendLine("OBD speed is NOT fused into SC Drive VehicleSpeedState until PID 010D status becomes SUPPORTED with valid realtime samples.")
        }
    }

    fun buildReport(state: ObdTelemetryState, entries: List<ProbeEntry>): String = buildString {
        appendLine("SC DRIVE OBD DIAGNOSTIC REPORT (LEGACY)")
        appendLine("Bluetooth Name: ${state.deviceName ?: "UNKNOWN"}")
        appendLine("Connection State: ${state.connectionState.name}")
        for (entry in entries) appendLine("${entry.command}: ${ElmResponseParser.sanitizedText(entry.rawResponse)}${entry.error?.let { " ERROR=$it" }.orEmpty()}")
    }

    private fun StringBuilder.section(name: String) { appendLine("================================"); appendLine(name); appendLine("================================") }
    private fun StringBuilder.appendRaw(record: ObdProbeCommandRecord?) { if (record == null) appendLine("NOT RUN") else appendLine(record.rawResponse.ifBlank { "<empty>" }) }
    private fun average(values: List<Double>): Double = if (values.isEmpty()) -1.0 else values.average()
    private fun percentile(values: List<Double>, fraction: Double): Double {
        if (values.isEmpty()) return -1.0
        val sorted = values.sorted()
        val index = (ceil(fraction.coerceIn(0.0, 1.0) * sorted.size).toInt() - 1).coerceIn(0, sorted.lastIndex)
        return sorted[index]
    }
    private fun successfulPidRateHz(records: List<ObdProbeCommandRecord>): Double {
        if (records.size < 2) return -1.0
        val first = records.minOf { it.completedNs }; val last = records.maxOf { it.completedNs }
        val durationSec = max(0.0, (last - first) / 1_000_000_000.0)
        return if (durationSec <= 0.0) -1.0 else (records.size - 1) / durationSec
    }
    private fun commandCompletionRateHz(records: List<ObdProbeCommandRecord>): Double {
        if (records.size < 2) return -1.0
        val first = records.minOf { it.requestStartNs }; val last = records.maxOf { it.completedNs }
        val durationSec = max(0.0, (last - first) / 1_000_000_000.0)
        return if (durationSec <= 0.0) -1.0 else records.size / durationSec
    }
    private fun formatHz(value: Double): String = if (value > 0) String.format(Locale.US, "%.2f Hz", value) else "NOT MEASURED"
    private fun formatMs(value: Double): String = if (value >= 0) String.format(Locale.US, "%.1f ms", value) else "NOT MEASURED"
    private fun wallTimestamp(probe: ObdProbeResult, elapsedNs: Long): String {
        if (elapsedNs <= 0L) return "--:--:--.---"
        val deltaMs = (elapsedNs - probe.probeStartElapsedNs) / 1_000_000L
        return SimpleDateFormat("HH:mm:ss.SSS", Locale.US).format(Date(probe.probeStartWallClockMs + deltaMs))
    }
}
