import 'package:chime_meeting/core/error/app_exception.dart';
import 'package:chime_meeting/features/meeting/data/datasources/meeting_api_data_source.dart';
import 'package:chime_meeting/features/meeting/data/dto/meeting_bootstrap_dto.dart';
import 'package:chime_meeting/features/meeting/data/repositories/meeting_repository_impl.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_bootstrap.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_id.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  group('MeetingRepositoryImpl', () {
    test('maps successful DTO to domain bootstrap', () async {
      final repository = MeetingRepositoryImpl(
        StubMeetingApiDataSource(create: () async => createBootstrapDto()),
      );

      final result = await repository.createMeeting();

      expect(result, isA<MeetingSuccess<MeetingBootstrap>>());
      final success = result as MeetingSuccess<MeetingBootstrap>;
      expect(success.value.meeting.id.value, fixtureMeetingId);
    });

    test('maps connection exception to network failure', () async {
      final repository = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () =>
              Future<MeetingBootstrapDto>.error(const NetworkException()),
        ),
      );

      final result = await repository.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.network),
        ),
      );
    });

    test('maps request deadline exception to timeout failure', () async {
      final repository = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () => Future<MeetingBootstrapDto>.error(
            const RequestTimeoutException(),
          ),
        ),
      );

      final result = await repository.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.timeout),
        ),
      );
    });

    test('maps a client API rejection to invalid meeting failure', () async {
      final repository = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          join: (_) => Future<MeetingBootstrapDto>.error(
            const ApiException(statusCode: 404),
          ),
        ),
      );

      final result = await repository.joinMeeting(MeetingId(fixtureMeetingId));

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.invalidMeeting),
        ),
      );
    });

    test('maps malformed response exception without leaking details', () async {
      final repository = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () => Future<MeetingBootstrapDto>.error(
            const InvalidResponseException(),
          ),
        ),
      );

      final result = await repository.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.invalidResponse),
        ),
      );
    });
  });
}

final class StubMeetingApiDataSource implements MeetingApiDataSource {
  StubMeetingApiDataSource({
    Future<MeetingBootstrapDto> Function()? create,
    Future<MeetingBootstrapDto> Function(String meetingId)? join,
  }) : _create = create ?? (() async => createBootstrapDto()),
       _join = join ?? ((_) async => createBootstrapDto());

  final Future<MeetingBootstrapDto> Function() _create;
  final Future<MeetingBootstrapDto> Function(String meetingId) _join;

  @override
  Future<MeetingBootstrapDto> createMeeting() => _create();

  @override
  Future<MeetingBootstrapDto> joinMeeting(String meetingId) => _join(meetingId);
}
