import 'dart:async';

import 'package:chime_meeting/features/meeting/domain/entities/meeting_bootstrap.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_id.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/meeting_media_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/repositories/meeting_repository.dart';
import 'package:chime_meeting/features/meeting/domain/usecases/create_meeting.dart';
import 'package:chime_meeting/features/meeting/domain/usecases/join_meeting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';

void main() {
  group('CreateMeeting', () {
    test(
      'passes credentials directly from repository to media gateway',
      () async {
        final repository = RecordingMeetingRepository();
        final gateway = RecordingMeetingMediaGateway();

        final result = await CreateMeeting(repository, gateway)();

        expect(repository.createCalls, 1);
        expect(gateway.startedBootstrap, meetingBootstrap());
        expect(result, MeetingSuccess<MeetingId>(MeetingId(fixtureMeetingId)));
      },
    );

    test('returns media start failure without exposing bootstrap', () async {
      final repository = RecordingMeetingRepository();
      final gateway = RecordingMeetingMediaGateway(
        startResult: const MeetingError<MeetingStatus>(
          MeetingFailure(MeetingFailureType.meetingStart),
        ),
      );

      final result = await CreateMeeting(repository, gateway)();

      expect(
        result,
        const MeetingError<MeetingId>(
          MeetingFailure(MeetingFailureType.meetingStart),
        ),
      );
    });
  });

  group('JoinMeeting', () {
    test('trims the ID and starts media with returned credentials', () async {
      final repository = RecordingMeetingRepository();
      final gateway = RecordingMeetingMediaGateway();

      final result = await JoinMeeting(repository, gateway)(
        '  $fixtureMeetingId  ',
      );

      expect(repository.joinedMeetingId, MeetingId(fixtureMeetingId));
      expect(gateway.startedBootstrap, meetingBootstrap());
      expect(result, MeetingSuccess<MeetingId>(MeetingId(fixtureMeetingId)));
    });

    test('rejects blank input without calling repository or media', () async {
      final repository = RecordingMeetingRepository();
      final gateway = RecordingMeetingMediaGateway();

      final result = await JoinMeeting(repository, gateway)('   ');

      expect(repository.joinedMeetingId, isNull);
      expect(gateway.startedBootstrap, isNull);
      expect(
        result,
        const MeetingError<MeetingId>(
          MeetingFailure(MeetingFailureType.invalidMeeting),
        ),
      );
    });
  });
}

final class RecordingMeetingRepository implements MeetingRepository {
  int createCalls = 0;
  MeetingId? joinedMeetingId;

  @override
  Future<MeetingResult<MeetingBootstrap>> createMeeting() async {
    createCalls += 1;
    return MeetingSuccess<MeetingBootstrap>(meetingBootstrap());
  }

  @override
  Future<MeetingResult<MeetingBootstrap>> joinMeeting(
    MeetingId meetingId,
  ) async {
    joinedMeetingId = meetingId;
    return MeetingSuccess<MeetingBootstrap>(meetingBootstrap());
  }
}

final class RecordingMeetingMediaGateway implements MeetingMediaGateway {
  RecordingMeetingMediaGateway({
    this.startResult = const MeetingSuccess<MeetingStatus>(
      MeetingStatus.joining,
    ),
  });

  final MeetingResult<MeetingStatus> startResult;
  MeetingBootstrap? startedBootstrap;

  @override
  Stream<MeetingMediaEvent> get events => const Stream.empty();

  @override
  Future<MeetingResult<MeetingStatus>> start(MeetingBootstrap bootstrap) async {
    startedBootstrap = bootstrap;
    return startResult;
  }

  @override
  Future<MeetingResult<bool>> setMicrophoneEnabled(bool enabled) async {
    return MeetingSuccess<bool>(enabled);
  }

  @override
  Future<MeetingResult<bool>> setCameraEnabled(bool enabled) async {
    return MeetingSuccess<bool>(enabled);
  }

  @override
  Future<MeetingResult<MeetingStatus>> leave() async {
    return const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected);
  }

  @override
  Future<MeetingResult<bool>> switchCamera() async {
    return const MeetingSuccess<bool>(true);
  }

  @override
  Future<void> dispose() async {}
}
