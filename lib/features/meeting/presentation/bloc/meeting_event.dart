import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../domain/entities/meeting_media_event.dart';
import '../../domain/entities/meeting_video_role.dart';

/// Presentation intents accepted by [MeetingBloc].
sealed class MeetingEvent extends Equatable {
  const MeetingEvent();
}

/// Requests creation of a meeting and its agent attendee credentials.
final class MeetingCreateRequested extends MeetingEvent {
  const MeetingCreateRequested();

  @override
  List<Object> get props => const <Object>[];
}

/// Requests client credentials for an existing meeting ID.
final class MeetingJoinRequested extends MeetingEvent {
  const MeetingJoinRequested(this.meetingIdInput);

  final String meetingIdInput;

  @override
  List<Object> get props => <Object>[meetingIdInput];
}

/// Requests the camera and microphone permissions once when the meeting flow is
/// first shown after app launch.
final class MeetingInitialPermissionsRequested extends MeetingEvent {
  const MeetingInitialPermissionsRequested();

  @override
  List<Object> get props => const <Object>[];
}

/// Requests a retry of the permission flow (user tapped Retry). This may show
/// the platform permission UI again.
final class MeetingRetryPermissionsRequested extends MeetingEvent {
  const MeetingRetryPermissionsRequested();

  @override
  List<Object> get props => const <Object>[];
}

/// Requests the platform app settings be opened so the user may enable
/// permissions. The UI drives this intent; the BLoC does not auto-check after.
final class MeetingOpenSettingsRequested extends MeetingEvent {
  const MeetingOpenSettingsRequested();

  @override
  List<Object> get props => const <Object>[];
}

/// Requests a local microphone state change from the active session.
final class MeetingMicrophoneChanged extends MeetingEvent {
  const MeetingMicrophoneChanged(this.enabled);

  final bool enabled;

  @override
  List<Object> get props => <Object>[enabled];
}

/// Requests a local camera state change from the active session.
final class MeetingCameraChanged extends MeetingEvent {
  const MeetingCameraChanged(this.enabled);

  final bool enabled;

  @override
  List<Object> get props => <Object>[enabled];
}

/// Requests a camera-facing switch (front/back) from the active session.
final class MeetingSwitchCameraRequested extends MeetingEvent {
  const MeetingSwitchCameraRequested();

  @override
  List<Object> get props => const <Object>[];
}

/// Requests an orderly leave from the active native meeting session.
final class MeetingLeaveRequested extends MeetingEvent {
  const MeetingLeaveRequested();

  @override
  List<Object> get props => const <Object>[];
}

/// Carries the current app lifecycle state into the meeting state machine.
final class MeetingLifecycleChanged extends MeetingEvent {
  const MeetingLifecycleChanged(this.state);

  final AppLifecycleState state;

  @override
  List<Object> get props => <Object>[state];
}

/// Internal watchdog event fired if native Chime never confirms session start.
final class MeetingSessionStartTimedOut extends MeetingEvent {
  const MeetingSessionStartTimedOut(this.sessionIdentity);

  final int sessionIdentity;

  @override
  List<Object> get props => <Object>[sessionIdentity];
}

/// Internal watchdog event for one specific reconnect episode and session.
final class MeetingReconnectTimedOut extends MeetingEvent {
  const MeetingReconnectTimedOut({
    required this.sessionIdentity,
    required this.episode,
    this.generation,
  });

  final int sessionIdentity;
  final int episode;
  final int? generation;

  @override
  List<Object?> get props => <Object?>[sessionIdentity, episode, generation];
}

/// Delivers an SDK-independent gateway callback into the BLoC event queue.
///
/// Presentation widgets should not create this event directly; it is public
/// only because Dart sealed subclasses must share this library.
final class MeetingMediaEventReceived extends MeetingEvent {
  const MeetingMediaEventReceived(this.mediaEvent);

  final MeetingMediaEvent mediaEvent;

  @override
  List<Object> get props => <Object>[mediaEvent];
}

/// Reports creation of a Flutter-owned video surface to the media adapter.
final class MeetingVideoSurfaceAttached extends MeetingEvent {
  const MeetingVideoSurfaceAttached(this.role, this.elementId);

  final MeetingVideoRole role;
  final String elementId;

  @override
  List<Object> get props => <Object>[role, elementId];
}

/// Reports disposal of a Flutter-owned video surface to the media adapter.
final class MeetingVideoSurfaceDetached extends MeetingEvent {
  const MeetingVideoSurfaceDetached(this.role, this.elementId);

  final MeetingVideoRole role;
  final String elementId;

  @override
  List<Object> get props => <Object>[role, elementId];
}
