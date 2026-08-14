import '../../domain/gateways/meeting_media_gateway.dart';
import '../web/chime_web_interop.dart';
import '../web/web_meeting_media_gateway.dart';

/// Creates the browser adapter at the application composition root.
MeetingMediaGateway createMeetingMediaGateway() {
  return WebMeetingMediaGateway(bridge: InteropChimeWebBridgeClient());
}
