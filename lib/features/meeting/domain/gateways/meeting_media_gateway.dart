import '../entities/meeting_bootstrap.dart';
import '../entities/meeting_media_event.dart';
import '../entities/meeting_result.dart';
import '../entities/meeting_status.dart';

/// Domain-facing boundary for Amazon Chime media operations.
///
/// Infrastructure translates [MeetingBootstrap] into native SDK configuration
/// and native callbacks into [MeetingMediaEvent] values. No native class is
/// allowed across this contract. The owner must call [dispose] when the gateway
/// leaves application scope.
abstract interface class MeetingMediaGateway {
  /// Emits SDK-independent events for the active session.
  Stream<MeetingMediaEvent> get events;

  /// Starts media from backend-issued meeting and attendee configuration.
  Future<MeetingResult<MeetingStatus>> start(MeetingBootstrap bootstrap);

  /// Applies microphone state and returns the state confirmed by the adapter.
  Future<MeetingResult<bool>> setMicrophoneEnabled(bool enabled);

  /// Requests a local camera state change.
  ///
  /// A successful command means native Chime accepted the request. Actual camera
  /// state remains authoritative through [events].
  Future<MeetingResult<bool>> setCameraEnabled(bool enabled);

  /// Leaves the active session and returns its terminal connection state.
  Future<MeetingResult<MeetingStatus>> leave();

  /// Requests a camera-facing switch (front/back). The call confirms command
  /// acceptance; actual facing is reported by video-tile callbacks.
  Future<MeetingResult<bool>> switchCamera();

  /// Releases native observers, sessions, views, and streams owned by the adapter.
  Future<void> dispose();
}
