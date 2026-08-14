import 'package:equatable/equatable.dart';

import 'meeting_failure.dart';

/// SDK-independent callbacks emitted by the active meeting media session.
enum MeetingMediaEventType {
  sessionStarted,
  sessionStopped,
  // Distinct audio-session lifecycle events.
  audioSessionStarted,
  audioSessionStopped,
  reconnecting,
  connectionRecovered,
  connectionPoor,
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
  // Local and remote mute semantics (semantic events) in addition to
  // microphoneEnabled/microphoneDisabled state updates.
  localMuted,
  localUnmuted,
  remoteMuted,
  remoteUnmuted,
  microphoneEnabled,
  microphoneDisabled,
  cameraEnabled,
  cameraDisabled,
  activeSpeaker,
  volumeLevel,
  audioDeviceChanged,
  sessionError,
}

/// Immutable media event that can cross into presentation without native data.
///
/// Attendee credentials and SDK objects are deliberately excluded. A
/// [failure] may describe a terminal session error or a recoverable browser
/// media warning such as camera denial while an audio-only meeting continues.
final class MeetingMediaEvent extends Equatable {
  const MeetingMediaEvent({
    required this.type,
    required this.occurredAt,
    this.failure,
    this.generation,
    this.attendeeId,
    this.volume,
  });

  final MeetingMediaEventType type;
  final DateTime occurredAt;
  final MeetingFailure? failure;
  final int? generation;
  final String? attendeeId;
  final double? volume;

  @override
  List<Object?> get props => <Object?>[
    type,
    occurredAt,
    failure,
    generation,
    attendeeId,
    volume,
  ];
}
