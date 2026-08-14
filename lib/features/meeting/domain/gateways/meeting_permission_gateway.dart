import '../entities/meeting_result.dart';

/// Represents three distinct permission outcomes the UI must handle.
enum MeetingPermissionStatus { granted, denied, permanentlyDenied }

/// Domain-facing boundary for the camera and microphone permission preflight.
///
/// Presentation and business logic depend on this contract rather than Android
/// permission APIs. Implementations must not persist or expose permission data
/// beyond the result required to decide whether meeting bootstrap may continue.
abstract interface class MeetingPermissionGateway {
  /// Requests the permissions required to start Chime media.
  ///
  /// Returns a [MeetingPermissionStatus] describing the user's decision or a
  /// typed platform failure.
  Future<MeetingResult<MeetingPermissionStatus>> requestRequiredPermissions();

  /// Returns the current permission status without prompting the user.
  Future<MeetingResult<MeetingPermissionStatus>> getRequiredPermissionStatus();

  /// Opens the platform app settings screen so users can manually enable
  /// permissions. Returns success true when the settings intent was launched.
  Future<MeetingResult<bool>> openAppSettings();
}
