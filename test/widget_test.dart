import 'package:chime_meeting/app/app.dart';
import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_event.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/meeting_widget_test_harness.dart';

void main() {
  testWidgets('missing build configuration renders a safe first frame', (
    tester,
  ) async {
    await tester.pumpWidget(const ChimeMeetingConfigurationErrorApp());

    expect(find.text('App configuration required'), findsOneWidget);
    expect(
      find.text('Rebuild with a valid HTTPS MEETING_API_BASE_URL.'),
      findsOneWidget,
    );
  });

  testWidgets('app starts on the Stage 1 meeting lobby', (tester) async {
    final mediaGateway = MeetingWidgetTestMediaGateway();
    final bloc = createMeetingWidgetTestBloc(mediaGateway: mediaGateway);
    addTearDown(mediaGateway.dispose);

    await tester.pumpWidget(ChimeMeetingApp(createMeetingBloc: () => bloc));

    expect(find.text('Chime Meeting'), findsOneWidget);
    expect(find.text('1:1 video meeting'), findsOneWidget);
    expect(find.byKey(const Key('create-meeting-button')), findsOneWidget);
    expect(find.byKey(const Key('join-meeting-button')), findsOneWidget);
  });

  testWidgets('connected state shows room and leave returns to lobby', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final mediaGateway = MeetingWidgetTestMediaGateway();
      final bloc = createMeetingWidgetTestBloc(mediaGateway: mediaGateway);
      addTearDown(mediaGateway.dispose);

      await tester.pumpWidget(ChimeMeetingApp(createMeetingBloc: () => bloc));

      bloc.add(const MeetingCreateRequested());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      mediaGateway.emit(MeetingMediaEventType.sessionStarted);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const Key('meeting-leave-button')), findsOneWidget);
      expect(find.byKey(const Key('active-meeting-id')), findsOneWidget);

      await tester.tap(find.byKey(const Key('meeting-leave-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const Key('create-meeting-button')), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(
        find.byKey(const Key('view-last-event-log-button')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
