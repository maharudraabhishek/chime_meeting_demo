import 'package:flutter/material.dart';

import '../../domain/entities/meeting_status.dart';

/// Compact, accessible representation of the meeting connection state.
final class MeetingStatusIndicator extends StatelessWidget {
  const MeetingStatusIndicator({required this.status, super.key});

  final MeetingStatus status;

  /// Builds a semantic chip for exactly one of the four required statuses.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final label = switch (status) {
      MeetingStatus.idle => 'Idle',
      MeetingStatus.joining => 'Joining',
      MeetingStatus.connected => 'Connected',
      MeetingStatus.reconnecting => 'Reconnecting',
      MeetingStatus.disconnected => 'Disconnected',
      MeetingStatus.failed => 'Failed',
    };
    final icon = switch (status) {
      MeetingStatus.idle => Icons.pause_circle_outline,
      MeetingStatus.joining => Icons.sync,
      MeetingStatus.connected => Icons.check_circle_outline,
      MeetingStatus.reconnecting => Icons.autorenew,
      MeetingStatus.disconnected => Icons.call_end_outlined,
      MeetingStatus.failed => Icons.error_outline,
    };

    return Semantics(
      label: 'Meeting status',
      value: label,
      child: Chip(
        key: const Key('meeting-status-indicator'),
        avatar: Icon(icon, size: 18),
        label: Text(label),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    );
  }
}
