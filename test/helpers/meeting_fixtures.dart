import 'package:chime_meeting/features/meeting/data/dto/meeting_bootstrap_dto.dart';
import 'package:chime_meeting/features/meeting/domain/entities/attendee_credentials.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_bootstrap.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_id.dart';

const String fixtureMeetingId = 'meeting-123';

Map<String, Object?> createResponseJson() => <String, Object?>{
  'status': 'success',
  'message': 'Created',
  'data': <String, Object?>{
    'meeting': <String, Object?>{
      'MeetingId': fixtureMeetingId,
      'ExternalMeetingId': 'external-123',
      'MediaRegion': 'ap-southeast-1',
      'MediaPlacement': mediaPlacementJson(),
    },
    'attendee': attendeeJson(),
  },
};

Map<String, Object?> joinResponseJson() => <String, Object?>{
  'status': 'success',
  'message': 'Joined',
  'data': <String, Object?>{
    'meeting': <String, Object?>{'MeetingId': fixtureMeetingId},
    'attendee': attendeeJson(),
  },
};

Map<String, Object?> mediaPlacementJson() => <String, Object?>{
  'AudioHostUrl': 'audio.example.test',
  'AudioFallbackUrl': 'wss://fallback.example.test',
  'SignalingUrl': 'wss://signal.example.test',
  'TurnControlUrl': 'https://turn.example.test',
  'ScreenDataUrl': 'wss://screen-data.example.test',
  'ScreenViewingUrl': 'wss://screen-view.example.test',
  'ScreenSharingUrl': 'wss://screen-share.example.test',
  'EventIngestionUrl': 'https://events.example.test',
};

Map<String, Object?> attendeeJson() => <String, Object?>{
  'ExternalUserId': 'client',
  'AttendeeId': 'attendee-123',
  'JoinToken': 'test-token-not-a-real-credential',
};

MeetingBootstrapDto createBootstrapDto() => MeetingBootstrapDto.fromJson(
  Map<String, Object?>.from(createResponseJson()['data']! as Map),
  requireMediaPlacement: true,
);

MeetingBootstrap meetingBootstrap() => MeetingBootstrap(
  meeting: Meeting(
    id: MeetingId(fixtureMeetingId),
    externalMeetingId: 'external-123',
    mediaRegion: 'ap-southeast-1',
    mediaPlacement: const MeetingMediaPlacement(
      audioHostUrl: 'audio.example.test',
      audioFallbackUrl: 'wss://fallback.example.test',
      signalingUrl: 'wss://signal.example.test',
      turnControlUrl: 'https://turn.example.test',
      eventIngestionUrl: 'https://events.example.test',
    ),
  ),
  attendee: const AttendeeCredentials(
    externalUserId: 'client',
    attendeeId: 'attendee-123',
    joinToken: 'test-token-not-a-real-credential',
  ),
);

MeetingBootstrap meetingBootstrapWithoutMediaPlacement() => MeetingBootstrap(
  meeting: Meeting(id: MeetingId(fixtureMeetingId)),
  attendee: const AttendeeCredentials(
    externalUserId: 'client',
    attendeeId: 'attendee-123',
    joinToken: 'test-token-not-a-real-credential',
  ),
);
