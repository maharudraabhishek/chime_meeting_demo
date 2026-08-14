import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_diagnostics.dart';
import '../../domain/entities/meeting_status.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_state.dart';
import '../widgets/meeting_controls.dart';
import '../widgets/meeting_failure_banner.dart';
import '../widgets/meeting_status_indicator.dart';
import '../widgets/meeting_video_area.dart';
import 'meeting_event_log_page.dart';

/// Active call surface for one local and one remote participant.
///
/// Native video stays inside Android PlatformViews; this page composes those
/// surfaces with BLoC-driven controls, meeting identity, status, and errors.
final class MeetingRoomPage extends StatelessWidget {
  const MeetingRoomPage({super.key});

  /// Builds native video surfaces, call controls, status, and safe errors.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            const Positioned.fill(child: MeetingVideoArea()),
            const Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _MeetingHeader(),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: MeetingControls(
                onShowEventLog: () => _showEventLog(context),
              ),
            ),
            // Compact diagnostics card above controls. Uses BlocSelector to
            // avoid rebuilding the video PlatformView when diagnostics change.
            Positioned(
              left: 12,
              right: 12,
              bottom: 92,
              child: BlocSelector<MeetingBloc, MeetingState, MeetingDiagnostics>(
                selector: (state) => state.diagnostics,
                builder: (context, diagnostics) {
                  if (diagnostics.connectionState == MeetingStatus.idle) {
                    return const SizedBox.shrink();
                  }
                  return GestureDetector(
                    onTap: () => _showDiagnosticsSheet(context, diagnostics),
                    child: Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 6,
                          children: <Widget>[
                            Text(
                              'Connection: ${_connectionLabel(diagnostics.connectionState)}',
                            ),
                            Text(
                              'Network: ${_networkLabel(diagnostics.networkQuality)}',
                            ),
                            Text(
                              'Mic: ${diagnostics.microphoneEnabled ? 'On' : 'Off'}',
                            ),
                            Text(
                              'Cam: ${diagnostics.cameraEnabled ? 'On' : 'Off'}',
                            ),
                            Text(
                              'Reconnect attempts: ${diagnostics.reconnectAttempts}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 76,
              left: 12,
              right: 12,
              child: BlocBuilder<MeetingBloc, MeetingState>(
                buildWhen: (previous, current) =>
                    previous.status != current.status ||
                    previous.failure != current.failure,
                builder: (context, state) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (state.status == MeetingStatus.reconnecting)
                        const _ReconnectBanner(),
                      if (state.status == MeetingStatus.reconnecting &&
                          state.failure != null)
                        const SizedBox(height: 8),
                      if (state.failure != null)
                        MeetingFailureBanner(failure: state.failure!),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the current meeting event log without changing meeting state.
  void _showEventLog(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MeetingEventLogPage()),
    );
  }
}

final class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.tertiaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.sync, color: colors.onTertiaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Connection interrupted. Reconnecting…',
                style: TextStyle(color: colors.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Displays the active meeting status and copyable backend-issued identifier.
class _MeetingHeader extends StatelessWidget {
  const _MeetingHeader();

  /// Builds the compact active-call header from selected BLoC state.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MeetingBloc, MeetingState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.meetingId != current.meetingId,
      builder: (context, state) {
        final meetingId = state.meetingId?.value;
        return Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: <Widget>[
                MeetingStatusIndicator(status: state.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    meetingId == null
                        ? 'Meeting ID pending'
                        : 'Meeting: $meetingId',
                    key: const Key('active-meeting-id'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (meetingId != null)
                  IconButton(
                    key: const Key('copy-meeting-id-button'),
                    tooltip: 'Copy meeting ID',
                    onPressed: () => _copyMeetingId(context, meetingId),
                    icon: const Icon(Icons.copy),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Copies the exact meeting ID and confirms the action without exposing credentials.
  Future<void> _copyMeetingId(BuildContext context, String meetingId) async {
    await Clipboard.setData(ClipboardData(text: meetingId));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Meeting ID copied.')));
  }
}

void _showDiagnosticsSheet(
  BuildContext context,
  MeetingDiagnostics diagnostics,
) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Connection: ${_connectionLabel(diagnostics.connectionState)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Network: ${_networkLabel(diagnostics.networkQuality)}'),
            const SizedBox(height: 8),
            Text('Reconnect attempts: ${diagnostics.reconnectAttempts}'),
            const SizedBox(height: 8),
            Text('Microphone: ${diagnostics.microphoneEnabled ? 'On' : 'Off'}'),
            const SizedBox(height: 8),
            Text('Camera: ${diagnostics.cameraEnabled ? 'On' : 'Off'}'),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

String _connectionLabel(MeetingStatus status) => switch (status) {
  MeetingStatus.idle => 'Idle',
  MeetingStatus.joining => 'Joining',
  MeetingStatus.connected => 'Connected',
  MeetingStatus.reconnecting => 'Reconnecting',
  MeetingStatus.disconnected => 'Disconnected',
  MeetingStatus.failed => 'Failed',
};

String _networkLabel(NetworkQuality q) => switch (q) {
  NetworkQuality.good => 'Good',
  NetworkQuality.poor => 'Poor',
  NetworkQuality.unknown => 'Unknown',
};
