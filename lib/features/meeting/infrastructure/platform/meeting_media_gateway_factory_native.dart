import '../../domain/gateways/meeting_media_gateway.dart';
import '../chime/chime_meeting_media_gateway.dart';
import '../chime/chime_platform_bridge.dart';

/// Creates the native media adapter at the application composition root.
MeetingMediaGateway createMeetingMediaGateway() {
  return ChimeMeetingMediaGateway(bridge: ChimePlatformBridge());
}
