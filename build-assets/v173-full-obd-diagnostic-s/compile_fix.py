from pathlib import Path

root = Path('.')

# Kotlin primitive ByteArray? has no generic orEmpty() helper. Use an explicit empty array.
p = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/obd/ObdManager.kt'
s = p.read_text()
s = s.replace('val initialDrain = queue?.drainInput().orEmpty()', 'val initialDrain = queue?.drainInput() ?: byteArrayOf()')
p.write_text(s)

# Keep normal runtime initialization compatible with the richer diagnostic queue.
p = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/obd/ElmCommandQueue.kt'
s = p.read_text()
if 'fun drainStaleInput(' not in s:
    needle = '''    fun drainInput(): ByteArray = lock.withLock {\n        if (transport.isConnected) transport.clearInput() else byteArrayOf()\n    }\n'''
    repl = needle + '''\n    /** Drain delayed bytes after reset until the stream stays quiet. */\n    fun drainStaleInput(maxDrainMs: Long = 700L, quietMs: Long = 100L): ByteArray = lock.withLock {\n        if (!transport.isConnected) return@withLock byteArrayOf()\n        val collected = java.io.ByteArrayOutputStream()\n        val deadlineNs = SystemClock.elapsedRealtimeNanos() + maxDrainMs.coerceAtLeast(0L) * 1_000_000L\n        var quietDeadlineNs = SystemClock.elapsedRealtimeNanos() + quietMs.coerceAtLeast(0L) * 1_000_000L\n        while (SystemClock.elapsedRealtimeNanos() < deadlineNs) {\n            val drained = transport.clearInput()\n            if (drained.isNotEmpty()) {\n                collected.write(drained)\n                quietDeadlineNs = SystemClock.elapsedRealtimeNanos() + quietMs.coerceAtLeast(0L) * 1_000_000L\n            } else if (SystemClock.elapsedRealtimeNanos() >= quietDeadlineNs) {\n                break\n            }\n            Thread.sleep(10L)\n        }\n        collected.toByteArray()\n    }\n'''
    if needle not in s:
        raise SystemExit('ElmCommandQueue drainInput anchor not found')
    s = s.replace(needle, repl)
p.write_text(s)

# Restore shared parser helpers used by normal OBD startup as compatibility wrappers
# around the V3 protocol parser. This avoids a separate parser/state path.
p = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/obd/ElmResponseParser.kt'
s = p.read_text()
if 'fun hasTransportOrBusError(' not in s:
    insert = '''\n    /** Runtime compatibility helpers shared by normal OBD initialization and diagnostic V3. */\n    fun hasTransportOrBusError(raw: String): Boolean =\n        containsToken(raw, "UNABLE TO CONNECT") ||\n            containsToken(raw, "CAN ERROR") ||\n            containsToken(raw, "BUS ERROR") ||\n            containsToken(raw, "DATA ERROR")\n\n    fun parseReportedFirmware(raw: String): String? {\n        val lines = normalizedLines(raw, "ATI")\n        return lines.firstOrNull { it.contains("ELM", ignoreCase = true) }\n            ?: lines.firstOrNull { it != "?" && it.isNotBlank() }\n    }\n\n    fun parseProtocol(descriptionRaw: String, numberRaw: String): ObdProtocolInfo {\n        val description = parseProtocolDescription(descriptionRaw)\n        val number = parseProtocolNumber(numberRaw)\n        return ObdProtocolInfo(\n            rawDescription = description.raw,\n            description = description.description,\n            numberRaw = number.raw,\n            number = number.number,\n            autoSelected = description.autoSelected || number.autoSelected,\n        )\n    }\n'''
    idx = s.rfind('\n}')
    if idx < 0:
        raise SystemExit('ElmResponseParser closing brace not found')
    s = s[:idx] + insert + s[idx:]
p.write_text(s)
