import 'package:chime_meeting/features/meeting/domain/entities/meeting_media_event.dart';
import 'package:chime_meeting/features/meeting/infrastructure/chime/chime_video_view.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_bloc.dart';
import 'package:chime_meeting/features/meeting/presentation/bloc/meeting_event.dart';
import 'package:chime_meeting/features/meeting/presentation/pages/meeting_room_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/meeting_widget_test_harness.dart';

void main() {
  testWidgets('room exposes local/remote video and Stage 1 controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final mediaGateway = MeetingWidgetTestMediaGateway();
      final bloc = createMeetingWidgetTestBloc(mediaGateway: mediaGateway);
      addTearDown(mediaGateway.dispose);
      addTearDown(bloc.close);

      await tester.pumpWidget(_app(bloc));
      bloc.add(const MeetingCreateRequested());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      mediaGateway.emit(MeetingMediaEventType.sessionStarted);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      final videoViews = tester
          .widgetList<ChimeVideoView>(find.byType(ChimeVideoView))
          .toList();
      expect(videoViews, hasLength(2));
      expect(videoViews.map((view) => view.role).toSet(), <ChimeVideoViewRole>{
        ChimeVideoViewRole.local,
        ChimeVideoViewRole.remote,
      });
      expect(
        find.byKey(const Key('meeting-microphone-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('meeting-camera-toggle')), findsOneWidget);
      expect(find.byKey(const Key('meeting-leave-button')), findsOneWidget);
      expect(find.byKey(const Key('meeting-event-log-button')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('camera UI waits for native media callback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final mediaGateway = MeetingWidgetTestMediaGateway();
      final bloc = createMeetingWidgetTestBloc(mediaGateway: mediaGateway);
      addTearDown(mediaGateway.dispose);
      addTearDown(bloc.close);

      await tester.pumpWidget(_app(bloc));
      bloc.add(const MeetingCreateRequested());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      mediaGateway.emit(MeetingMediaEventType.sessionStarted);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      await tester.tap(find.byKey(const Key('meeting-camera-toggle')));
      await tester.pump();

      expect(mediaGateway.cameraCalls, 1);
      expect(bloc.state.media.isCameraEnabled, isFalse);

      mediaGateway.emit(MeetingMediaEventType.cameraEnabled);
      await tester.pump();

      expect(bloc.state.media.isCameraEnabled, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _app(MeetingBloc bloc) {
  return BlocProvider<MeetingBloc>.value(
    value: bloc,
    child: const MaterialApp(home: MeetingRoomPage()),
  );
}
