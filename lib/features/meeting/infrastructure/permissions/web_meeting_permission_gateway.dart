import '../../domain/entities/meeting_result.dart';
import '../../domain/gateways/meeting_permission_gateway.dart';

/// Defers browser permission requests to Chime's per-device media operations.
///
/// This preflight deliberately reports granted so Create/Join can reach the
/// browser media request. Actual denials arrive as typed media events, allowing
/// listen-only or audio-only participation where the browser permits it.
final class WebMeetingPermissionGateway implements MeetingPermissionGateway {
  const WebMeetingPermissionGateway();

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  requestRequiredPermissions() async {
    return const MeetingSuccess<MeetingPermissionStatus>(
      MeetingPermissionStatus.granted,
    );
  }

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  getRequiredPermissionStatus() async {
    return const MeetingSuccess<MeetingPermissionStatus>(
      MeetingPermissionStatus.granted,
    );
  }

  @override
  Future<MeetingResult<bool>> openAppSettings() async {
    // Browsers do not expose a portable, trustworthy settings deep link.
    return const MeetingSuccess<bool>(false);
  }
}
