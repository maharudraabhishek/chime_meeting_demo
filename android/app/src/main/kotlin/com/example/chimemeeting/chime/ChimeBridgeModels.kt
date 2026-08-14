package com.example.chimemeeting.chime

/** A validated, minimal session bootstrap payload received from Flutter. */
internal data class ChimeSessionBootstrap(
    val meetingId: String,
    val attendeeId: String,
    val externalUserId: String,
    val joinToken: String,
    val audioHostUrl: String,
    val audioFallbackUrl: String,
    val signalingUrl: String,
    val turnControlUrl: String,
    val eventIngestionUrl: String?,
) {
    /** Owns conversion from untyped platform-channel arguments. */
    companion object {
        /** Validates every required media/credential field before native startup. */
        fun from(arguments: Any?): ChimeSessionBootstrap {
            val map = arguments as? Map<*, *>
                ?: throw ChimeBridgeFailure(
                    ChimeBridgeContract.Error.INVALID_ARGUMENTS,
                    "Meeting session arguments are required.",
                )

            return ChimeSessionBootstrap(
                meetingId = map.requiredMediaString("meetingId"),
                attendeeId = map.requiredCredentialString("attendeeId"),
                externalUserId = map.requiredCredentialString("externalUserId"),
                joinToken = map.requiredCredentialString("joinToken"),
                audioHostUrl = map.requiredMediaString("audioHostUrl"),
                audioFallbackUrl = map.requiredMediaString("audioFallbackUrl"),
                signalingUrl = map.requiredMediaString("signalingUrl"),
                turnControlUrl = map.requiredMediaString("turnControlUrl"),
                eventIngestionUrl = map.optionalString("eventIngestionUrl"),
            )
        }
    }
}

/** Identifies which native PlatformView receives a Chime video tile. */
internal enum class ChimeVideoRole(val wireValue: String) {
    LOCAL("local"),
    REMOTE("remote");

    /** Owns conversion from Flutter PlatformView creation arguments. */
    companion object {
        /** Resolves the required local/remote role or rejects malformed input. */
        fun fromCreationArguments(arguments: Any?): ChimeVideoRole {
            val role = (arguments as? Map<*, *>)?.get("role") as? String
            return entries.firstOrNull { it.wireValue == role }
                ?: throw IllegalArgumentException("Video view role must be local or remote.")
        }
    }
}

/** Stable native failure surfaced to Flutter without raw SDK exception details. */
internal class ChimeBridgeFailure(
    val code: String,
    override val message: String,
) : RuntimeException(message)

/** Reads one required boolean command argument from a MethodChannel payload. */
internal fun Any?.requiredBoolean(name: String): Boolean {
    val map = this as? Map<*, *>
        ?: throw ChimeBridgeFailure(
            ChimeBridgeContract.Error.INVALID_ARGUMENTS,
            "Command arguments are required.",
        )
    return map[name] as? Boolean
        ?: throw ChimeBridgeFailure(
            ChimeBridgeContract.Error.INVALID_ARGUMENTS,
            "$name must be a boolean.",
        )
}

/** Reads a required Chime media field using the media-configuration error code. */
private fun Map<*, *>.requiredMediaString(name: String): String =
    requiredString(name, ChimeBridgeContract.Error.MISSING_MEDIA_CONFIGURATION)

/** Reads a required attendee field using the credential-validation error code. */
private fun Map<*, *>.requiredCredentialString(name: String): String =
    requiredString(name, ChimeBridgeContract.Error.INVALID_ATTENDEE_CREDENTIALS)

/** Reads a required non-blank string and reports a stable bridge error on failure. */
private fun Map<*, *>.requiredString(name: String, errorCode: String): String {
    val value = this[name] as? String
    if (value.isNullOrBlank()) {
        throw ChimeBridgeFailure(
            errorCode,
            "$name is required.",
        )
    }
    return value
}

/** Reads an optional non-blank string from a platform-channel payload. */
private fun Map<*, *>.optionalString(name: String): String? =
    (this[name] as? String)?.takeIf { it.isNotBlank() }
