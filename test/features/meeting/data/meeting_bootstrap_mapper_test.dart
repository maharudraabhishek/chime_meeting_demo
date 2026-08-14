import 'package:chime_meeting/features/meeting/data/dto/meeting_bootstrap_dto.dart';
import 'package:chime_meeting/features/meeting/data/mappers/meeting_bootstrap_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  test('maps DTO values into immutable domain entities', () {
    final dto = MeetingBootstrapDto.fromJson(
      Map<String, Object?>.from(createResponseJson()['data']! as Map),
      requireMediaPlacement: true,
    );

    final domain = dto.toDomain();

    expect(domain.meeting.id.value, fixtureMeetingId);
    expect(domain.meeting.mediaPlacement?.audioHostUrl, 'audio.example.test');
    expect(domain.attendee.externalUserId, 'client');
  });
}
