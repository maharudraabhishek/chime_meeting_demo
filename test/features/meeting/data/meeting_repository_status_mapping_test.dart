import 'package:chime_meeting/core/error/app_exception.dart';
import 'package:chime_meeting/features/meeting/data/dto/meeting_bootstrap_dto.dart';
import 'package:chime_meeting/features/meeting/data/repositories/meeting_repository_impl.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_bootstrap.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_id.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/data/datasources/meeting_api_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  group('MeetingRepositoryImpl HTTP status mapping', () {
    test('maps 401 to unauthorized failure', () async {
      final repo = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () => Future<MeetingBootstrapDto>.error(
            const ApiException(statusCode: 401),
          ),
        ),
      );

      final result = await repo.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.unauthorized),
        ),
      );
      expect(
        (result as MeetingError<MeetingBootstrap>).failure.userMessage,
        'The meeting service rejected this request. Please try again later.',
      );
    });

    test('maps 429 to rateLimited failure', () async {
      final repo = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () => Future<MeetingBootstrapDto>.error(
            const ApiException(statusCode: 429),
          ),
        ),
      );

      final result = await repo.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.rateLimited),
        ),
      );
    });

    test('maps Worker 504 to timeout failure', () async {
      final repo = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () => Future<MeetingBootstrapDto>.error(
            const ApiException(statusCode: 504),
          ),
        ),
      );

      final result = await repo.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.timeout),
        ),
      );
    });

    test('maps 500 to server failure', () async {
      final repo = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          create: () => Future<MeetingBootstrapDto>.error(
            const ApiException(statusCode: 500),
          ),
        ),
      );

      final result = await repo.createMeeting();

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.server),
        ),
      );
    });

    test('join uses invalidMeeting for 404', () async {
      final repo = MeetingRepositoryImpl(
        StubMeetingApiDataSource(
          join: (_) => Future<MeetingBootstrapDto>.error(
            const ApiException(statusCode: 404),
          ),
        ),
      );

      final result = await repo.joinMeeting(MeetingId('abc'));

      expect(
        result,
        const MeetingError<MeetingBootstrap>(
          MeetingFailure(MeetingFailureType.invalidMeeting),
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
