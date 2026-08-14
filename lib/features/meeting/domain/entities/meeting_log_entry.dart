import 'package:equatable/equatable.dart';

/// Safe event categories exposed by the active media gateway.
enum MeetingLogEventType {
  meetingStarted,
  meetingEnded,
  audioSessionStarted,
  audioSessionStopped,
  participantJoined,
  participantLeft,
  localVideoAvailable,
  localVideoRemoved,
  remoteVideoAvailable,
  remoteVideoRemoved,
  localVideoPaused,
  localVideoResumed,
  remoteVideoPaused,
  remoteVideoResumed,
  microphoneEnabled,
  microphoneDisabled,
  localMuted,
  localUnmuted,
  remoteMuted,
  remoteUnmuted,
  cameraEnabled,
  cameraDisabled,
  reconnectAttempt,
  connectionRecovered,
  connectionPoor,
  activeSpeaker,
  volumeLevel,
  audioDeviceChanged,
  sessionFailed,
}

/// Immutable, user-displayable meeting event without native SDK types.
final class MeetingLogEntry extends Equatable {
  const MeetingLogEntry({
    required this.type,
    required this.occurredAt,
    this.message,
    this.metadata,
  });

  final MeetingLogEventType type;
  final DateTime occurredAt;
  final String? message;
  final Map<String, String>? metadata;

  @override
  List<Object?> get props => <Object?>[type, occurredAt, message, metadata];
}
