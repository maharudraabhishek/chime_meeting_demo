import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_log_entry.dart';
import '../../domain/entities/meeting_status.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_state.dart';

/// Displays the safe meeting callback history as a scrolling list.
///
/// Entries are presentation-safe domain values produced by real meeting actions
/// and native callbacks; credentials and native SDK objects never enter this UI.
final class MeetingEventLogPage extends StatelessWidget {
  const MeetingEventLogPage({super.key});

  /// Builds the scrolling event history for the active or last session.
  @override
  Widget build(BuildContext context) {
    return BlocListener<MeetingBloc, MeetingState>(
      listenWhen: (previous, current) {
        final wasActive =
            previous.status == MeetingStatus.connected ||
            previous.status == MeetingStatus.reconnecting;

        final isTerminal =
            current.status == MeetingStatus.disconnected ||
            current.status == MeetingStatus.failed;

        return wasActive && isTerminal;
      },
      listener: (context, state) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Meeting event log')),
        body: SafeArea(
          child: BlocBuilder<MeetingBloc, MeetingState>(
            buildWhen: (previous, current) =>
                previous.eventLog != current.eventLog,
            builder: (context, state) {
              if (state.eventLog.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Meeting events will appear here as they occur.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView.separated(
                key: const Key('meeting-event-log-list'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: state.eventLog.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = state.eventLog[index];
                  return ListTile(
                    leading: Icon(_iconFor(entry.type)),
                    title: Text(_labelFor(entry.type)),
                    trailing: Text(
                      _timeLabel(entry.occurredAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  /// Returns the user-facing label for one safe domain log event.
  String _labelFor(MeetingLogEventType type) => switch (type) {
    MeetingLogEventType.meetingStarted => 'Meeting started',
    MeetingLogEventType.meetingEnded => 'Meeting ended',
    MeetingLogEventType.audioSessionStarted => 'Audio session started',
    MeetingLogEventType.audioSessionStopped => 'Audio session stopped',
    MeetingLogEventType.participantJoined => 'Participant joined',
    MeetingLogEventType.participantLeft => 'Participant left',
    MeetingLogEventType.localVideoAvailable => 'Local video available',
    MeetingLogEventType.localVideoRemoved => 'Local video removed',
    MeetingLogEventType.remoteVideoAvailable => 'Remote video available',
    MeetingLogEventType.remoteVideoRemoved => 'Remote video removed',
    MeetingLogEventType.localVideoPaused => 'Local video paused',
    MeetingLogEventType.localVideoResumed => 'Local video resumed',
    MeetingLogEventType.remoteVideoPaused => 'Remote video paused',
    MeetingLogEventType.remoteVideoResumed => 'Remote video resumed',
    MeetingLogEventType.microphoneEnabled => 'Microphone enabled',
    MeetingLogEventType.microphoneDisabled => 'Microphone disabled',
    MeetingLogEventType.localMuted => 'Local muted',
    MeetingLogEventType.localUnmuted => 'Local unmuted',
    MeetingLogEventType.remoteMuted => 'Remote muted',
    MeetingLogEventType.remoteUnmuted => 'Remote unmuted',
    MeetingLogEventType.cameraEnabled => 'Camera enabled',
    MeetingLogEventType.cameraDisabled => 'Camera disabled',
    MeetingLogEventType.reconnectAttempt => 'Reconnect attempt',
    MeetingLogEventType.connectionRecovered => 'Connection recovered',
    MeetingLogEventType.connectionPoor => 'Connection poor',
    MeetingLogEventType.activeSpeaker => 'Active speaker',
    MeetingLogEventType.volumeLevel => 'Volume indication',
    MeetingLogEventType.audioDeviceChanged => 'Audio device changed',
    MeetingLogEventType.sessionFailed => 'Meeting failed',
  };

  /// Returns a compact semantic icon for one event category.
  IconData _iconFor(MeetingLogEventType type) => switch (type) {
    MeetingLogEventType.meetingStarted => Icons.call,
    MeetingLogEventType.meetingEnded => Icons.call_end,
    MeetingLogEventType.audioSessionStarted => Icons.volume_up,
    MeetingLogEventType.audioSessionStopped => Icons.volume_off,
    MeetingLogEventType.participantJoined => Icons.person_add_alt_1,
    MeetingLogEventType.participantLeft => Icons.person_remove_alt_1,
    MeetingLogEventType.localVideoAvailable => Icons.videocam,
    MeetingLogEventType.localVideoRemoved => Icons.videocam_off,
    MeetingLogEventType.remoteVideoAvailable => Icons.screen_share,
    MeetingLogEventType.remoteVideoRemoved => Icons.stop_screen_share,
    MeetingLogEventType.localVideoPaused => Icons.pause,
    MeetingLogEventType.localVideoResumed => Icons.play_arrow,
    MeetingLogEventType.remoteVideoPaused => Icons.pause,
    MeetingLogEventType.remoteVideoResumed => Icons.play_arrow,
    MeetingLogEventType.microphoneEnabled => Icons.mic,
    MeetingLogEventType.microphoneDisabled => Icons.mic_off,
    MeetingLogEventType.localMuted => Icons.mic_off,
    MeetingLogEventType.localUnmuted => Icons.mic,
    MeetingLogEventType.remoteMuted => Icons.mic_off,
    MeetingLogEventType.remoteUnmuted => Icons.mic,
    MeetingLogEventType.cameraEnabled => Icons.videocam,
    MeetingLogEventType.cameraDisabled => Icons.videocam_off,
    MeetingLogEventType.reconnectAttempt => Icons.sync,
    MeetingLogEventType.connectionRecovered => Icons.wifi,
    MeetingLogEventType.connectionPoor => Icons.wifi_off,
    MeetingLogEventType.activeSpeaker => Icons.record_voice_over,
    MeetingLogEventType.volumeLevel => Icons.graphic_eq,
    MeetingLogEventType.audioDeviceChanged => Icons.headphones,
    MeetingLogEventType.sessionFailed => Icons.error_outline,
  };

  /// Formats an event timestamp in local `HH:mm:ss` form for the log.
  String _timeLabel(DateTime time) {
    final local = time.toLocal();
    return '${_twoDigits(local.hour)}:'
        '${_twoDigits(local.minute)}:'
        '${_twoDigits(local.second)}';
  }

  /// Pads one clock component to two digits.
  String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
