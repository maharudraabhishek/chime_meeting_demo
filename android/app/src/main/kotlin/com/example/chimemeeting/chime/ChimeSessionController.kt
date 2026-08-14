package com.example.chimemeeting.chime

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.amazonaws.services.chime.sdk.meetings.audiovideo.AttendeeInfo
import com.amazonaws.services.chime.sdk.meetings.audiovideo.AudioVideoObserver
import com.amazonaws.services.chime.sdk.meetings.audiovideo.SignalUpdate
import com.amazonaws.services.chime.sdk.meetings.audiovideo.VolumeUpdate
import com.amazonaws.services.chime.sdk.meetings.audiovideo.audio.activespeakerdetector.ActiveSpeakerObserver
import com.amazonaws.services.chime.sdk.meetings.audiovideo.audio.activespeakerpolicy.DefaultActiveSpeakerPolicy
import com.amazonaws.services.chime.sdk.meetings.audiovideo.video.DefaultVideoRenderView
import com.amazonaws.services.chime.sdk.meetings.audiovideo.video.RemoteVideoSource
import com.amazonaws.services.chime.sdk.meetings.audiovideo.video.VideoTileObserver
import com.amazonaws.services.chime.sdk.meetings.audiovideo.video.VideoTileState
import com.amazonaws.services.chime.sdk.meetings.device.DeviceChangeObserver
import com.amazonaws.services.chime.sdk.meetings.device.MediaDevice
import com.amazonaws.services.chime.sdk.meetings.realtime.RealtimeObserver
import com.amazonaws.services.chime.sdk.meetings.session.DefaultMeetingSession
import com.amazonaws.services.chime.sdk.meetings.session.MeetingSession
import com.amazonaws.services.chime.sdk.meetings.session.MeetingSessionConfiguration
import com.amazonaws.services.chime.sdk.meetings.session.MeetingSessionCredentials
import com.amazonaws.services.chime.sdk.meetings.session.MeetingSessionStatus
import com.amazonaws.services.chime.sdk.meetings.session.MeetingSessionURLs
import com.amazonaws.services.chime.sdk.meetings.session.defaultUrlRewriter

/**
 * Owns the single active native meeting and every Chime observer registration.
 *
 * Platform views do not own meeting state. They register their render surfaces
 * here, allowing a tile and view to arrive in either order. All attendee
 * credentials are discarded during deterministic session cleanup.
 */
internal class ChimeSessionController(
    context: Context,
    private val logger: SafeChimeLogger,
    private val publishEvent: (Map<String, Any?>) -> Unit,
) : AudioVideoObserver,
    RealtimeObserver,
    VideoTileObserver,
    ActiveSpeakerObserver,
    DeviceChangeObserver {
    private val applicationContext = context.applicationContext

    private var meetingSession: MeetingSession? = null
    private var localAttendeeId: String? = null
    private var localTileId: Int? = null
    private var remoteTileId: Int? = null
    private var localVideoView: DefaultVideoRenderView? = null
    private var remoteVideoView: DefaultVideoRenderView? = null
    private var microphoneEnabled: Boolean? = null
    private var cameraEnabled: Boolean? = null
    private var sessionGeneration = 0
    private var sessionStartedEmitted = false
    private var sessionStoppedEmitted = false
    private var cleaningUp = false
    private var lastVolumeEventAtMs = 0L

    override val scoreCallbackIntervalMs: Int? = null

    /** Creates and starts a session after validating required runtime grants. */
    @Synchronized
    fun startSession(bootstrap: ChimeSessionBootstrap) {
        if (meetingSession != null || cleaningUp) {
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.SESSION_ALREADY_ACTIVE,
                "A meeting session is already active.",
            )
        }
        requireSupportedRuntime()
        requireMediaPermissions()
        logger.registerSensitiveValue(bootstrap.joinToken)
        logger.registerSensitiveValue(bootstrap.attendeeId)
        logger.registerSensitiveValue(bootstrap.externalUserId)

        val session = try {
            val credentials = MeetingSessionCredentials(
                bootstrap.attendeeId,
                bootstrap.externalUserId,
                bootstrap.joinToken,
            )
            val urls = MeetingSessionURLs(
                bootstrap.audioFallbackUrl,
                bootstrap.audioHostUrl,
                bootstrap.turnControlUrl,
                bootstrap.signalingUrl,
                ::defaultUrlRewriter,
                bootstrap.eventIngestionUrl,
            )
            DefaultMeetingSession(
                MeetingSessionConfiguration(bootstrap.meetingId, credentials, urls),
                logger,
                applicationContext,
            )
        } catch (error: LinkageError) {
            logger.clearSensitiveValues()
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.NATIVE_INITIALIZATION,
                "Amazon Chime native media libraries could not be loaded.",
            )
        } catch (error: Exception) {
            logger.clearSensitiveValues()
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.NATIVE_INITIALIZATION,
                "Amazon Chime could not initialize the meeting session.",
            )
        }

        sessionGeneration += 1
        meetingSession = session
        localAttendeeId = bootstrap.attendeeId
        resetSessionFlags()

        try {
            session.audioVideo.addAudioVideoObserver(this)
            session.audioVideo.addRealtimeObserver(this)
            session.audioVideo.addVideoTileObserver(this)
            session.audioVideo.addActiveSpeakerObserver(
                DefaultActiveSpeakerPolicy(),
                this,
            )
            session.audioVideo.addDeviceChangeObserver(this)
            session.audioVideo.start()
        } catch (error: LinkageError) {
            cleanupSession(stopSession = true, emitStopped = false, reason = null)
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.NATIVE_INITIALIZATION,
                "Amazon Chime native media libraries could not be loaded.",
            )
        } catch (error: Exception) {
            cleanupSession(stopSession = true, emitStopped = false, reason = null)
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.MEETING_START,
                "Amazon Chime could not start the meeting session.",
            )
        }
    }

    /** Applies microphone state only when the SDK confirms command acceptance. */
    @Synchronized
    fun setMicrophoneEnabled(enabled: Boolean): Boolean {
        val audioVideo = meetingSession?.audioVideo ?: unavailableSession()
        val succeeded = try {
            if (enabled) audioVideo.realtimeLocalUnmute() else audioVideo.realtimeLocalMute()
        } catch (error: Exception) {
            false
        }
        if (!succeeded) {
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.MICROPHONE_OPERATION,
                "The microphone state could not be changed.",
            )
        }
        emitMicrophoneState(enabled)
        return microphoneEnabled == true
    }

    /**
     * Requests local camera transmission state.
     *
     * Command completion only means Chime accepted the operation. The video-tile
     * callbacks remain the source of truth for actual camera availability.
     */
    @Synchronized
    fun setCameraEnabled(enabled: Boolean): Boolean {
        val audioVideo = meetingSession?.audioVideo ?: unavailableSession()
        if (cameraEnabled == enabled) return enabled
        try {
            if (enabled) {
                audioVideo.startLocalVideo()
            } else {
                audioVideo.stopLocalVideo()
                emitCameraState(false)
            }
        } catch (error: Exception) {
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.CAMERA_OPERATION,
                "The camera state could not be changed.",
            )
        }

        return enabled
    }

    @Volatile
    private var switchInProgress = false

    /** Attempts to switch between available cameras using the Chime SDK typed API. */
    @Synchronized
    fun switchCamera(): Boolean {
        val audioVideo = meetingSession?.audioVideo ?: unavailableSession()
        if (cameraEnabled != true || localTileId == null) {
            return false
        }
        if (switchInProgress) {
            // Prevent rapid duplicate requests.
            return false
        }
        switchInProgress = true
        try {
            // Use the typed SDK API available in the pinned Chime SDK (no reflection).
            // This should call the concrete camera-switch method on the audioVideo controller.
            audioVideo.switchCamera()
            return true
        } catch (error: NoSuchMethodError) {
            // SDK does not expose the typed API (unexpected given pinned dependency).
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.CAMERA_OPERATION,
                "Camera switch not supported by installed Chime SDK.",
            )
        } catch (error: Exception) {
            logger.warn(TAG, "Camera switch failed: ${error.javaClass.simpleName}.")
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.CAMERA_OPERATION,
                "The camera switch operation failed.",
            )
        } finally {
            switchInProgress = false
        }
    }

    /** Leaves the active meeting; repeating the command is safe. */
    @Synchronized
    fun leaveSession() {
        if (meetingSession == null) return
        sessionGeneration += 1
        cleanupSession(stopSession = true, emitStopped = true, reason = "left")
    }

    /** Releases native session resources; repeating disposal is safe. */
    @Synchronized
    fun disposeSession() {
        if (meetingSession == null) {
            logger.clearSensitiveValues()
            return
        }
        sessionGeneration += 1
        cleanupSession(stopSession = true, emitStopped = true, reason = "disposed")
    }

    /** Registers a Flutter-owned native render view and binds any earlier tile. */
    @Synchronized
    fun attachVideoView(role: ChimeVideoRole, view: DefaultVideoRenderView) {
        when (role) {
            ChimeVideoRole.LOCAL -> {
                localVideoView?.takeIf { it !== view }?.let { unbindTile(localTileId) }
                localVideoView = view
                view.mirror = true
                bindIfReady(localTileId, view)
            }
            ChimeVideoRole.REMOTE -> {
                remoteVideoView?.takeIf { it !== view }?.let { unbindTile(remoteTileId) }
                remoteVideoView = view
                view.mirror = false
                bindIfReady(remoteTileId, view)
            }
        }
    }

    /** Unbinds a disposed PlatformView without affecting the meeting lifecycle. */
    @Synchronized
    fun detachVideoView(role: ChimeVideoRole, view: DefaultVideoRenderView) {
        when (role) {
            ChimeVideoRole.LOCAL -> if (localVideoView === view) {
                unbindTile(localTileId)
                localVideoView = null
            }
            ChimeVideoRole.REMOTE -> if (remoteVideoView === view) {
                unbindTile(remoteTileId)
                remoteVideoView = null
            }
        }
    }

    /** Establishes the session generation before publishing session-owned media events. */
    override fun onAudioSessionStarted(reconnecting: Boolean) {
        if (cleaningUp || meetingSession == null) return
        val audioVideo = meetingSession?.audioVideo ?: return

        if (!sessionStartedEmitted) {
            try {
                // SESSION_STARTED must be the first startup event for this
                // generation. Dart establishes the active generation from this
                // callback before accepting microphone/video/attendee events.
                sessionStartedEmitted = true

                publishEvent(
                    ChimeEventMapper.event(
                        ChimeBridgeContract.Event.SESSION_STARTED,
                        generation = sessionGeneration,
                    ),
                )

                publishEvent(
                    ChimeEventMapper.event(
                        ChimeBridgeContract.Event.AUDIO_SESSION_STARTED,
                        generation = sessionGeneration,
                    ),
                )

                emitMicrophoneState(true)
                audioVideo.startRemoteVideo()
                audioVideo.startLocalVideo()
            } catch (error: LinkageError) {
                publishEvent(
                    ChimeEventMapper.sessionError(
                        ChimeBridgeContract.Error.NATIVE_INITIALIZATION,
                        "Amazon Chime native media could not be loaded.",
                        sessionGeneration,
                    ),
                )
                cleanupSession(
                    stopSession = true,
                    emitStopped = true,
                    reason = "nativeMediaFailure",
                )
            } catch (error: Exception) {
                publishEvent(
                    ChimeEventMapper.sessionError(
                        ChimeBridgeContract.Error.MEETING_START,
                        "Amazon Chime media could not start.",
                        sessionGeneration,
                    ),
                )
                cleanupSession(
                    stopSession = true,
                    emitStopped = true,
                    reason = "startFailure",
                )
            }

            return
        }

        if (reconnecting) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.CONNECTION_RECOVERED,
                    generation = sessionGeneration,
                ),
            )

            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.AUDIO_SESSION_STARTED,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Converts an unexpected Chime stop into a safe terminal event and cleanup. */
    override fun onAudioSessionStopped(sessionStatus: MeetingSessionStatus) {
        if (cleaningUp || meetingSession == null) return
        val reason = sessionStatus.statusCode?.name ?: "unknown"

        // Emit an explicit audio-session-stopped semantic event (do not collapse).
        publishEvent(
            ChimeEventMapper.event(
                ChimeBridgeContract.Event.AUDIO_SESSION_STOPPED,
                reason?.let { mapOf("reason" to it) } ?: emptyMap(),
                sessionGeneration,
            ),
        )

        if (reason != "OK" && reason != "Left") {
            val credentialsRejected = reason == "AudioAuthenticationRejected"
            publishEvent(
                ChimeEventMapper.sessionError(
                    if (credentialsRejected) ChimeBridgeContract.Error.INVALID_ATTENDEE_CREDENTIALS
                    else ChimeBridgeContract.Error.MEETING_START,
                    if (credentialsRejected) "Amazon Chime rejected the attendee credentials."
                    else "Amazon Chime stopped the meeting session ($reason).",
                    sessionGeneration,
                ),
            )
        }
        cleanupSession(stopSession = false, emitStopped = true, reason = reason)
    }

    /** Reconnect cancellation is not a new reconnect attempt. */
    override fun onAudioSessionCancelledReconnect() = Unit

    /** Chime automatically attempts reconnection after a dropped audio session. */
    override fun onAudioSessionDropped() {
        if (!cleaningUp && meetingSession != null) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.SESSION_RECONNECTING,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Emits reconnecting only for an SDK-reported reconnect sequence. */
    override fun onAudioSessionStartedConnecting(reconnecting: Boolean) {
        if (reconnecting && !cleaningUp && meetingSession != null) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.SESSION_RECONNECTING,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Clears camera state if the SDK reports local send capability unavailable. */
    override fun onCameraSendAvailabilityUpdated(available: Boolean) {
        if (!available) emitCameraState(false)
    }

    /** Marks a degraded connection while preserving the same active meeting session. */
    override fun onConnectionBecamePoor() {
        if (!cleaningUp && meetingSession != null) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.CONNECTION_POOR,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Confirms the active session has recovered and the RTC path is healthy again. */
    override fun onConnectionRecovered() {
        if (!cleaningUp && meetingSession != null) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.CONNECTION_RECOVERED,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Ignores source discovery because the UI renders one remote tile. */
    override fun onRemoteVideoSourceAvailable(sources: List<RemoteVideoSource>) = Unit

    /** Ignores source-removal callbacks; tile callbacks own rendered availability. */
    override fun onRemoteVideoSourceUnavailable(sources: List<RemoteVideoSource>) = Unit

    /** Ignores separate video-session status because audio start owns connection state. */
    override fun onVideoSessionStarted(sessionStatus: MeetingSessionStatus) = Unit

    /** Ignores video connection progress until video-tile availability is reported. */
    override fun onVideoSessionStartedConnecting() = Unit

    /** Clears local camera/tile state when the Chime video session stops. */
    override fun onVideoSessionStopped(sessionStatus: MeetingSessionStatus) {
        if (cleaningUp) return
        clearLocalVideoState()
    }

    /** Emits one identity-free participant-presence event for each remote attendee. */
    override fun onAttendeesJoined(attendeeInfo: Array<AttendeeInfo>) {
        attendeeInfo.filter(::isRemoteParticipant).forEach {
            publishEvent(
                ChimeEventMapper.participant(
                    ChimeBridgeContract.Event.PARTICIPANT_JOINED,
                    sessionGeneration,
                ),
            )
        }
    }

    /** Maps remote attendee departures into the required participant-left event. */
    override fun onAttendeesLeft(attendeeInfo: Array<AttendeeInfo>) = emitParticipantLeft(attendeeInfo)

    /** Treats dropped remote attendees as departures in the safe event model. */
    override fun onAttendeesDropped(attendeeInfo: Array<AttendeeInfo>) = emitParticipantLeft(attendeeInfo)

    /** Reconciles microphone mute/unmute from the Chime realtime observer. */
    override fun onAttendeesMuted(attendeeInfo: Array<AttendeeInfo>) {
        // Emit local mute if it contains the local attendee.
        if (attendeeInfo.any { it.attendeeId == localAttendeeId }) {
            emitMicrophoneState(false)
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.LOCAL_MUTED,
                    generation = sessionGeneration,
                ),
            )
        }
        // Publish remote mute events for other attendees (identity-free semantics).
        attendeeInfo.filter { it.attendeeId != localAttendeeId }
            .filter(::isRemoteParticipant)
            .forEach {
                publishEvent(
                    ChimeEventMapper.event(
                        ChimeBridgeContract.Event.REMOTE_MUTED,
                        generation = sessionGeneration,
                    ),
                )
            }
    }

    /** Reconciles microphone unmute from the Chime realtime observer. */
    override fun onAttendeesUnmuted(attendeeInfo: Array<AttendeeInfo>) {
        // Emit local unmute if it contains the local attendee.
        if (attendeeInfo.any { it.attendeeId == localAttendeeId }) {
            emitMicrophoneState(true)
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.LOCAL_UNMUTED,
                    generation = sessionGeneration,
                ),
            )
        }
        // Publish remote unmute events for other attendees (identity-free semantics).
        attendeeInfo.filter { it.attendeeId != localAttendeeId }
            .filter(::isRemoteParticipant)
            .forEach {
                publishEvent(
                    ChimeEventMapper.event(
                        ChimeBridgeContract.Event.REMOTE_UNMUTED,
                        generation = sessionGeneration,
                    ),
                )
            }
    }

    /** Ignores raw signal telemetry; diagnostics expose only coarse quality. */
    override fun onSignalStrengthChanged(signalUpdates: Array<SignalUpdate>) = Unit

    /** Emits bounded volume telemetry without allowing callbacks to flood the event log. */
    override fun onVolumeChanged(volumeUpdates: Array<VolumeUpdate>) {
        if (cleaningUp || meetingSession == null || volumeUpdates.isEmpty()) return

        val now = System.currentTimeMillis()
        if (now - lastVolumeEventAtMs < VOLUME_EVENT_INTERVAL_MS) return
        lastVolumeEventAtMs = now

        publishEvent(
            ChimeEventMapper.event(
                ChimeBridgeContract.Event.VOLUME_LEVEL,
                mapOf("count" to volumeUpdates.size),
                sessionGeneration,
            ),
        )
    }

    /** Emits one identity-free active-speaker indication. */
    override fun onActiveSpeakerDetected(attendeeInfo: Array<AttendeeInfo>) {
        if (cleaningUp || meetingSession == null || attendeeInfo.isEmpty()) return

        publishEvent(
            ChimeEventMapper.event(
                ChimeBridgeContract.Event.ACTIVE_SPEAKER,
                generation = sessionGeneration,
            ),
        )
    }

    /** Score telemetry is intentionally disabled by scoreCallbackIntervalMs = null. */
    override fun onActiveSpeakerScoreChanged(
        scores: Map<AttendeeInfo, Double>,
    ) = Unit

    /** Emits safe audio-device changes without exposing platform objects to Flutter. */
    override fun onAudioDeviceChanged(
        freshAudioDeviceList: List<MediaDevice>,
    ) {
        if (cleaningUp || meetingSession == null) return

        val activeType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            try {
                meetingSession
                    ?.audioVideo
                    ?.getActiveAudioDevice()
                    ?.type
                    ?.toString()
            } catch (_: LinkageError) {
                null
            } catch (_: Exception) {
                null
            }
        } else {
            null
        }

        val payload = buildMap<String, Any?> {
            put("availableCount", freshAudioDeviceList.size)

            if (activeType != null) {
                put("activeType", activeType)
            }
        }

        publishEvent(
            ChimeEventMapper.event(
                ChimeBridgeContract.Event.AUDIO_DEVICE_CHANGED,
                payload,
                sessionGeneration,
            ),
        )
    }

    /** Tracks and binds one local or one remote non-content video tile. */
    override fun onVideoTileAdded(tileState: VideoTileState) {
        if (cleaningUp || tileState.isContent) return
        if (tileState.isLocalTile) {
            localTileId?.takeIf { it != tileState.tileId }?.let(::unbindTile)
            localTileId = tileState.tileId
            bindIfReady(localTileId, localVideoView)
            emitCameraState(true)
            publishEvent(ChimeEventMapper.event(ChimeBridgeContract.Event.LOCAL_VIDEO_AVAILABLE, generation = sessionGeneration))
        } else {
            remoteTileId?.takeIf { it != tileState.tileId }?.let(::unbindTile)
            remoteTileId = tileState.tileId
            bindIfReady(remoteTileId, remoteVideoView)
            publishEvent(ChimeEventMapper.event(ChimeBridgeContract.Event.REMOTE_VIDEO_AVAILABLE, generation = sessionGeneration))
        }
    }

    /** Unbinds a removed tile and emits the corresponding availability event. */
    override fun onVideoTileRemoved(tileState: VideoTileState) {
        when (tileState.tileId) {
            localTileId -> {
                clearLocalVideoState()
            }
            remoteTileId -> {
                unbindTile(remoteTileId)
                remoteTileId = null
                publishEvent(ChimeEventMapper.event(ChimeBridgeContract.Event.REMOTE_VIDEO_REMOVED, generation = sessionGeneration))
            }
        }
    }

    /** Emits a paused event for the local or remote tile when reported by SDK. */
    override fun onVideoTilePaused(tileState: VideoTileState) {
        if (cleaningUp) return
        if (tileState.isContent) return
        if (tileState.isLocalTile) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.LOCAL_VIDEO_PAUSED,
                    generation = sessionGeneration,
                ),
            )
        } else {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.REMOTE_VIDEO_PAUSED,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Emits a resumed event for the local or remote tile when reported by SDK. */
    override fun onVideoTileResumed(tileState: VideoTileState) {
        if (cleaningUp) return
        if (tileState.isContent) return
        if (tileState.isLocalTile) {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.LOCAL_VIDEO_RESUMED,
                    generation = sessionGeneration,
                ),
            )
        } else {
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.REMOTE_VIDEO_RESUMED,
                    generation = sessionGeneration,
                ),
            )
        }
    }

    /** Ignores native tile-size changes because Flutter owns surface layout. */
    override fun onVideoTileSizeChanged(tileState: VideoTileState) = Unit

    /** Rejects unsupported CPU runtimes before Amazon Chime loads native media. */
    private fun requireSupportedRuntime() {
        val primaryAbi = Build.SUPPORTED_ABIS
            .firstOrNull()
            ?.lowercase()
            .orEmpty()
        val runtimeArch = System.getProperty("os.arch")
            ?.lowercase()
            .orEmpty()

        // Check both Android's preferred ABI and the actual VM/runtime
        // architecture. This also rejects x86 emulators that advertise
        // translated/secondary ARM ABI support.
        val isX86Runtime =
            primaryAbi == "x86" ||
                primaryAbi == "x86_64" ||
                runtimeArch == "x86" ||
                runtimeArch == "x86_64" ||
                runtimeArch == "amd64" ||
                runtimeArch == "i386" ||
                runtimeArch == "i686"

        val isArmRuntime =
            primaryAbi == "arm64-v8a" ||
                primaryAbi == "armeabi-v7a" ||
                runtimeArch == "aarch64" ||
                runtimeArch == "arm64" ||
                runtimeArch == "arm64-v8a" ||
                runtimeArch == "armeabi-v7a" ||
                runtimeArch.startsWith("arm")

        if (isX86Runtime || !isArmRuntime) {
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.UNSUPPORTED_RUNTIME,
                "Amazon Chime media requires an ARM or ARM64 Android runtime.",
            )
        }
    }

    /** Rejects native startup unless microphone and camera grants are present. */
    private fun requireMediaPermissions() {
        val missing = listOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.CAMERA)
            .filter { permission ->
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                    applicationContext.checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED
            }
        if (missing.isNotEmpty()) {
            throw ChimeBridgeFailure(
                ChimeBridgeContract.Error.PERMISSION_UNAVAILABLE,
                "Microphone and camera permissions are required before starting a meeting.",
            )
        }
    }

    /** Emits identity-free participant-left events for remote attendees only. */
    private fun emitParticipantLeft(attendeeInfo: Array<AttendeeInfo>) {
        attendeeInfo.filter(::isRemoteParticipant).forEach {
            publishEvent(
                ChimeEventMapper.participant(
                    ChimeBridgeContract.Event.PARTICIPANT_LEFT,
                    sessionGeneration,
                ),
            )
        }
    }

    /** Excludes the local attendee and Chime content-share attendees. */
    private fun isRemoteParticipant(attendee: AttendeeInfo): Boolean =
        attendee.attendeeId != localAttendeeId && !attendee.attendeeId.endsWith("#content")

    /** Emits microphone state only when the confirmed value actually changes. */
    private fun emitMicrophoneState(enabled: Boolean) {
        if (microphoneEnabled == enabled) return
        microphoneEnabled = enabled
        publishEvent(
            ChimeEventMapper.event(
                if (enabled) ChimeBridgeContract.Event.MICROPHONE_ENABLED
                else ChimeBridgeContract.Event.MICROPHONE_DISABLED,
                generation = sessionGeneration,
            ),
        )
    }

    /** Emits camera state only when callback-confirmed availability changes. */
    private fun emitCameraState(enabled: Boolean) {
        if (cameraEnabled == enabled) return
        cameraEnabled = enabled
        publishEvent(
            ChimeEventMapper.event(
                if (enabled) ChimeBridgeContract.Event.CAMERA_ENABLED
                else ChimeBridgeContract.Event.CAMERA_DISABLED,
                generation = sessionGeneration,
            ),
        )
    }

    /** Unbinds the local tile and resets camera/video availability atomically. */
    private fun clearLocalVideoState() {
        val tileId = localTileId
        if (tileId != null) {
            unbindTile(tileId)
            localTileId = null
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.LOCAL_VIDEO_REMOVED,
                    generation = sessionGeneration,
                ),
            )
        }
        emitCameraState(false)
    }

    /** Binds a tile when both the SDK tile and Flutter-owned native view exist. */
    private fun bindIfReady(tileId: Int?, view: DefaultVideoRenderView?) {
        if (tileId == null || view == null) return
        try {
            meetingSession?.audioVideo?.bindVideoView(view, tileId)
        } catch (error: LinkageError) {
            publishEvent(
                ChimeEventMapper.sessionError(
                    ChimeBridgeContract.Error.PLATFORM_BRIDGE,
                    "A video tile could not be bound to its native view.",
                    sessionGeneration,
                ),
            )
        } catch (error: Exception) {
            publishEvent(
                ChimeEventMapper.sessionError(
                    ChimeBridgeContract.Error.PLATFORM_BRIDGE,
                    "A video tile could not be bound to its native view.",
                    sessionGeneration,
                ),
            )
        }
    }

    /** Best-effort unbinds one Chime video tile during removal or cleanup. */
    private fun unbindTile(tileId: Int?) {
        if (tileId == null) return
        try {
            meetingSession?.audioVideo?.unbindVideoView(tileId)
        } catch (_: LinkageError) {
            logger.warn(TAG, "A video tile could not be unbound during cleanup.")
        } catch (_: Exception) {
            logger.warn(TAG, "A video tile could not be unbound during cleanup.")
        }
    }

    /** Clears per-session media flags before observers and media start. */
    private fun resetSessionFlags() {
        localTileId = null
        remoteTileId = null
        microphoneEnabled = null
        cameraEnabled = null
        sessionStartedEmitted = false
        sessionStoppedEmitted = false
        cleaningUp = false
        lastVolumeEventAtMs = 0L
        switchInProgress = false
    }

    /** Performs idempotent observer, media, view, credential, and session cleanup. */
    private fun cleanupSession(stopSession: Boolean, emitStopped: Boolean, reason: String?) {
        val session = meetingSession ?: return
        if (cleaningUp) return
        cleaningUp = true
        val audioVideo = session.audioVideo

        runCleanupStep("Local video could not be stopped during cleanup.") {
            audioVideo.stopLocalVideo()
        }
        runCleanupStep("Remote video could not be stopped during cleanup.") {
            audioVideo.stopRemoteVideo()
        }

        unbindTile(localTileId)
        unbindTile(remoteTileId)

        runCleanupStep("Active speaker observer could not be removed during cleanup.") {
            audioVideo.removeActiveSpeakerObserver(this)
        }
        runCleanupStep("Device change observer could not be removed during cleanup.") {
            audioVideo.removeDeviceChangeObserver(this)
        }
        runCleanupStep("Video tile observer could not be removed during cleanup.") {
            audioVideo.removeVideoTileObserver(this)
        }

        runCleanupStep("Realtime observer could not be removed during cleanup.") {
            audioVideo.removeRealtimeObserver(this)
        }
        runCleanupStep("Audio/video observer could not be removed during cleanup.") {
            audioVideo.removeAudioVideoObserver(this)
        }
        if (stopSession) {
            runCleanupStep("The meeting session could not be stopped cleanly.") {
                audioVideo.stop()
            }
        }

        meetingSession = null
        localAttendeeId = null
        localTileId = null
        remoteTileId = null
        microphoneEnabled = null
        cameraEnabled = null
        logger.clearSensitiveValues()
        cleaningUp = false

        if (emitStopped && !sessionStoppedEmitted) {
            sessionStoppedEmitted = true
            publishEvent(
                ChimeEventMapper.event(
                    ChimeBridgeContract.Event.SESSION_STOPPED,
                    reason?.let { mapOf("reason" to it) } ?: emptyMap(),
                    sessionGeneration,
                ),
            )
        }
    }

    /** Runs one cleanup action without allowing teardown failures to cascade. */
    private inline fun runCleanupStep(message: String, action: () -> Unit) {
        try {
            action()
        } catch (_: LinkageError) {
            logger.warn(TAG, message)
        } catch (_: Exception) {
            logger.warn(TAG, message)
        }
    }

    /** Produces the stable error used when a control has no active session. */
    private fun unavailableSession(): Nothing = throw ChimeBridgeFailure(
        ChimeBridgeContract.Error.SESSION_UNAVAILABLE,
        "No meeting session is active.",
    )

    /** Native log tag for session-controller diagnostics. */
    private companion object {
        const val TAG = "ChimeSessionController"
        const val VOLUME_EVENT_INTERVAL_MS = 1_000L
    }
}
