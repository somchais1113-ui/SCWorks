package com.scdeport.scdrive.obd

import java.util.Locale

object ElmResponseParser {
    private val knownStatusTokens = listOf(
        "SEARCHING...", "BUS INIT...", "NO DATA", "STOPPED", "UNABLE TO CONNECT",
        "CAN ERROR", "BUS ERROR", "DATA ERROR", "BUFFER FULL",
    )

    fun normalizedLines(raw: String, command: String? = null): List<String> {
        val normalizedCommand = command?.replace(" ", "")?.trim()?.uppercase(Locale.US)
        return raw.replace('\u0000', ' ').replace('>', '\n').split('\r', '\n')
            .map { it.trim() }.filter { it.isNotEmpty() }
            .filterNot { line -> normalizedCommand != null && line.replace(" ", "").uppercase(Locale.US) == normalizedCommand }
    }

    fun normalizedText(raw: String, command: String? = null): String = normalizedLines(raw, command).joinToString(" | ")

    fun compactHexCandidates(raw: String, command: String? = null): List<String> =
        normalizedLines(raw, command)
            .map { it.uppercase(Locale.US).replace(" ", "") }
            .map { line -> knownStatusTokens.fold(line) { current, token -> current.replace(token.replace(" ", ""), "") } }
            .map { it.filter { ch -> ch in '0'..'9' || ch in 'A'..'F' } }
            .filter { it.length >= 4 }

    fun containsToken(raw: String, token: String): Boolean = raw.uppercase(Locale.US).contains(token.uppercase(Locale.US))
    fun isUnsupported(raw: String): Boolean = normalizedLines(raw).any { it.trim() == "?" }
    fun hasNoData(raw: String): Boolean = containsToken(raw, "NO DATA") || containsToken(raw, "UNABLE TO CONNECT") || containsToken(raw, "BUS ERROR") || containsToken(raw, "CAN ERROR") || containsToken(raw, "DATA ERROR")
    fun sanitizedText(raw: String): String = normalizedLines(raw).joinToString(" | ")

    fun classifyError(raw: String, parserValid: Boolean? = null): ObdProbeErrorType = when {
        isUnsupported(raw) -> ObdProbeErrorType.ELM_UNKNOWN_COMMAND
        containsToken(raw, "NO DATA") -> ObdProbeErrorType.NO_DATA
        containsToken(raw, "CAN ERROR") -> ObdProbeErrorType.CAN_ERROR
        containsToken(raw, "BUS ERROR") || containsToken(raw, "DATA ERROR") -> ObdProbeErrorType.BUS_ERROR
        containsToken(raw, "UNABLE TO CONNECT") -> ObdProbeErrorType.UNABLE_TO_CONNECT
        parserValid == false -> ObdProbeErrorType.INVALID_PID_RESPONSE
        else -> ObdProbeErrorType.NONE
    }

    fun extractCanResponderIds(raw: String): Set<String> {
        val ids = linkedSetOf<String>()
        for (line0 in normalizedLines(raw)) {
            val line = line0.uppercase(Locale.US).trim()
            if (line.isBlank() || knownStatusTokens.any { line.contains(it) }) continue
            val spaced = Regex("^([0-9A-F]{3})\\s+(?:[0-9A-F]{2}\\s+)+").find(line)
            if (spaced != null && Regex("(?:^|\\s)41(?:\\s|$)").containsMatchIn(line)) {
                ids += spaced.groupValues[1]
                continue
            }
            val compact = line.filter { it in '0'..'9' || it in 'A'..'F' }
            if (compact.length >= 9) {
                val payload = compact.drop(3)
                if (payload.contains("41")) ids += compact.take(3)
            }
        }
        return ids
    }

    data class ParsedProtocolDescription(val raw: String?, val description: String?, val autoSelected: Boolean)
    fun parseProtocolDescription(raw: String): ParsedProtocolDescription {
        val text = sanitizedText(raw).trim().ifBlank { return ParsedProtocolDescription(null, null, false) }
        val auto = text.startsWith("AUTO", ignoreCase = true)
        val description = if (auto) text.substringAfter(',', text).trim().ifBlank { text } else text
        return ParsedProtocolDescription(text, description, auto)
    }

    data class ParsedProtocolNumber(val raw: String?, val number: String?, val autoSelected: Boolean)
    fun parseProtocolNumber(raw: String): ParsedProtocolNumber {
        val text = normalizedLines(raw).firstOrNull()?.trim()?.uppercase(Locale.US) ?: return ParsedProtocolNumber(null, null, false)
        val match = Regex("^(A)?([0-9A-F]+)$").find(text) ?: return ParsedProtocolNumber(text, null, false)
        return ParsedProtocolNumber(text, match.groupValues[2].trimStart('0').ifBlank { "0" }, match.groupValues[1] == "A")
    }

    fun isSuspiciousZeroCapabilityBitmap(raw: String): Boolean {
        val payloads = ObdPidParser.payloadsForMode01(raw, 0x00, 4)
        return payloads.isNotEmpty() && payloads.all { bytes -> bytes.all { (it.toInt() and 0xFF) == 0 } }
    }
}
