import '../../domain/gateways/meeting_permission_gateway.dart';
import 'web_meeting_permission_gateway.dart';

MeetingPermissionGateway createMeetingPermissionGateway() {
  return const WebMeetingPermissionGateway();
}
