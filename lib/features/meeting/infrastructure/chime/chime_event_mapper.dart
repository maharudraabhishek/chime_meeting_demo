import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_media_event.dart';
import 'chime_platform_bridge.dart';

/// Converts validated Android wire events into SDK-independent domain events.
final class ChimeEventMapper {
  const ChimeEventMapper();

  /// Returns `null` for forward-compatible event types this app does not use.
  MeetingMediaEvent? map(ChimePlatformEvent event) {
    final type = switch (event.type) {
      'sessionStarted' => MeetingMediaEventType.sessionStarted,
      'sessionStopped' => MeetingMediaEventType.sessionStopped,
      'audioSessionStarted' => MeetingMediaEventType.audioSessionStarted,
      'audioSessionStopped' => MeetingMediaEventType.audioSessionStopped,
      'sessionReconnecting' => MeetingMediaEventType.reconnecting,
      'connectionPoor' => MeetingMediaEventType.connectionPoor,
      'connectionRecovered' => MeetingMediaEventType.connectionRecovered,
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

    return MeetingMediaEvent(
      type: type,
      occurredAt: event.occurredAt,
      failure: type == MeetingMediaEventType.sessionError
          ? _mapFailureCode(event.payload['code'])
          : null,
      generation: event.generation,
    );
  }

  /// Maps an optional native error code into a safe domain failure.
  MeetingFailure _mapFailureCode(Object? code) {
    return MeetingFailure(_failureTypeForCode(code is String ? code : ''));
  }

  static MeetingFailureType failureTypeForPlatformCode(
    String code, {
    MeetingFailureType fallback = MeetingFailureType.platformBridge,
  }) {
    return switch (code) {
      'missing_media_configuration' =>
        MeetingFailureType.missingMediaConfiguration,
      'invalid_attendee_credentials' ||
      'invalid_arguments' => MeetingFailureType.invalidAttendeeCredentials,
      'permission_unavailable' => MeetingFailureType.permissionUnavailable,
      'unsupported_runtime' => MeetingFailureType.unsupportedRuntime,
      'native_chime_initialization_failure' =>
        MeetingFailureType.nativeInitialization,
      'meeting_start_failure' => MeetingFailureType.meetingStart,
      'microphone_operation_failure' => MeetingFailureType.microphoneOperation,
      'camera_operation_failure' => MeetingFailureType.cameraOperation,
      'session_already_active' => MeetingFailureType.sessionAlreadyActive,
      'session_unavailable' => MeetingFailureType.sessionUnavailable,
      'platform_bridge_failure' => MeetingFailureType.platformBridge,
      _ => fallback,
    };
  }

  /// Resolves a known bridge error code to its stable domain category.
  MeetingFailureType _failureTypeForCode(String code) {
    return failureTypeForPlatformCode(code);
  }
}
