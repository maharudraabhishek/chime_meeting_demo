import 'dart:async';

import 'package:chime_meeting/features/meeting/domain/entities/meeting_bootstrap.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_id.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/connectivity_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/meeting_media_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/meeting_permission_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/repositories/meeting_repository.dart';
import 'package:chime_meeting/features/meeting/domain/usecases/create_meeting.dart';
import 'package:chime_meeting/features/meeting/domain/usecases/join_meeting.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_bloc.dart';

import 'meeting_fixtures.dart';

/// Creates a real presentation BLoC with deterministic Stage 1 test doubles.
MeetingBloc createMeetingWidgetTestBloc({
  MeetingWidgetTestRepository? repository,
  MeetingWidgetTestMediaGateway? mediaGateway,
  MeetingWidgetTestPermissionGateway? permissionGateway,
  MeetingWidgetTestConnectivityGateway? connectivityGateway,
}) {
  final repo = repository ?? MeetingWidgetTestRepository();
  final media = mediaGateway ?? MeetingWidgetTestMediaGateway();
  final permissions =
      permissionGateway ?? const MeetingWidgetTestPermissionGateway();
  final connectivity =
      connectivityGateway ?? const MeetingWidgetTestConnectivityGateway();

  return MeetingBloc(
    createMeeting: CreateMeeting(repo, media),
    joinMeeting: JoinMeeting(repo, media),
    mediaGateway: media,
    permissionGateway: permissions,
    connectivityGateway: connectivity,
  );
}

/// Connectivity double that keeps the meeting feature in a deterministic online
/// state unless the test explicitly overrides it.
final class MeetingWidgetTestConnectivityGateway
    implements ConnectivityGateway {
  const MeetingWidgetTestConnectivityGateway({this.online = true});

  final bool online;

  @override
  Future<bool> get isOnline async => online;
}

/// Repository double that records the exact client meeting ID received.
final class MeetingWidgetTestRepository implements MeetingRepository {
  int createCalls = 0;
  int joinCalls = 0;
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
    joinCalls += 1;
    joinedMeetingId = meetingId;
    return MeetingSuccess<MeetingBootstrap>(meetingBootstrap());
  }
}

/// Controllable media boundary used by Phase 3 widget tests.
final class MeetingWidgetTestMediaGateway implements MeetingMediaGateway {
  final StreamController<MeetingMediaEvent> _events =
      StreamController<MeetingMediaEvent>.broadcast();

  int startCalls = 0;
  int microphoneCalls = 0;
  int cameraCalls = 0;
  int leaveCalls = 0;

  @override
  Stream<MeetingMediaEvent> get events => _events.stream;

  void emit(MeetingMediaEventType type, {MeetingFailure? failure}) {
    _events.add(
      MeetingMediaEvent(
        type: type,
        occurredAt: DateTime.utc(2026, 8, 12, 12),
        failure: failure,
      ),
    );
  }

  @override
  Future<MeetingResult<MeetingStatus>> start(MeetingBootstrap bootstrap) async {
    startCalls += 1;
    return const MeetingSuccess<MeetingStatus>(MeetingStatus.joining);
  }

  @override
  Future<MeetingResult<bool>> setMicrophoneEnabled(bool enabled) async {
    microphoneCalls += 1;
    return MeetingSuccess<bool>(enabled);
  }

  @override
  Future<MeetingResult<bool>> setCameraEnabled(bool enabled) async {
    cameraCalls += 1;
    return MeetingSuccess<bool>(enabled);
  }

  @override
  Future<MeetingResult<bool>> switchCamera() async {
    // Test double always accepts the command.
    return const MeetingSuccess<bool>(true);
  }

  @override
  Future<MeetingResult<MeetingStatus>> leave() async {
    leaveCalls += 1;
    return const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// Permission double that can model either user grant or denial.
final class MeetingWidgetTestPermissionGateway
    implements MeetingPermissionGateway {
  const MeetingWidgetTestPermissionGateway({this.granted = true});

  final bool granted;

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  requestRequiredPermissions() async {
    return MeetingSuccess<MeetingPermissionStatus>(
      granted
          ? MeetingPermissionStatus.granted
          : MeetingPermissionStatus.denied,
    );
  }

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  getRequiredPermissionStatus() async {
    return MeetingSuccess<MeetingPermissionStatus>(
      granted
          ? MeetingPermissionStatus.granted
          : MeetingPermissionStatus.denied,
    );
  }

  @override
  Future<MeetingResult<bool>> openAppSettings() async =>
      const MeetingSuccess<bool>(true);
}
