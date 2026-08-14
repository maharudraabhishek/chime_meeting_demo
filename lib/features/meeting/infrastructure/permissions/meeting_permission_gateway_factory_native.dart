import '../../domain/gateways/meeting_permission_gateway.dart';
import 'android_meeting_permission_gateway.dart';

MeetingPermissionGateway createMeetingPermissionGateway() {
  return AndroidMeetingPermissionGateway();
}
