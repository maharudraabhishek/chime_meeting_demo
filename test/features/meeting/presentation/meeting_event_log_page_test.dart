import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_status.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_bloc.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_event.dart';
import 'package:chime_meeting/features/meeting/presentation/pages/meeting_event_log_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_widget_test_harness.dart';

void main() {
  testWidgets('renders required Stage 1 event labels from real BLoC events', (
    tester,
  ) async {
    final mediaGateway = MeetingWidgetTestMediaGateway();
    final bloc = createMeetingWidgetTestBloc(mediaGateway: mediaGateway);
    addTearDown(mediaGateway.dispose);
    addTearDown(bloc.close);

    bloc.add(const MeetingCreateRequested());
    await _pumpUntil(
      tester,
      () => bloc.state.meetingId != null,
      description: 'meeting bootstrap to finish',
    );

    mediaGateway.emit(MeetingMediaEventType.sessionStarted);
    await _pumpUntil(
      tester,
      () => bloc.state.status == MeetingStatus.connected,
      description: 'native session start callback',
    );

    mediaGateway.emit(MeetingMediaEventType.participantJoined);
    mediaGateway.emit(MeetingMediaEventType.microphoneEnabled);
    mediaGateway.emit(MeetingMediaEventType.cameraEnabled);
    await _pumpUntil(
      tester,
      () => bloc.state.eventLog.length >= 4,
      description: 'event log to update from media callbacks',
    );

    await tester.pumpWidget(
      BlocProvider<MeetingBloc>.value(
        value: bloc,
        child: const MaterialApp(home: MeetingEventLogPage()),
      ),
    );
    await tester.pump();

    expect(find.text('Meeting started'), findsOneWidget);
    expect(find.text('Participant joined'), findsOneWidget);
    expect(find.text('Microphone enabled'), findsOneWidget);
    expect(find.text('Camera enabled'), findsOneWidget);
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String description,
  int maxSteps = 200,
}) async {
  for (var attempt = 0; attempt < maxSteps; attempt += 1) {
    if (predicate()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Timed out waiting for $description.');
}
