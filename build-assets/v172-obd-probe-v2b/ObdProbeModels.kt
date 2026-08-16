package com.scdeport.scdrive.obd

enum class ObdProbeErrorType {
    NONE,
    TRANSPORT_ERROR,
    TIMEOUT,
    ELM_UNKNOWN_COMMAND,
    NO_DATA,
    CAN_ERROR,
    BUS_ERROR,
    UNABLE_TO_CONNECT,
    PARSER_ERROR,
    INVALID_PID_RESPONSE,
    STALE_RESPONSE,
    COMMAND_OVERLAP,
}

enum class ObdPidVerificationStatus {
    SUPPORTED,
    UNSUPPORTED,
    NO_RESPONSE,
    NOT_VERIFIED,
    INVALID_RESPONSE,
}

enum class ObdCapabilityState {
    VALID,
    SUSPICIOUS_ZERO_CAPABILITY_BITMAP,
    INVALID,
    NOT_VERIFIED,
}

data class ObdProtocolInfo(
    val rawDescription: String?,
    val description: String?,
    val numberRaw: String?,
    val number: String?,
    val autoSelected: Boolean,
)

data class ObdProbeCommandRecord(
    val label: String,
    val command: String,
    val rawResponse: String,
    val normalizedResponse: String,
    val requestStartNs: Long,
    val firstByteNs: Long,
    val completedNs: Long,
    val roundTripLatencyMs: Double,
    val firstByteLatencyMs: Double,
    val success: Boolean,
    val errorType: ObdProbeErrorType,
    val errorMessage: String? = null,
    val parsedValue: Double? = null,
    val pidMeasurementValid: Boolean = false,
)

data class ObdProbeResult(
    val connectionStateAtProbeStart: String,
    val probeStartWallClockMs: Long = System.currentTimeMillis(),
    val probeStartElapsedNs: Long = android.os.SystemClock.elapsedRealtimeNanos(),
    var connectionStateDuringProbe: String,
    var connectionStateAtProbeEnd: String,
    var probeCompletedSuccessfully: Boolean = false,
    var transportClosedAfterProbe: Boolean = false,
    val records: MutableList<ObdProbeCommandRecord> = mutableListOf(),
    val respondingCanIds: MutableSet<String> = linkedSetOf(),
    var capabilityState: ObdCapabilityState = ObdCapabilityState.NOT_VERIFIED,
    var speedPidStatus: ObdPidVerificationStatus = ObdPidVerificationStatus.NOT_VERIFIED,
    var rpmPidStatus: ObdPidVerificationStatus = ObdPidVerificationStatus.NOT_VERIFIED,
    var speedKmh: Double? = null,
    var rpm: Double? = null,
    var protocolInfo: ObdProtocolInfo = ObdProtocolInfo(null, null, null, null, false),
    var reportedFirmware: String? = null,
    var secondPassExecuted: Boolean = false,
)
