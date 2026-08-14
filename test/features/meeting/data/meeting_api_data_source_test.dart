import 'package:chime_meeting/core/error/app_exception.dart';
import 'package:chime_meeting/core/network/json_api_client.dart';
import 'package:chime_meeting/features/meeting/data/datasources/meeting_api_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  group('HipsterMeetingApiDataSource', () {
    test('uses JSON-body contract when creating a meeting', () async {
      final client = RecordingJsonApiClient(createResponseJson());
      final dataSource = HipsterMeetingApiDataSource(client);

      final dto = await dataSource.createMeeting();

      expect(client.path, 'meetings');
      expect(client.body, <String, Object?>{'type': 'agent'});
      expect(dto.meeting.mediaPlacement, isNotNull);
    });

    test(
      'sends exact meeting ID in the client meeting-body payload when joining',
      () async {
        final client = RecordingJsonApiClient(joinResponseJson());
        final dataSource = HipsterMeetingApiDataSource(client);

        await dataSource.joinMeeting(fixtureMeetingId);

        expect(client.body, <String, Object?>{
          'type': 'client',
          'meeting_id': fixtureMeetingId,
        });
      },
    );

    test('maps malformed envelope to InvalidResponseException', () async {
      final client = RecordingJsonApiClient(<String, Object?>{
        'status': 'success',
      });
      final dataSource = HipsterMeetingApiDataSource(client);

      await expectLater(
        dataSource.createMeeting(),
        throwsA(isA<InvalidResponseException>()),
      );
    });
  });
}

final class RecordingJsonApiClient implements JsonApiClient {
  RecordingJsonApiClient(this.response);

  final Map<String, Object?> response;
  String? path;
  Map<String, Object?>? body;

  @override
  Future<Map<String, Object?>> post(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    this.path = path;
    this.body = body;
    return response;
  }
}
