import 'package:equatable/equatable.dart';

import 'meeting_status.dart';

/// Coarse semantic network quality exposed to the UI. Precise bitrate/packet
/// metrics are intentionally omitted unless the native SDK provides them.
enum NetworkQuality { good, poor, unknown }

/// Small immutable snapshot of meeting diagnostics used by presentation UI.
///
/// The model is intentionally minimal and derived from existing presentation
/// state. Do not poll external services — values are updated by the MeetingBloc
/// when media events arrive.
final class MeetingDiagnostics extends Equatable {
  const MeetingDiagnostics({
    required this.connectionState,
    this.networkQuality = NetworkQuality.unknown,
    this.reconnectAttempts = 0,
    this.microphoneEnabled = false,
    this.cameraEnabled = false,
  });

  final MeetingStatus connectionState;
  final NetworkQuality networkQuality;
  final int reconnectAttempts;
  final bool microphoneEnabled;
  final bool cameraEnabled;

  static const MeetingDiagnostics initial = MeetingDiagnostics(
    connectionState: MeetingStatus.idle,
    networkQuality: NetworkQuality.unknown,
    reconnectAttempts: 0,
    microphoneEnabled: false,
    cameraEnabled: false,
  );

  @override
  List<Object> get props => <Object>[
    connectionState,
    networkQuality,
    reconnectAttempts,
    microphoneEnabled,
    cameraEnabled,
  ];

  MeetingDiagnostics copyWith({
    MeetingStatus? connectionState,
    NetworkQuality? networkQuality,
    int? reconnectAttempts,
    bool? microphoneEnabled,
    bool? cameraEnabled,
  }) {
    return MeetingDiagnostics(
      connectionState: connectionState ?? this.connectionState,
      networkQuality: networkQuality ?? this.networkQuality,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      microphoneEnabled: microphoneEnabled ?? this.microphoneEnabled,
      cameraEnabled: cameraEnabled ?? this.cameraEnabled,
    );
  }
}
