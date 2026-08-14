import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_media_event.dart';
import 'chime_web_bridge_client.dart';

/// Strictly maps the small browser callback vocabulary into domain events.
final class WebBridgeEventDecoder {
  const WebBridgeEventDecoder();

  MeetingMediaEvent? decode(WebBridgeEventData data, {DateTime? occurredAt}) {
    if (data.generation < 1 || data.type.isEmpty) {
      return null;
    }

    final type = switch (data.type) {
      'sessionStarted' => MeetingMediaEventType.sessionStarted,
      'sessionStopped' => MeetingMediaEventType.sessionStopped,
      'audioSessionStarted' => MeetingMediaEventType.audioSessionStarted,
      'audioSessionStopped' => MeetingMediaEventType.audioSessionStopped,
      'sessionReconnecting' => MeetingMediaEventType.reconnecting,
      'connectionRecovered' => MeetingMediaEventType.connectionRecovered,
      'connectionPoor' => MeetingMediaEventType.connectionPoor,
      'participantJoined' => MeetingMediaEventType.participantJoined,
      'participantLeft' => MeetingMediaEventType.participantLeft,
      'localVideoAvailable' => MeetingMediaEventType.localVideoAvailable,
      'localVideoRemoved' => MeetingMediaEventType.localVideoRemoved,
      'remoteVideoAvailable' => MeetingMediaEventType.remoteVideoAvailable,
      'remoteVideoRemoved' => MeetingMediaEventType.remoteVideoRemoved,
      'localVideoPaused' => MeetingMediaEventType.localVideoPaused,
      'localVideoResumed' => MeetingMediaEventType.localVideoResumed,
      'remoteVideoPaused' => MeetingMediaEventType.remoteVideoPaused,
      'remoteVideoResumed' => MeetingMediaEventType.remoteVideoResumed,
      'localMuted' => MeetingMediaEventType.localMuted,
      'localUnmuted' => MeetingMediaEventType.localUnmuted,
      'remoteMuted' => MeetingMediaEventType.remoteMuted,
      'remoteUnmuted' => MeetingMediaEventType.remoteUnmuted,
      'microphoneEnabled' => MeetingMediaEventType.microphoneEnabled,
      'microphoneDisabled' => MeetingMediaEventType.microphoneDisabled,
      'cameraEnabled' => MeetingMediaEventType.cameraEnabled,
      'cameraDisabled' => MeetingMediaEventType.cameraDisabled,
      'activeSpeaker' => MeetingMediaEventType.activeSpeaker,
      'volumeLevel' => MeetingMediaEventType.volumeLevel,
      'audioDeviceChanged' => MeetingMediaEventType.audioDeviceChanged,
      'sessionError' => MeetingMediaEventType.sessionError,
      _ => null,
    };
    if (type == null) {
      return null;
    }

    final attendeeId = _nonBlank(data.attendeeId);
    final volume = data.volume;
    return MeetingMediaEvent(
      type: type,
      occurredAt: occurredAt ?? DateTime.now(),
      generation: data.generation,
      attendeeId: attendeeId,
      volume: volume != null && volume.isFinite && volume >= 0 && volume <= 1
          ? volume
          : null,
      failure: _failureForCode(data.failureCode, eventType: type),
    );
  }

  MeetingFailure? _failureForCode(
    String? code, {
    required MeetingMediaEventType eventType,
  }) {
    final normalized = _nonBlank(code);
    if (normalized == null && eventType != MeetingMediaEventType.sessionError) {
      return null;
    }
    return MeetingFailure(switch (normalized) {
      'bridge_unavailable' => MeetingFailureType.bridgeUnavailable,
      'unsupported_runtime' => MeetingFailureType.unsupportedRuntime,
      'missing_media_configuration' =>
        MeetingFailureType.missingMediaConfiguration,
      'invalid_attendee_credentials' =>
        MeetingFailureType.invalidAttendeeCredentials,
      'microphone_permission_denied' =>
        MeetingFailureType.microphonePermissionDenied,
      'camera_permission_denied' => MeetingFailureType.cameraPermissionDenied,
      'device_not_found' => MeetingFailureType.mediaDeviceNotFound,
      'device_not_readable' => MeetingFailureType.mediaDeviceNotReadable,
      'device_constraints' => MeetingFailureType.mediaDeviceConstraints,
      'audio_playback_blocked' => MeetingFailureType.audioPlaybackBlocked,
      'session_start' ||
      'meeting_start_failure' => MeetingFailureType.meetingStart,
      'session_stopped_fatal' => MeetingFailureType.sessionUnavailable,
      'microphone_operation_failure' => MeetingFailureType.microphoneOperation,
      'camera_operation_failure' => MeetingFailureType.cameraOperation,
      'interop_failure' ||
      'platform_bridge_failure' => MeetingFailureType.platformBridge,
      _ => MeetingFailureType.unexpected,
    });
  }

  String? _nonBlank(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
