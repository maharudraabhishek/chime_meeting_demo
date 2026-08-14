package com.example.chimemeeting.chime

/** Centralizes every Flutter/native identifier used by the Chime bridge. */
internal object ChimeBridgeContract {
    const val METHOD_CHANNEL = "com.example.chimemeeting/chime/methods"
    const val EVENT_CHANNEL = "com.example.chimemeeting/chime/events"
    const val VIDEO_VIEW_TYPE = "com.example.chimemeeting/chime/video"

    /** Flutter-to-Android command names. */
    object Method {
        const val START_SESSION = "startSession"
        const val SET_MICROPHONE_ENABLED = "setMicrophoneEnabled"
        const val SET_CAMERA_ENABLED = "setCameraEnabled"
        const val SWITCH_CAMERA = "switchCamera"
        const val LEAVE_SESSION = "leaveSession"
        const val DISPOSE_SESSION = "disposeSession"
    }

    /** Android-to-Flutter normalized event names. */
    object Event {
        const val SESSION_STARTED = "sessionStarted"
        const val SESSION_STOPPED = "sessionStopped"
        const val SESSION_RECONNECTING = "sessionReconnecting"
        const val CONNECTION_POOR = "connectionPoor"
        const val CONNECTION_RECOVERED = "connectionRecovered"
        const val PARTICIPANT_JOINED = "participantJoined"
        const val PARTICIPANT_LEFT = "participantLeft"
        const val LOCAL_VIDEO_AVAILABLE = "localVideoAvailable"
        const val LOCAL_VIDEO_REMOVED = "localVideoRemoved"
        const val REMOTE_VIDEO_AVAILABLE = "remoteVideoAvailable"
        const val REMOTE_VIDEO_REMOVED = "remoteVideoRemoved"
        const val LOCAL_VIDEO_PAUSED = "localVideoPaused"
        const val LOCAL_VIDEO_RESUMED = "localVideoResumed"
        const val REMOTE_VIDEO_PAUSED = "remoteVideoPaused"
        const val REMOTE_VIDEO_RESUMED = "remoteVideoResumed"
        const val MICROPHONE_ENABLED = "microphoneEnabled"
        const val MICROPHONE_DISABLED = "microphoneDisabled"
        const val CAMERA_ENABLED = "cameraEnabled"
        const val CAMERA_DISABLED = "cameraDisabled"
        // Distinct audio session lifecycle events (do not collapse into sessionStarted/sessionStopped)
        const val AUDIO_SESSION_STARTED = "audioSessionStarted"
        const val AUDIO_SESSION_STOPPED = "audioSessionStopped"
        // Local vs remote mute semantics
        const val LOCAL_MUTED = "localMuted"
        const val LOCAL_UNMUTED = "localUnmuted"
        const val REMOTE_MUTED = "remoteMuted"
        const val REMOTE_UNMUTED = "remoteUnmuted"
        const val ACTIVE_SPEAKER = "activeSpeaker"
        const val VOLUME_LEVEL = "volumeLevel"
        const val AUDIO_DEVICE_CHANGED = "audioDeviceChanged"
        const val SESSION_ERROR = "sessionError"
    }

    /** Stable bridge error codes mapped into typed Dart failures. */
    object Error {
        const val INVALID_ARGUMENTS = "invalid_arguments"
        const val MISSING_MEDIA_CONFIGURATION = "missing_media_configuration"
        const val INVALID_ATTENDEE_CREDENTIALS = "invalid_attendee_credentials"
        const val PERMISSION_UNAVAILABLE = "permission_unavailable"
        const val UNSUPPORTED_RUNTIME = "unsupported_runtime"
        const val NATIVE_INITIALIZATION = "native_chime_initialization_failure"
        const val MEETING_START = "meeting_start_failure"
        const val MICROPHONE_OPERATION = "microphone_operation_failure"
        const val CAMERA_OPERATION = "camera_operation_failure"
        const val SESSION_ALREADY_ACTIVE = "session_already_active"
        const val SESSION_UNAVAILABLE = "session_unavailable"
        const val PLATFORM_BRIDGE = "platform_bridge_failure"
    }
}
