from pathlib import Path

p = Path('android/app/src/main/kotlin/com/scdeport/scdrive/obd/ObdManager.kt')
text = p.read_text()
start = text.index('    fun runHardwareProbe(callback: (Result<String>) -> Unit) {')
end = text.index('    fun getDiagnosticReport(): String?', start)
new = r'''    fun runHardwareProbe(callback: (Result<String>) -> Unit) {
        worker.execute {
            if (!operationInProgress.compareAndSet(false, true)) {
                postResult(callback, Result.failure(IllegalStateException("OBD operation already in progress")))
                return@execute
            }
            val wasPolling = polling
            val wasReady = synchronized(stateLock) { state.ready }
            val wasConnected = transport?.isConnected == true
            val probe = ObdProbeResult(
                connectionStateAtProbeStart = synchronized(stateLock) { state.connectionState.name },
                connectionStateDuringProbe = "NOT_CONNECTED",
                connectionStateAtProbeEnd = "UNKNOWN",
            )
            try {
                polling = false
                pollFuture?.cancel(false)
                ensureProbeTransportConnected()
                probe.connectionStateDuringProbe = "CONNECTED"
                synchronized(stateLock) {
                    state.connected = true
                    state.connectionState = ObdConnectionState.ELM_INITIALIZING
                }
                emitState(force = true)
                queue?.drainInput()
                Thread.sleep(120)
                executeProbeCommand(probe, "RESET", "ATZ", 6000L)
                Thread.sleep(850)
                queue?.drainInput()
                executeProbeCommand(probe, "SETUP", "ATE0", 2500L)
                val ati = executeProbeCommand(probe, "IDENTITY", "ATI", 2500L)
                probe.reportedFirmware = ati?.let { extractReportedFirmware(it.rawResponse) }
                for (command in listOf("ATL0", "ATS1", "ATH1", "ATCAF1", "ATCFC1", "ATAT1", "ATST64", "ATSP0")) {
                    executeProbeCommand(probe, "SETUP", command, 3000L)
                }
                synchronized(stateLock) { state.connectionState = ObdConnectionState.ECU_CONNECTING }
                emitState(force = true)
                val pid00Pass1 = executeProbeCommand(probe, "PASS1", "0100", 12000L, pid = 0x00)
                val rpmPass1 = executeProbeCommand(probe, "PASS1", "010C", 6000L, pid = 0x0C)
                val speedPass1 = executeProbeCommand(probe, "PASS1", "010D", 6000L, pid = 0x0D)
                val atdp = executeProbeCommand(probe, "PROTOCOL", "ATDP", 3000L)
                val atdpn = executeProbeCommand(probe, "PROTOCOL", "ATDPN", 3000L)
                updateProbeProtocol(probe, atdp, atdpn)
                collectCanIds(probe)

                var activePid00 = pid00Pass1
                var activeRpm = rpmPass1
                var activeSpeed = speedPass1
                var supportedPids = supportedPidsFromPid00(pid00Pass1?.rawResponse.orEmpty())
                probe.capabilityState = capabilityStateFor(pid00Pass1)
                updatePidVerification(probe, activeRpm, activeSpeed, supportedPids)

                val protocol6 = probe.protocolInfo.number == "6" || probe.protocolInfo.description?.contains("CAN 11/500", ignoreCase = true) == true
                val needsSecondPass = protocol6 && (probe.rpmPidStatus != ObdPidVerificationStatus.SUPPORTED || probe.speedPidStatus != ObdPidVerificationStatus.SUPPORTED)
                if (needsSecondPass) {
                    probe.secondPassExecuted = true
                    for (command in listOf("ATTP6", "ATH1", "ATS1", "ATCAF1", "ATCFC1", "ATAT1", "ATST64")) {
                        executeProbeCommand(probe, "PASS2 SETUP", command, 4000L)
                    }
                    val pid00Pass2 = executeProbeCommand(probe, "PASS2", "0100", 10000L, pid = 0x00)
                    val rpmPass2 = executeProbeCommand(probe, "PASS2", "010C", 6000L, pid = 0x0C)
                    val speedPass2 = executeProbeCommand(probe, "PASS2", "010D", 6000L, pid = 0x0D)
                    collectCanIds(probe)
                    if (pid00Pass2 != null) activePid00 = pid00Pass2
                    if (rpmPass2 != null) activeRpm = rpmPass2
                    if (speedPass2 != null) activeSpeed = speedPass2
                    supportedPids = supportedPidsFromPid00(activePid00?.rawResponse.orEmpty())
                    probe.capabilityState = capabilityStateFor(activePid00)
                    updatePidVerification(probe, activeRpm, activeSpeed, supportedPids)
                    executeProbeCommand(probe, "RESTORE", "ATSP0", 3000L)
                }

                if (probe.speedPidStatus == ObdPidVerificationStatus.SUPPORTED) {
                    repeat(10) { index ->
                        executeProbeCommand(probe, "SPEED BENCH ${index + 1}", "010D", 4000L, pid = 0x0D)?.parsedValue?.let { probe.speedKmh = it }
                    }
                }
                if (probe.rpmPidStatus == ObdPidVerificationStatus.SUPPORTED) {
                    repeat(10) { index ->
                        executeProbeCommand(probe, "RPM BENCH ${index + 1}", "010C", 4000L, pid = 0x0C)?.parsedValue?.let { probe.rpm = it }
                    }
                }
                collectCanIds(probe)
                probe.probeCompletedSuccessfully = probe.records.any { it.command == "ATI" && it.completedNs > 0L } && probe.records.any { it.command == "ATDP" && it.completedNs > 0L }
                synchronized(stateLock) {
                    probe.reportedFirmware?.let { state.firmwareReported = it }
                    probe.protocolInfo.description?.let { state.protocolDescription = it; prefs.edit().putString(KEY_PROTOCOL, it).apply() }
                    probe.protocolInfo.number?.let { state.protocolNumber = it }
                    if (probe.capabilityState == ObdCapabilityState.VALID) state.supportedPids = supportedPids
                    probe.speedKmh?.let { state.rawSpeedKmh = it; state.speedValid = true }
                    probe.rpm?.let { state.engineRpm = it; state.rpmValid = true }
                }
                restoreRuntimeElmFormat(probe)
                if (wasReady && transport?.isConnected == true) {
                    synchronized(stateLock) { state.ready = true; state.connectionState = ObdConnectionState.READY }
                    probe.connectionStateAtProbeEnd = "READY"
                    probe.transportClosedAfterProbe = false
                } else {
                    try { transport?.disconnect() } catch (_: Throwable) {}
                    transport = null
                    queue = null
                    synchronized(stateLock) { state.connected = false; state.ready = false; state.connectionState = ObdConnectionState.DISCONNECTED }
                    probe.connectionStateAtProbeEnd = "DISCONNECTED_BY_PROBE"
                    probe.transportClosedAfterProbe = true
                }
                val report = synchronized(stateLock) { ObdDiagnostics.buildReportV2(state.copy(), probe).also { state.lastDiagnosticReport = it } }
                emitState(force = true)
                postResult(callback, Result.success(report))
            } catch (error: Throwable) {
                probe.connectionStateAtProbeEnd = synchronized(stateLock) { state.connectionState.name }
                probe.transportClosedAfterProbe = transport?.isConnected != true
                val report = synchronized(stateLock) { ObdDiagnostics.buildReportV2(state.copy(), probe).also { state.lastDiagnosticReport = it } }
                emitState(force = true)
                postResult(callback, Result.failure(IOException("Hardware Probe V2 failed: ${error.message}\n\n$report", error)))
            } finally {
                operationInProgress.set(false)
                if (wasPolling && state.ready && transport?.isConnected == true) startPolling()
                else if (!wasConnected && state.enabled && transport?.isConnected != true) scheduleConnect(700)
            }
        }
    }

    private fun ensureProbeTransportConnected() {
        synchronized(stateLock) {
            refreshEnvironmentLocked()
            if (!state.enabled) { state.enabled = true; prefs.edit().putBoolean(KEY_ENABLED, true).apply() }
            if (!state.permissionGranted) { state.connectionState = ObdConnectionState.PERMISSION_REQUIRED; throw SecurityException("Bluetooth permission required") }
            if (!state.bluetoothEnabled) { state.connectionState = ObdConnectionState.BLUETOOTH_DISABLED; throw IOException("Bluetooth is disabled") }
            if (state.deviceMac.isNullOrBlank()) { state.connectionState = ObdConnectionState.ADAPTER_NOT_SELECTED; throw IOException("No OBD adapter selected") }
        }
        if (transport?.isConnected == true && queue != null) return
        try { transport?.disconnect() } catch (_: Throwable) {}
        transport = null; queue = null
        synchronized(stateLock) { state.connectionState = ObdConnectionState.BLUETOOTH_CONNECTING; state.connected = false; state.ready = false }
        emitState(force = true)
        val mac = synchronized(stateLock) { state.deviceMac!! }
        val newTransport = BluetoothClassicObdTransport(appContext) { error -> if (!destroyed && !operationInProgress.get()) worker.execute { handleTransportLoss(error) } }
        newTransport.connect(mac)
        transport = newTransport
        queue = ElmCommandQueue(newTransport)
        synchronized(stateLock) { state.connected = true; state.connectionState = ObdConnectionState.BLUETOOTH_CONNECTED }
        emitState(force = true)
    }

    private fun executeProbeCommand(probe: ObdProbeResult, label: String, command: String, timeoutMs: Long, pid: Int? = null): ObdProbeCommandRecord? {
        val activeQueue = queue ?: throw IOException("ELM command queue unavailable")
        return try {
            val result = activeQueue.execute(ElmCommand(command = command, priority = if (command.startsWith("AT")) ElmCommandPriority.CONTROL else ElmCommandPriority.HIGH, timeoutMs = timeoutMs))
            val normalized = ElmResponseParser.normalizedText(result.rawResponse, command)
            var parsedValue: Double? = null
            var pidValid = false
            if (pid == 0x0C) { parsedValue = ObdPidParser.rpm(result.rawResponse); pidValid = parsedValue != null && parsedValue in 0.0..20000.0 }
            else if (pid == 0x0D) { parsedValue = ObdPidParser.vehicleSpeedKmh(result.rawResponse); pidValid = parsedValue != null && parsedValue in 0.0..255.0 }
            else if (pid == 0x00) pidValid = ObdPidParser.payloadsForMode01(result.rawResponse, 0x00, 4).isNotEmpty()
            var errorType = ElmResponseParser.classifyError(result.rawResponse, parserValid = if (pid == 0x0C || pid == 0x0D) { if (ElmResponseParser.containsToken(result.rawResponse, "NO DATA")) null else pidValid } else null)
            if (errorType == ObdProbeErrorType.NONE && pid != null && pid != 0x00 && !pidValid) errorType = ObdProbeErrorType.INVALID_PID_RESPONSE
            val record = ObdProbeCommandRecord(label, result.command, result.rawResponse, normalized, result.requestElapsedRealtimeNanos, result.firstByteElapsedRealtimeNanos, result.responseElapsedRealtimeNanos, result.latencyMs, result.firstByteLatencyMs, errorType == ObdProbeErrorType.NONE, errorType, parsedValue = parsedValue, pidMeasurementValid = pidValid && (pid == 0x0C || pid == 0x0D))
            probe.records += record
            probe.respondingCanIds += ElmResponseParser.extractCanResponderIds(result.rawResponse)
            if (pid == 0x0C && pidValid) probe.rpm = parsedValue
            if (pid == 0x0D && pidValid) probe.speedKmh = parsedValue
            record
        } catch (timeout: ElmCommandTimeoutException) {
            val now = SystemClock.elapsedRealtimeNanos()
            val record = ObdProbeCommandRecord(label, command.trim().uppercase(Locale.US), timeout.partialResponse, ElmResponseParser.normalizedText(timeout.partialResponse, command), timeout.requestElapsedRealtimeNanos, timeout.firstByteElapsedRealtimeNanos, now, if (timeout.requestElapsedRealtimeNanos > 0) (now - timeout.requestElapsedRealtimeNanos) / 1_000_000.0 else timeoutMs.toDouble(), if (timeout.firstByteElapsedRealtimeNanos > 0 && timeout.requestElapsedRealtimeNanos > 0) (timeout.firstByteElapsedRealtimeNanos - timeout.requestElapsedRealtimeNanos) / 1_000_000.0 else -1.0, false, ObdProbeErrorType.TIMEOUT, timeout.message)
            probe.records += record; record
        } catch (error: Throwable) {
            val now = SystemClock.elapsedRealtimeNanos()
            val record = ObdProbeCommandRecord(label, command.trim().uppercase(Locale.US), "", "", now, 0L, now, -1.0, -1.0, false, ObdProbeErrorType.TRANSPORT_ERROR, error.message)
            probe.records += record
            throw error
        }
    }

    private fun updateProbeProtocol(probe: ObdProbeResult, atdp: ObdProbeCommandRecord?, atdpn: ObdProbeCommandRecord?) {
        val description = ElmResponseParser.parseProtocolDescription(atdp?.rawResponse.orEmpty())
        val number = ElmResponseParser.parseProtocolNumber(atdpn?.rawResponse.orEmpty())
        probe.protocolInfo = ObdProtocolInfo(description.raw, description.description, number.raw, number.number, description.autoSelected || number.autoSelected)
    }

    private fun extractReportedFirmware(raw: String): String? {
        val lines = ElmResponseParser.normalizedLines(raw, "ATI")
        return lines.firstOrNull { it.contains("ELM", ignoreCase = true) } ?: lines.firstOrNull()?.takeIf { it != "?" }
    }
    private fun collectCanIds(probe: ObdProbeResult) { for (record in probe.records) probe.respondingCanIds += ElmResponseParser.extractCanResponderIds(record.rawResponse) }
    private fun capabilityStateFor(record: ObdProbeCommandRecord?): ObdCapabilityState {
        if (record == null) return ObdCapabilityState.NOT_VERIFIED
        if (record.errorType == ObdProbeErrorType.NO_DATA || record.errorType == ObdProbeErrorType.TIMEOUT) return ObdCapabilityState.NOT_VERIFIED
        val payloads = ObdPidParser.payloadsForMode01(record.rawResponse, 0x00, 4)
        if (payloads.isEmpty()) return ObdCapabilityState.INVALID
        return if (ElmResponseParser.isSuspiciousZeroCapabilityBitmap(record.rawResponse)) ObdCapabilityState.SUSPICIOUS_ZERO_CAPABILITY_BITMAP else ObdCapabilityState.VALID
    }
    private fun supportedPidsFromPid00(raw: String): Set<Int> {
        val payloads = ObdPidParser.payloadsForMode01(raw, 0x00, 4)
        if (payloads.isEmpty() || ElmResponseParser.isSuspiciousZeroCapabilityBitmap(raw)) return emptySet()
        var merged = 0L
        for (payload in payloads) merged = merged or (((payload[0].toLong() and 0xFF) shl 24) or ((payload[1].toLong() and 0xFF) shl 16) or ((payload[2].toLong() and 0xFF) shl 8) or (payload[3].toLong() and 0xFF))
        val supported = linkedSetOf<Int>()
        for (offset in 1..32) if ((merged and (1L shl (32 - offset))) != 0L) supported += offset
        return supported
    }
    private fun updatePidVerification(probe: ObdProbeResult, rpmRecord: ObdProbeCommandRecord?, speedRecord: ObdProbeCommandRecord?, supportedPids: Set<Int>) {
        probe.rpmPidStatus = pidStatusFor(rpmRecord, 0x0C, probe.capabilityState, supportedPids)
        probe.speedPidStatus = pidStatusFor(speedRecord, 0x0D, probe.capabilityState, supportedPids)
    }
    private fun pidStatusFor(record: ObdProbeCommandRecord?, pid: Int, capabilityState: ObdCapabilityState, supportedPids: Set<Int>): ObdPidVerificationStatus {
        if (record == null) return ObdPidVerificationStatus.NOT_VERIFIED
        if (record.pidMeasurementValid) return ObdPidVerificationStatus.SUPPORTED
        if (capabilityState == ObdCapabilityState.VALID && !supportedPids.contains(pid)) return ObdPidVerificationStatus.UNSUPPORTED
        return when (record.errorType) {
            ObdProbeErrorType.NO_DATA, ObdProbeErrorType.TIMEOUT, ObdProbeErrorType.UNABLE_TO_CONNECT, ObdProbeErrorType.CAN_ERROR, ObdProbeErrorType.BUS_ERROR -> ObdPidVerificationStatus.NO_RESPONSE
            ObdProbeErrorType.INVALID_PID_RESPONSE, ObdProbeErrorType.PARSER_ERROR -> ObdPidVerificationStatus.INVALID_RESPONSE
            else -> ObdPidVerificationStatus.NOT_VERIFIED
        }
    }
    private fun restoreRuntimeElmFormat(probe: ObdProbeResult) {
        if (transport?.isConnected != true || queue == null) return
        for (command in listOf("ATE0", "ATL0", "ATS0", "ATH0", "ATCAF1", "ATCFC1", "ATAT1", "ATSP0")) try { executeProbeCommand(probe, "RUNTIME RESTORE", command, 2500L) } catch (_: Throwable) {}
    }

'''
text = text[:start] + new + text[end:]
old = '''        val atdp = executeCommand("ATDP", 2500, countPerformance = false)
        val atdpn = executeCommand("ATDPN", 2500, countPerformance = false)
        synchronized(stateLock) {
            state.protocolDescription = ElmResponseParser.sanitizedText(atdp.rawResponse).ifBlank { null }
            state.protocolNumber = ElmResponseParser.sanitizedText(atdpn.rawResponse).ifBlank { null }
            state.protocolDescription?.let { prefs.edit().putString(KEY_PROTOCOL, it).apply() }
            state.connectionState = ObdConnectionState.CAPABILITY_SCANNING
        }
'''
new_protocol = '''        val atdp = executeCommand("ATDP", 2500, countPerformance = false)
        val atdpn = executeCommand("ATDPN", 2500, countPerformance = false)
        val parsedProtocol = ElmResponseParser.parseProtocolDescription(atdp.rawResponse)
        val parsedProtocolNumber = ElmResponseParser.parseProtocolNumber(atdpn.rawResponse)
        synchronized(stateLock) {
            state.protocolDescription = parsedProtocol.description ?: ElmResponseParser.sanitizedText(atdp.rawResponse).ifBlank { null }
            state.protocolNumber = parsedProtocolNumber.number ?: ElmResponseParser.sanitizedText(atdpn.rawResponse).ifBlank { null }
            state.protocolDescription?.let { prefs.edit().putString(KEY_PROTOCOL, it).apply() }
            state.connectionState = ObdConnectionState.CAPABILITY_SCANNING
        }
'''
if old not in text:
    raise SystemExit('normal protocol block not found')
text = text.replace(old, new_protocol)
p.write_text(text)
