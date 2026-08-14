import 'package:chime_meeting/features/meeting/data/dto/meeting_bootstrap_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  group('MeetingBootstrapDto', () {
    test('parses create response fields required for future media setup', () {
      final data = Map<String, Object?>.from(
        createResponseJson()['data']! as Map,
      );

      final dto = MeetingBootstrapDto.fromJson(
        data,
        requireMediaPlacement: true,
      );

      expect(dto.meeting.meetingId, fixtureMeetingId);
      expect(dto.meeting.mediaRegion, 'ap-southeast-1');
      expect(dto.meeting.mediaPlacement?.signalingUrl, contains('signal'));
      expect(dto.attendee.attendeeId, 'attendee-123');
    });

    test('truthfully accepts join response without MediaPlacement', () {
      final data = Map<String, Object?>.from(
        joinResponseJson()['data']! as Map,
      );

      final dto = MeetingBootstrapDto.fromJson(
        data,
        requireMediaPlacement: false,
      );

      expect(dto.meeting.meetingId, fixtureMeetingId);
      expect(dto.meeting.mediaPlacement, isNull);
    });

    test(
      'parses Chime media placement without unused screen or ingestion URLs',
      () {
        final data = Map<String, Object?>.from(
          createResponseJson()['data']! as Map,
        );

        final meeting = Map<String, Object?>.from(data['meeting']! as Map);
        final placement =
            Map<String, Object?>.from(meeting['MediaPlacement']! as Map)
              ..remove('ScreenDataUrl')
              ..remove('ScreenViewingUrl')
              ..remove('ScreenSharingUrl')
              ..remove('EventIngestionUrl');

        meeting['MediaPlacement'] = placement;
        data['meeting'] = meeting;

        final dto = MeetingBootstrapDto.fromJson(
          data,
          requireMediaPlacement: true,
        );

        expect(dto.meeting.mediaPlacement?.audioHostUrl, 'audio.example.test');
        expect(dto.meeting.mediaPlacement?.eventIngestionUrl, isNull);
      },
    );

    test('rejects a malformed attendee response', () {
      final data = Map<String, Object?>.from(
        joinResponseJson()['data']! as Map,
      );
      data['attendee'] = <String, Object?>{
        'ExternalUserId': 'client',
        'AttendeeId': 'attendee-123',
      };

      expect(
        () => MeetingBootstrapDto.fromJson(data, requireMediaPlacement: false),
        throwsFormatException,
      );
    });
  });
}
