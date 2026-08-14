import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_media_state.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_event.dart';
import '../bloc/meeting_state.dart';

/// Call controls backed exclusively by [MeetingBloc] state.
///
/// Microphone changes use the native command result while camera appearance
/// follows Chime callbacks, preserving the media layer as the camera authority.
final class MeetingControls extends StatelessWidget {
  const MeetingControls({required this.onShowEventLog, super.key});

  final VoidCallback onShowEventLog;

  /// Builds the supported controls from selected media state.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MeetingBloc, MeetingState>(
      buildWhen: (previous, current) =>
          previous.media.isMicrophoneEnabled !=
              current.media.isMicrophoneEnabled ||
          previous.media.isCameraEnabled != current.media.isCameraEnabled ||
          previous.media.localVideo != current.media.localVideo,
      builder: (context, state) {
        final colorScheme = Theme.of(context).colorScheme;
        return Material(
          elevation: 4,
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _MeetingControlButton(
                  key: const Key('meeting-microphone-toggle'),
                  tooltip: state.media.isMicrophoneEnabled
                      ? 'Mute microphone'
                      : 'Enable microphone',
                  icon: state.media.isMicrophoneEnabled
                      ? Icons.mic
                      : Icons.mic_off,
                  onPressed: () => context.read<MeetingBloc>().add(
                    MeetingMicrophoneChanged(!state.media.isMicrophoneEnabled),
                  ),
                ),
                _MeetingControlButton(
                  key: const Key('meeting-camera-toggle'),
                  tooltip: state.media.isCameraEnabled
                      ? 'Turn camera off'
                      : 'Turn camera on',
                  icon: state.media.isCameraEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  onPressed: () => context.read<MeetingBloc>().add(
                    MeetingCameraChanged(!state.media.isCameraEnabled),
                  ),
                ),
                _MeetingControlButton(
                  key: const Key('meeting-switch-camera-button'),
                  tooltip: 'Switch camera',
                  icon: Icons.cameraswitch,
                  onPressed:
                      state.media.isCameraEnabled &&
                          state.media.localVideo == VideoAvailability.available
                      ? () => context.read<MeetingBloc>().add(
                          const MeetingSwitchCameraRequested(),
                        )
                      : null,
                ),
                _MeetingControlButton(
                  key: const Key('meeting-event-log-button'),
                  tooltip: 'Open event log',
                  icon: Icons.receipt_long_outlined,
                  onPressed: onShowEventLog,
                ),
                _MeetingControlButton(
                  key: const Key('meeting-leave-button'),
                  tooltip: 'Leave meeting',
                  icon: Icons.call_end,
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                  onPressed: () => context.read<MeetingBloc>().add(
                    const MeetingLeaveRequested(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Reusable accessible call-control button with a minimum 48dp touch target.
class _MeetingControlButton extends StatelessWidget {
  const _MeetingControlButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// Builds one semantic icon control with optional destructive styling.
  @override
  Widget build(BuildContext context) {
    final button = IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(48),
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      ),
      icon: Icon(icon),
    );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: tooltip,
      child: button,
    );
  }
}
