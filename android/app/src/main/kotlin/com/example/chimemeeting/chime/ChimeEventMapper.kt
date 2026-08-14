package com.example.chimemeeting.chime

/** Produces the stable, credential-free wire envelope consumed by Flutter. */
internal object ChimeEventMapper {
    /** Creates one timestamped event with optional safe payload metadata. */
    fun event(
        type: String,
        payload: Map<String, Any?> = emptyMap(),
        generation: Int? = null,
    ): Map<String, Any?> =
        buildMap {
            put("type", type)
            put("timestampMs", System.currentTimeMillis())
            if (generation != null) {
                put("generation", generation)
            }
            put("payload", payload)
        }

    /** Creates a participant-presence event without exporting attendee identity. */
    fun participant(type: String, generation: Int? = null): Map<String, Any?> =
        event(type, generation = generation)

    /** Creates a safe session-error event from a stable bridge error code. */
    fun sessionError(code: String, message: String, generation: Int? = null): Map<String, Any?> =
        event(
            ChimeBridgeContract.Event.SESSION_ERROR,
            mapOf("code" to code, "message" to message),
            generation,
        )
}

