import 'package:equatable/equatable.dart';

import '../../domain/entities/meeting_diagnostics.dart';
import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_id.dart';
import '../../domain/entities/meeting_log_entry.dart';
import '../../domain/entities/meeting_media_state.dart';
import '../../domain/entities/meeting_status.dart';

const Object _notProvided = Object();

/// Immutable presentation snapshot for the meeting workflow.
///
/// REST/native command success retains [MeetingStatus.joining].
/// Only the accepted native session-start callback establishes connected.
final class MeetingState extends Equatable {
  MeetingState({
    this.status = MeetingStatus.idle,
    this.meetingId,
    this.media = const MeetingMediaState(),
    List<MeetingLogEntry> eventLog = const <MeetingLogEntry>[],
    this.failure,
    this.statusMessage,
    this.reconnectAttempts = 0,
    this.networkQuality = NetworkQuality.unknown,
  }) : eventLog = List<MeetingLogEntry>.unmodifiable(eventLog);

  final MeetingStatus status;
  final MeetingId? meetingId;
  final MeetingMediaState media;
  final List<MeetingLogEntry> eventLog;
  final MeetingFailure? failure;
  final String? statusMessage;
  final int reconnectAttempts;
  final NetworkQuality networkQuality;

  MeetingDiagnostics get diagnostics => MeetingDiagnostics(
    connectionState: status,
    networkQuality: networkQuality,
    reconnectAttempts: reconnectAttempts,
    microphoneEnabled: media.isMicrophoneEnabled,
    cameraEnabled: media.isCameraEnabled,
  );

  MeetingState copyWith({
    MeetingStatus? status,
    Object? meetingId = _notProvided,
    MeetingMediaState? media,
    List<MeetingLogEntry>? eventLog,
    Object? failure = _notProvided,
    Object? statusMessage = _notProvided,
    int? reconnectAttempts,
    NetworkQuality? networkQuality,
  }) {
    return MeetingState(
      status: status ?? this.status,
      meetingId: identical(meetingId, _notProvided)
          ? this.meetingId
          : meetingId as MeetingId?,
      media: media ?? this.media,
      eventLog: eventLog ?? this.eventLog,
      failure: identical(failure, _notProvided)
          ? this.failure
          : failure as MeetingFailure?,
      statusMessage: identical(statusMessage, _notProvided)
          ? this.statusMessage
          : statusMessage as String?,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      networkQuality: networkQuality ?? this.networkQuality,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    meetingId,
    media,
    eventLog,
    failure,
    statusMessage,
    reconnectAttempts,
    networkQuality,
  ];
}
