import '../../domain/entities/meeting_bootstrap.dart';

/// Minimal browser bridge contract consumed by the Web media adapter.
///
/// Implementations own JavaScript interop. This interface remains browser-free
/// so generation, mapping, and cleanup behavior can be tested on the Dart VM.
abstract interface class ChimeWebBridgeClient {
  bool get isAvailable;
  bool get isSupported;

  void setEventHandler(void Function(WebBridgeEventData event)? handler);

  Future<void> startSession(WebStartSessionRequest request);
  Future<void> stopSession(int generation);
  Future<bool> muteLocalAudio(int generation);
  Future<bool> unmuteLocalAudio(int generation);
  Future<void> startLocalVideo(int generation);
  Future<void> stopLocalVideo(int generation);
  Future<bool> switchCamera(int generation);
  void attachLocalVideoElement(int generation, String elementId);
  void attachRemoteVideoElement(int generation, String elementId);
  void detachVideoElement(int generation, String role);
  Future<void> dispose();
}

/// One in-memory session request. Its credentials must never be persisted or
/// logged, and references are released after the bridge call completes.
final class WebStartSessionRequest {
  const WebStartSessionRequest({
    required this.generation,
    required this.bootstrap,
    this.debugLogging = false,
  });

  final int generation;
  final MeetingBootstrap bootstrap;
  final bool debugLogging;

  @override
  String toString() => 'WebStartSessionRequest(generation: $generation)';
}

/// Minimal validated data copied across the JavaScript callback boundary.
final class WebBridgeEventData {
  const WebBridgeEventData({
    required this.type,
    required this.generation,
    this.attendeeId,
    this.volume,
    this.failureCode,
  });

  final String type;
  final int generation;
  final String? attendeeId;
  final double? volume;
  final String? failureCode;
}
