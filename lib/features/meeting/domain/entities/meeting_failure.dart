import 'package:equatable/equatable.dart';

/// Stable failure categories understood by meeting business logic and UI.
enum MeetingFailureType {
  network,
  timeout,
  unauthorized,
  rateLimited,
  server,
  invalidResponse,
  invalidMeeting,
  configuration,
  missingMediaConfiguration,
  invalidAttendeeCredentials,
  permissionUnavailable,
  permissionPermanentlyDenied,
  microphonePermissionDenied,
  cameraPermissionDenied,
  mediaDeviceNotFound,
  mediaDeviceNotReadable,
  mediaDeviceConstraints,
  audioPlaybackBlocked,
  bridgeUnavailable,
  unsupportedRuntime,
  nativeInitialization,
  meetingStart,
  reconnectTimeout,
  microphoneOperation,
  cameraOperation,
  platformBridge,
  sessionAlreadyActive,
  sessionUnavailable,
  unexpected,
}

/// Safe domain failure that never exposes transport exceptions or credentials.
final class MeetingFailure extends Equatable {
  const MeetingFailure(this.type);

  final MeetingFailureType type;

  /// Concise message safe to display without exposing implementation details.
  String get userMessage => switch (type) {
    MeetingFailureType.network =>
      'No internet connection. Check your connection and try again.',
    MeetingFailureType.timeout =>
      'The meeting service took too long to respond. Please try again.',
    MeetingFailureType.unauthorized =>
      'The meeting service rejected this request. Please try again later.',
    MeetingFailureType.rateLimited =>
      'The meeting service is currently rate-limiting requests. Please try again shortly.',
    MeetingFailureType.server =>
      'The meeting service could not complete the request.',
    MeetingFailureType.invalidResponse =>
      'The meeting service returned an invalid response.',
    MeetingFailureType.invalidMeeting =>
      'Enter a valid meeting ID and try again.',
    MeetingFailureType.configuration =>
      'The meeting service is not configured for this build.',
    MeetingFailureType.missingMediaConfiguration =>
      'This meeting response does not include the media configuration needed '
          'to join.',
    MeetingFailureType.invalidAttendeeCredentials =>
      'The meeting attendee credentials are invalid.',
    MeetingFailureType.permissionUnavailable =>
      'Camera and microphone permissions are required to start the meeting.',
    MeetingFailureType.permissionPermanentlyDenied =>
      'Camera and microphone permissions were permanently denied. Open app settings to enable them.',
    MeetingFailureType.microphonePermissionDenied =>
      'Microphone access was denied. The meeting can continue in listen-only mode.',
    MeetingFailureType.cameraPermissionDenied =>
      'Camera access was denied. The meeting can continue with audio only.',
    MeetingFailureType.mediaDeviceNotFound =>
      'No suitable camera or microphone was found.',
    MeetingFailureType.mediaDeviceNotReadable =>
      'A camera or microphone is unavailable or already in use.',
    MeetingFailureType.mediaDeviceConstraints =>
      'The selected camera or microphone is not supported by this browser.',
    MeetingFailureType.audioPlaybackBlocked =>
      'Browser audio playback is blocked. Interact with the page and try again.',
    MeetingFailureType.bridgeUnavailable =>
      'The browser meeting integration did not load. Reload the page and try again.',
    MeetingFailureType.unsupportedRuntime =>
      'Amazon Chime audio/video is unavailable on this browser or device.',
    MeetingFailureType.nativeInitialization =>
      'The meeting media session could not be initialized.',
    MeetingFailureType.meetingStart =>
      'The meeting media session could not be started.',
    MeetingFailureType.reconnectTimeout =>
      'The meeting connection could not be restored. Please try again.',
    MeetingFailureType.microphoneOperation =>
      'The microphone setting could not be changed.',
    MeetingFailureType.cameraOperation =>
      'The camera setting could not be changed.',
    MeetingFailureType.platformBridge =>
      'The meeting platform integration is unavailable.',
    MeetingFailureType.sessionAlreadyActive =>
      'A meeting session is already active.',
    MeetingFailureType.sessionUnavailable =>
      'No active meeting session is available.',
    MeetingFailureType.unexpected =>
      'Something unexpected happened. Please try again.',
  };

  @override
  List<Object> get props => <Object>[type];
}
