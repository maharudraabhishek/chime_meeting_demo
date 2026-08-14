import 'dart:async';

import 'package:chime_meeting/features/meeting/domain/entities/meeting_bootstrap.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_diagnostics.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_id.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_log_entry.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_state.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_result.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/connectivity_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/meeting_media_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/gateways/meeting_permission_gateway.dart';
import 'package:chime_meeting/features/meeting/domain/repositories/meeting_repository.dart';
import 'package:chime_meeting/features/meeting/domain/usecases/create_meeting.dart';
import 'package:chime_meeting/features/meeting/domain/usecases/join_meeting.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_bloc.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_event.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';
import '../../../helpers/meeting_widget_test_harness.dart'
    show
        MeetingWidgetTestConnectivityGateway,
        MeetingWidgetTestPermissionGateway;

void main() {
  group('MeetingBloc', () {
    test('create remains joining until sessionStarted connects it', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);

      bloc.add(const MeetingCreateRequested());
      await _waitUntil(() => bloc.state.meetingId != null);

      expect(bloc.state.status, MeetingStatus.joining);
      expect(gateway.startCalls, 1);

      gateway.emit(MeetingMediaEventType.sessionStarted);
      await _waitUntil(() => bloc.state.status == MeetingStatus.connected);

      expect(
        bloc.state.eventLog.single.type,
        MeetingLogEventType.meetingStarted,
      );
      await bloc.close();
      await gateway.dispose();
    });

    test('join remains joining until sessionStarted connects it', () async {
      final repository = ControllableMeetingRepository();
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(repository, gateway);

      bloc.add(const MeetingJoinRequested(fixtureMeetingId));
      await _waitUntil(() => bloc.state.meetingId != null);

      expect(repository.joinCalls, 1);
      expect(bloc.state.status, MeetingStatus.joining);

      gateway.emit(MeetingMediaEventType.sessionStarted);
      await _waitUntil(() => bloc.state.status == MeetingStatus.connected);

      expect(bloc.state.meetingId, MeetingId(fixtureMeetingId));
      await bloc.close();
      await gateway.dispose();
    });

    test('media start failure enters failed with its typed failure', () async {
      final gateway = ControllableMeetingMediaGateway(
        startResult: const MeetingError<MeetingStatus>(
          MeetingFailure(MeetingFailureType.meetingStart),
        ),
      );
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);

      bloc.add(const MeetingCreateRequested());
      await _waitUntil(() => bloc.state.status == MeetingStatus.failed);

      expect(bloc.state.failure?.type, MeetingFailureType.meetingStart);
      expect(bloc.state.meetingId, isNull);
      await bloc.close();
      await gateway.dispose();
    });

    test('offline create never calls the repository or permissions', () async {
      final repository = ControllableMeetingRepository();
      final gateway = ControllableMeetingMediaGateway();
      final connectivity = FakeConnectivityGateway(isOnline: false);
      final permissions = CountingPermissionGateway();
      final bloc = _createBloc(
        repository,
        gateway,
        connectivityGateway: connectivity,
        permissionGateway: permissions,
      );

      bloc.add(const MeetingCreateRequested());
      await _waitUntil(
        () => bloc.state.failure?.type == MeetingFailureType.network,
      );

      expect(repository.createCalls, 0);
      expect(gateway.startCalls, 0);
      expect(permissions.callCount, 0);
      expect(connectivity.checkCount, 1);
      expect(
        bloc.state.failure?.userMessage,
        'No internet connection. Check your connection and try again.',
      );
      expect(bloc.state.status, MeetingStatus.disconnected);
      await bloc.close();
      await gateway.dispose();
    });

    test('offline join never calls the repository or media start', () async {
      final repository = ControllableMeetingRepository();
      final gateway = ControllableMeetingMediaGateway();
      final connectivity = FakeConnectivityGateway(isOnline: false);
      final permissions = CountingPermissionGateway();
      final bloc = _createBloc(
        repository,
        gateway,
        connectivityGateway: connectivity,
        permissionGateway: permissions,
      );

      bloc.add(const MeetingJoinRequested(fixtureMeetingId));
      await _waitUntil(
        () => bloc.state.failure?.type == MeetingFailureType.network,
      );

      expect(repository.joinCalls, 0);
      expect(gateway.startCalls, 0);
      expect(permissions.callCount, 0);
      expect(connectivity.checkCount, 1);
      expect(bloc.state.failure?.type, MeetingFailureType.network);
      await bloc.close();
      await gateway.dispose();
    });

    test(
      'retry after connectivity returns runs the normal create flow once',
      () async {
        final repository = ControllableMeetingRepository();
        final gateway = ControllableMeetingMediaGateway();
        final connectivity = FakeConnectivityGateway(isOnline: false);
        final bloc = _createBloc(
          repository,
          gateway,
          connectivityGateway: connectivity,
        );

        bloc.add(const MeetingCreateRequested());
        await _waitUntil(
          () => bloc.state.failure?.type == MeetingFailureType.network,
        );

        connectivity.setOnline(true);
        bloc.add(const MeetingCreateRequested());
        await _waitUntil(() => bloc.state.meetingId != null);

        expect(repository.createCalls, 1);
        expect(gateway.startCalls, 1);
        expect(connectivity.checkCount, 2);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'invalid join input disconnects before connectivity and repo checks',
      () async {
        final repository = ControllableMeetingRepository();
        final gateway = ControllableMeetingMediaGateway();
        final connectivity = FakeConnectivityGateway();
        final bloc = _createBloc(
          repository,
          gateway,
          connectivityGateway: connectivity,
        );

        bloc.add(const MeetingJoinRequested('   '));
        await _waitUntil(() => bloc.state.status == MeetingStatus.disconnected);

        expect(repository.joinCalls, 0);
        expect(gateway.startCalls, 0);
        expect(connectivity.checkCount, 0);
        expect(bloc.state.failure?.type, MeetingFailureType.invalidMeeting);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'duplicate create requests while bootstrapping do not produce duplicates',
      () async {
        final repository = DelayedMeetingRepository();
        final gateway = ControllableMeetingMediaGateway();
        final connectivity = FakeConnectivityGateway(isOnline: true);
        final bloc = _createBloc(
          repository,
          gateway,
          connectivityGateway: connectivity,
        );

        bloc
          ..add(const MeetingCreateRequested())
          ..add(const MeetingCreateRequested());
        await _waitUntil(
          () =>
              repository.createCalls == 1 &&
              bloc.state.status == MeetingStatus.joining,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(repository.createCalls, 1);
        expect(gateway.startCalls, 0);

        repository.completeFirstCreate();
        await _waitUntil(() => bloc.state.meetingId != null);

        expect(repository.createCalls, 1);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test('session error disconnects a joining session', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);

      bloc.add(const MeetingCreateRequested());
      await _waitUntil(() => bloc.state.meetingId != null);
      gateway.emit(
        MeetingMediaEventType.sessionError,
        failure: const MeetingFailure(MeetingFailureType.nativeInitialization),
      );
      await _waitUntil(() => bloc.state.status == MeetingStatus.failed);

      expect(bloc.state.failure?.type, MeetingFailureType.nativeInitialization);
      await bloc.close();
      await gateway.dispose();
    });

    test(
      'session error cleans once and preserves failure when leave fails',
      () async {
        final gateway = ControllableMeetingMediaGateway()
          ..leaveResult = const MeetingError<MeetingStatus>(
            MeetingFailure(MeetingFailureType.sessionUnavailable),
          );
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);

        gateway.emit(
          MeetingMediaEventType.sessionError,
          failure: const MeetingFailure(MeetingFailureType.meetingStart),
        );
        await _waitUntil(
          () =>
              bloc.state.status == MeetingStatus.failed &&
              gateway.leaveCalls == 1,
        );

        gateway.emit(MeetingMediaEventType.sessionStopped);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(gateway.leaveCalls, 1);
        expect(bloc.state.failure?.type, MeetingFailureType.meetingStart);
        expect(bloc.state.status, MeetingStatus.failed);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'late native callbacks cannot clear failure or resurrect disconnected state',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);

        gateway.emit(
          MeetingMediaEventType.sessionError,
          failure: const MeetingFailure(MeetingFailureType.meetingStart),
        );
        await _waitUntil(() => bloc.state.status == MeetingStatus.failed);
        final terminalState = bloc.state;

        gateway.emit(MeetingMediaEventType.sessionStopped, generation: 1);
        gateway.emit(MeetingMediaEventType.sessionStarted, generation: 2);
        gateway.emit(MeetingMediaEventType.participantJoined, generation: 2);
        gateway.emit(MeetingMediaEventType.remoteVideoAvailable, generation: 2);
        gateway.emit(MeetingMediaEventType.microphoneEnabled);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(bloc.state, terminalState);
        expect(bloc.state.failure?.type, MeetingFailureType.meetingStart);
        expect(bloc.state.status, MeetingStatus.failed);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'microphone state changes only to the native confirmed result',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);

        gateway.microphoneResult = const MeetingSuccess<bool>(false);
        bloc.add(const MeetingMicrophoneChanged(true));
        await _waitUntil(() => gateway.microphoneCalls == 1);

        expect(bloc.state.media.isMicrophoneEnabled, isFalse);
        expect(bloc.state.eventLog, hasLength(1));

        gateway.microphoneResult = const MeetingSuccess<bool>(true);
        bloc.add(const MeetingMicrophoneChanged(true));
        await _waitUntil(() => bloc.state.media.isMicrophoneEnabled);

        expect(
          bloc.state.eventLog.last.type,
          MeetingLogEventType.microphoneEnabled,
        );
        await bloc.close();
        await gateway.dispose();
      },
    );

    test('camera state changes only after native media callbacks', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);
      await _connect(bloc, gateway);

      bloc.add(const MeetingCameraChanged(true));
      await _waitUntil(() => gateway.cameraCalls == 1);

      // Command acceptance alone must not claim that camera media is active.
      expect(bloc.state.media.isCameraEnabled, isFalse);

      gateway.emit(MeetingMediaEventType.cameraEnabled);
      await _waitUntil(() => bloc.state.media.isCameraEnabled);

      bloc.add(const MeetingCameraChanged(false));
      await _waitUntil(() => gateway.cameraCalls == 2);

      gateway.emit(MeetingMediaEventType.cameraDisabled);
      await _waitUntil(() => !bloc.state.media.isCameraEnabled);

      expect(
        bloc.state.eventLog.map((entry) => entry.type),
        containsAllInOrder(<MeetingLogEventType>[
          MeetingLogEventType.cameraEnabled,
          MeetingLogEventType.cameraDisabled,
        ]),
      );

      await bloc.close();
      await gateway.dispose();
    });

    test('participant and video callbacks update only safe UI state', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);
      await _connect(bloc, gateway);

      gateway.emit(MeetingMediaEventType.participantJoined);
      gateway.emit(MeetingMediaEventType.localVideoAvailable);
      gateway.emit(MeetingMediaEventType.remoteVideoAvailable);
      await _waitUntil(
        () => bloc.state.media.remoteVideo == VideoAvailability.available,
      );

      expect(bloc.state.media.localVideo, VideoAvailability.available);
      expect(bloc.state.media.remoteVideo, VideoAvailability.available);
      expect(
        bloc.state.eventLog.map((e) => e.type),
        containsAllInOrder(<MeetingLogEventType>[
          MeetingLogEventType.participantJoined,
          MeetingLogEventType.localVideoAvailable,
          MeetingLogEventType.remoteVideoAvailable,
        ]),
      );

      gateway.emit(MeetingMediaEventType.participantLeft);
      gateway.emit(MeetingMediaEventType.localVideoRemoved);
      gateway.emit(MeetingMediaEventType.remoteVideoRemoved);
      await _waitUntil(
        () => bloc.state.media.remoteVideo == VideoAvailability.unavailable,
      );

      expect(bloc.state.media.localVideo, VideoAvailability.unavailable);
      expect(
        bloc.state.eventLog.map((e) => e.type),
        containsAllInOrder(<MeetingLogEventType>[
          MeetingLogEventType.participantLeft,
          MeetingLogEventType.localVideoRemoved,
          MeetingLogEventType.remoteVideoRemoved,
        ]),
      );

      await bloc.close();
      await gateway.dispose();
    });

    test(
      'leave transitions connected to disconnected and clears media',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);
        gateway.emit(MeetingMediaEventType.localVideoAvailable);
        await _waitUntil(
          () => bloc.state.media.localVideo == VideoAvailability.available,
        );

        bloc.add(const MeetingLeaveRequested());
        await _waitUntil(() => bloc.state.status == MeetingStatus.disconnected);

        expect(gateway.leaveCalls, 1);
        expect(bloc.state.media, const MeetingMediaState());
        expect(bloc.state.eventLog.last.type, MeetingLogEventType.meetingEnded);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'duplicate leave requests invoke the media gateway only once',
      () async {
        final gateway = ControllableMeetingMediaGateway()
          ..leaveCompleter = Completer<MeetingResult<MeetingStatus>>();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);

        bloc
          ..add(const MeetingLeaveRequested())
          ..add(const MeetingLeaveRequested());
        await _waitUntil(() => gateway.leaveCalls == 1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(gateway.leaveCalls, 1);

        gateway.leaveCompleter!.complete(
          const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected),
        );
        await _waitUntil(() => bloc.state.status == MeetingStatus.disconnected);

        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'leave during delayed bootstrap cleans late start and blocks overlap',
      () async {
        final repository = DelayedMeetingRepository();
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(repository, gateway);

        bloc.add(const MeetingCreateRequested());
        await _waitUntil(
          () =>
              repository.createCalls == 1 &&
              bloc.state.status == MeetingStatus.joining,
        );

        bloc.add(const MeetingLeaveRequested());
        await _waitUntil(
          () =>
              bloc.state.status == MeetingStatus.disconnected &&
              gateway.leaveCalls == 1,
        );

        bloc.add(const MeetingCreateRequested());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(repository.createCalls, 1);
        expect(gateway.startCalls, 0);

        repository.completeFirstCreate();
        await _waitUntil(
          () => gateway.startCalls == 1 && gateway.leaveCalls == 2,
        );

        expect(bloc.state.status, MeetingStatus.disconnected);
        expect(bloc.state.meetingId, isNull);

        bloc.add(const MeetingCreateRequested());
        await _waitUntil(
          () => repository.createCalls == 2 && gateway.startCalls == 2,
        );

        expect(bloc.state.status, MeetingStatus.joining);
        await bloc.close();
        await gateway.dispose();
      },
    );

    test('credentials never enter MeetingState', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);

      bloc.add(const MeetingCreateRequested());
      await _waitUntil(() => bloc.state.meetingId != null);

      expect(bloc.state.props, isNot(contains(meetingBootstrap())));
      expect(
        bloc.state.toString(),
        isNot(contains('test-token-not-a-real-credential')),
      );
      await bloc.close();
      await gateway.dispose();
    });

    test(
      'close cancels its subscription without disposing shared gateway',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);

        expect(gateway.hasEventListener, isTrue);
        await bloc.close();

        expect(gateway.hasEventListener, isFalse);
        expect(gateway.disposeCalls, 0);
        await gateway.dispose();
      },
    );

    test('MeetingState uses value equality and freezes its event log', () {
      final first = MeetingState(meetingId: MeetingId(fixtureMeetingId));
      final second = MeetingState(meetingId: MeetingId(fixtureMeetingId));

      expect(first, second);
      expect(() => first.eventLog.addAll(const []), throwsUnsupportedError);
    });

    test(
      'P0: first sessionStarted with generation establishes active generation',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);

        bloc.add(const MeetingCreateRequested());
        await _waitUntil(() => bloc.state.meetingId != null);
        expect(bloc.state.status, MeetingStatus.joining);

        // First sessionStarted with generation 1 establishes it as active
        gateway.emit(MeetingMediaEventType.sessionStarted, generation: 1);
        await _waitUntil(() => bloc.state.status == MeetingStatus.connected);

        // Verify state is connected
        expect(bloc.state.status, MeetingStatus.connected);
        expect(
          bloc.state.eventLog.single.type,
          MeetingLogEventType.meetingStarted,
        );

        await bloc.close();
        await gateway.dispose();
      },
    );

    test('P0: stale generation events are rejected', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);
      await _connect(bloc, gateway);

      // Emit events with stale generation (0, when active is 1)
      gateway.emit(MeetingMediaEventType.participantJoined, generation: 0);
      gateway.emit(MeetingMediaEventType.localVideoAvailable, generation: 0);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // These events should be ignored, so event log should only have sessionStarted
      expect(bloc.state.eventLog.length, 1);
      expect(
        bloc.state.eventLog.single.type,
        MeetingLogEventType.meetingStarted,
      );

      await bloc.close();
      await gateway.dispose();
    });

    test(
      'P1: terminal session failure produces failed state, not disconnected',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);

        gateway.emit(
          MeetingMediaEventType.sessionError,
          failure: const MeetingFailure(
            MeetingFailureType.nativeInitialization,
          ),
        );
        await _waitUntil(() => bloc.state.status == MeetingStatus.failed);

        expect(bloc.state.status, MeetingStatus.failed);
        expect(
          bloc.state.failure?.type,
          MeetingFailureType.nativeInitialization,
        );

        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'session startup timeout fails instead of remaining joining forever',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(
          ControllableMeetingRepository(),
          gateway,
          sessionStartTimeout: const Duration(milliseconds: 20),
        );

        bloc.add(const MeetingCreateRequested());

        await _waitUntil(
          () =>
              bloc.state.status == MeetingStatus.failed &&
              gateway.leaveCalls == 1,
        );

        expect(bloc.state.failure?.type, MeetingFailureType.meetingStart);
        expect(
          bloc.state.eventLog.last.type,
          MeetingLogEventType.sessionFailed,
        );
        expect(gateway.leaveCalls, 1);

        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'background pauses active camera and foreground restores it',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);

        await _connect(bloc, gateway);

        gateway.emit(MeetingMediaEventType.cameraEnabled, generation: 1);
        await _waitUntil(() => bloc.state.media.isCameraEnabled);

        bloc.add(const MeetingLifecycleChanged(AppLifecycleState.paused));

        await _waitUntil(() => gateway.cameraCalls == 1);

        expect(gateway.cameraEnabledRequests, <bool>[false]);

        gateway.emit(MeetingMediaEventType.cameraDisabled, generation: 1);
        await _waitUntil(() => !bloc.state.media.isCameraEnabled);

        bloc.add(const MeetingLifecycleChanged(AppLifecycleState.resumed));

        await _waitUntil(() => gateway.cameraCalls == 2);

        expect(gateway.cameraEnabledRequests, <bool>[false, true]);

        gateway.emit(MeetingMediaEventType.cameraEnabled, generation: 1);
        await _waitUntil(() => bloc.state.media.isCameraEnabled);

        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'P1: connectionPoor does not change status or increment reconnectAttempts',
      () async {
        final gateway = ControllableMeetingMediaGateway();
        final bloc = _createBloc(ControllableMeetingRepository(), gateway);
        await _connect(bloc, gateway);

        final logBeforeCount = bloc.state.eventLog.length;
        final reconnectCountBefore = bloc.state.reconnectAttempts;

        gateway.emit(MeetingMediaEventType.connectionPoor, generation: 1);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Status should still be connected, reconnectAttempts unchanged
        expect(bloc.state.status, MeetingStatus.connected);
        expect(bloc.state.reconnectAttempts, reconnectCountBefore);
        expect(bloc.state.diagnostics.networkQuality, NetworkQuality.poor);
        // But event log should include the connectionPoor entry
        expect(bloc.state.eventLog.length, greaterThan(logBeforeCount));
        expect(
          bloc.state.eventLog.last.type,
          MeetingLogEventType.connectionPoor,
        );

        gateway.emit(MeetingMediaEventType.connectionRecovered, generation: 1);

        await _waitUntil(
          () => bloc.state.diagnostics.networkQuality == NetworkQuality.good,
        );

        expect(bloc.state.status, MeetingStatus.connected);

        await bloc.close();
        await gateway.dispose();
      },
    );

    test(
      'P1: duplicate bootstrap taps are blocked before first await',
      () async {
        final repository = ControllableMeetingRepository();
        final gateway = ControllableMeetingMediaGateway();
        final connectivity = FakeConnectivityGateway(isOnline: true);
        final bloc = _createBloc(
          repository,
          gateway,
          connectivityGateway: connectivity,
        );

        // Rapid duplicate create taps
        bloc
          ..add(const MeetingCreateRequested())
          ..add(const MeetingCreateRequested());
        await _waitUntil(
          () =>
              repository.createCalls == 1 &&
              bloc.state.status == MeetingStatus.joining,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        // Only one create call should have been made
        expect(repository.createCalls, 1);

        await bloc.close();
        await gateway.dispose();
      },
    );

    test('audio playback recovery clears only the autoplay warning', () async {
      final gateway = ControllableMeetingMediaGateway();
      final bloc = _createBloc(ControllableMeetingRepository(), gateway);
      await _connect(bloc, gateway);

      gateway.emit(
        MeetingMediaEventType.audioSessionStarted,
        generation: 1,
        failure: const MeetingFailure(MeetingFailureType.audioPlaybackBlocked),
      );
      await _waitUntil(
        () =>
            bloc.state.failure?.type == MeetingFailureType.audioPlaybackBlocked,
      );

      gateway.emit(MeetingMediaEventType.audioSessionStarted, generation: 1);
      await _waitUntil(() => bloc.state.failure == null);

      expect(bloc.state.status, MeetingStatus.connected);
      expect(bloc.state.statusMessage, 'Connected');

      await bloc.close();
      await gateway.dispose();
    });
  });
}

MeetingBloc _createBloc(
  MeetingRepository repository,
  ControllableMeetingMediaGateway gateway, {
  ConnectivityGateway connectivityGateway =
      const MeetingWidgetTestConnectivityGateway(),
  MeetingPermissionGateway permissionGateway =
      const MeetingWidgetTestPermissionGateway(),
  Duration sessionStartTimeout = const Duration(seconds: 20),
}) {
  return MeetingBloc(
    createMeeting: CreateMeeting(repository, gateway),
    joinMeeting: JoinMeeting(repository, gateway),
    mediaGateway: gateway,
    permissionGateway: permissionGateway,
    connectivityGateway: connectivityGateway,
    sessionStartTimeout: sessionStartTimeout,
  );
}

Future<void> _connect(
  MeetingBloc bloc,
  ControllableMeetingMediaGateway gateway,
) async {
  bloc.add(const MeetingCreateRequested());
  await _waitUntil(() => bloc.state.meetingId != null);
  gateway.emit(MeetingMediaEventType.sessionStarted, generation: 1);
  await _waitUntil(() => bloc.state.status == MeetingStatus.connected);
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Timed out waiting for asynchronous BLoC state.');
}

final class ControllableMeetingRepository implements MeetingRepository {
  int createCalls = 0;
  int joinCalls = 0;

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
    return MeetingSuccess<MeetingBootstrap>(meetingBootstrap());
  }
}

final class FakeConnectivityGateway implements ConnectivityGateway {
  FakeConnectivityGateway({bool isOnline = true}) : _isOnline = isOnline;

  bool _isOnline;
  int checkCount = 0;

  void setOnline(bool value) {
    _isOnline = value;
  }

  @override
  Future<bool> get isOnline async {
    checkCount += 1;
    return _isOnline;
  }
}

final class CountingPermissionGateway implements MeetingPermissionGateway {
  int callCount = 0;

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  requestRequiredPermissions() async {
    callCount += 1;
    return const MeetingSuccess<MeetingPermissionStatus>(
      MeetingPermissionStatus.granted,
    );
  }

  @override
  Future<MeetingResult<MeetingPermissionStatus>>
  getRequiredPermissionStatus() async =>
      const MeetingSuccess<MeetingPermissionStatus>(
        MeetingPermissionStatus.granted,
      );

  @override
  Future<MeetingResult<bool>> openAppSettings() async =>
      const MeetingSuccess<bool>(true);
}

final class DelayedMeetingRepository implements MeetingRepository {
  final Completer<MeetingResult<MeetingBootstrap>> _firstCreate = Completer();
  int createCalls = 0;

  void completeFirstCreate() {
    _firstCreate.complete(MeetingSuccess<MeetingBootstrap>(meetingBootstrap()));
  }

  @override
  Future<MeetingResult<MeetingBootstrap>> createMeeting() {
    createCalls += 1;
    if (createCalls == 1) {
      return _firstCreate.future;
    }
    return Future<MeetingResult<MeetingBootstrap>>.value(
      MeetingSuccess<MeetingBootstrap>(meetingBootstrap()),
    );
  }

  @override
  Future<MeetingResult<MeetingBootstrap>> joinMeeting(MeetingId meetingId) {
    return Future<MeetingResult<MeetingBootstrap>>.value(
      MeetingSuccess<MeetingBootstrap>(meetingBootstrap()),
    );
  }
}

final class ControllableMeetingMediaGateway implements MeetingMediaGateway {
  ControllableMeetingMediaGateway({
    this.startResult = const MeetingSuccess<MeetingStatus>(
      MeetingStatus.joining,
    ),
  });

  final StreamController<MeetingMediaEvent> _events =
      StreamController<MeetingMediaEvent>.broadcast();
  final MeetingResult<MeetingStatus> startResult;
  MeetingResult<bool>? microphoneResult;
  MeetingResult<bool>? cameraResult;
  MeetingResult<MeetingStatus>? leaveResult;
  Completer<MeetingResult<MeetingStatus>>? leaveCompleter;
  int startCalls = 0;
  int microphoneCalls = 0;
  int cameraCalls = 0;
  final List<bool> cameraEnabledRequests = <bool>[];
  int leaveCalls = 0;
  int disposeCalls = 0;

  bool get hasEventListener => _events.hasListener;

  @override
  Stream<MeetingMediaEvent> get events => _events.stream;

  void emit(
    MeetingMediaEventType type, {
    MeetingFailure? failure,
    int? generation,
  }) {
    _events.add(
      MeetingMediaEvent(
        type: type,
        occurredAt: DateTime.utc(2026, 8, 11, 12),
        failure: failure,
        generation: generation,
      ),
    );
  }

  @override
  Future<MeetingResult<MeetingStatus>> start(MeetingBootstrap bootstrap) async {
    startCalls += 1;
    return startResult;
  }

  @override
  Future<MeetingResult<bool>> setMicrophoneEnabled(bool enabled) async {
    microphoneCalls += 1;
    return microphoneResult ?? MeetingSuccess<bool>(enabled);
  }

  @override
  Future<MeetingResult<bool>> setCameraEnabled(bool enabled) async {
    cameraCalls += 1;
    cameraEnabledRequests.add(enabled);
    return cameraResult ?? MeetingSuccess<bool>(enabled);
  }

  @override
  Future<MeetingResult<bool>> switchCamera() async {
    // Default controllable double treats switch as accepted unless overridden.
    return MeetingSuccess<bool>(true);
  }

  @override
  Future<MeetingResult<MeetingStatus>> leave() async {
    leaveCalls += 1;
    final pending = leaveCompleter;
    if (pending != null) {
      return pending.future;
    }
    return leaveResult ??
        const MeetingSuccess<MeetingStatus>(MeetingStatus.disconnected);
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _events.close();
  }
}
