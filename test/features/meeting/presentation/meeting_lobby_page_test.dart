import 'package:chime_meeting/features/meeting/domain/entities/meeting_failure.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_bloc.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_event.dart';
import 'package:chime_meeting/features/meeting/presentation/pages/meeting_lobby_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_fixtures.dart';
import '../../../helpers/meeting_widget_test_harness.dart';

void main() {
  testWidgets('join trims the meeting ID before repository invocation', (
    tester,
  ) async {
    final repository = MeetingWidgetTestRepository();
    final mediaGateway = MeetingWidgetTestMediaGateway();
    final bloc = createMeetingWidgetTestBloc(
      repository: repository,
      mediaGateway: mediaGateway,
    );
    addTearDown(mediaGateway.dispose);
    addTearDown(() async {
      if (!bloc.isClosed) {
        await bloc.close();
      }
    });

    await tester.pumpWidget(_app(bloc));

    await tester.enterText(
      find.byKey(const Key('meeting-id-field')),
      '  $fixtureMeetingId  ',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('join-meeting-button')));
    await tester.pump();
    await tester.pump();

    expect(repository.joinCalls, 1);
    expect(repository.joinedMeetingId?.value, fixtureMeetingId);
    bloc.add(const MeetingLeaveRequested());
    await tester.pump();
    await tester.pump();
  });

  testWidgets('join button disables for blank and whitespace-only input', (
    tester,
  ) async {
    final repository = MeetingWidgetTestRepository();
    final mediaGateway = MeetingWidgetTestMediaGateway();
    final bloc = createMeetingWidgetTestBloc(
      repository: repository,
      mediaGateway: mediaGateway,
    );
    addTearDown(mediaGateway.dispose);
    addTearDown(() async {
      if (!bloc.isClosed) {
        await bloc.close();
      }
    });

    await tester.pumpWidget(_app(bloc));

    final joinButton = find.byKey(const Key('join-meeting-button'));
    expect(tester.widget<OutlinedButton>(joinButton).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('meeting-id-field')), '   ');
    await tester.pump();
    expect(tester.widget<OutlinedButton>(joinButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('meeting-id-field')),
      '  $fixtureMeetingId  ',
    );
    await tester.pump();
    expect(tester.widget<OutlinedButton>(joinButton).onPressed, isNotNull);
    expect(repository.joinCalls, 0);
    expect(bloc.state.status, MeetingStatus.idle);
  });

  testWidgets('permission denial stops before creating a meeting', (
    tester,
  ) async {
    final repository = MeetingWidgetTestRepository();
    final mediaGateway = MeetingWidgetTestMediaGateway();
    final bloc = createMeetingWidgetTestBloc(
      repository: repository,
      mediaGateway: mediaGateway,
      permissionGateway: const MeetingWidgetTestPermissionGateway(
        granted: false,
      ),
    );
    addTearDown(mediaGateway.dispose);
    addTearDown(() async {
      if (!bloc.isClosed) {
        await bloc.close();
      }
    });

    await tester.pumpWidget(_app(bloc));
    await tester.tap(find.byKey(const Key('create-meeting-button')));
    await tester.pump();
    await tester.pump();

    expect(repository.createCalls, 0);
    expect(bloc.state.failure?.type, MeetingFailureType.permissionUnavailable);
    expect(find.byKey(const Key('meeting-failure-banner')), findsOneWidget);
  });
}

Widget _app(MeetingBloc bloc) {
  return BlocProvider<MeetingBloc>.value(
    value: bloc,
    child: const MaterialApp(home: MeetingLobbyPage()),
  );
}
