import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_failure.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_event.dart';

/// Displays a safe domain failure without exposing transport or SDK details.
final class MeetingFailureBanner extends StatelessWidget {
  const MeetingFailureBanner({required this.failure, super.key});

  final MeetingFailure failure;

  /// Builds an accessible live-region banner from a safe domain message.
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const Key('meeting-failure-banner'),
        color: colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      failure.userMessage,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                    const SizedBox(height: 8),
                    // Action buttons depend on the failure type: Retry for normal
                    // denial, Open Settings for permanent denial.
                    if (failure.type ==
                        MeetingFailureType.permissionUnavailable)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          key: const Key('permission-retry-button'),
                          onPressed: () => _onRetry(context),
                          child: const Text('Retry'),
                        ),
                      ),
                    if (failure.type ==
                        MeetingFailureType.permissionPermanentlyDenied)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          key: const Key('permission-open-settings-button'),
                          onPressed: () => _onOpenSettings(context),
                          child: const Text('Open settings'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onRetry(BuildContext context) {
    // Widgets only emit intents; BLoC handles the permission flow.
    try {
      final bloc = context.read<MeetingBloc>();
      bloc.add(const MeetingRetryPermissionsRequested());
    } catch (_) {
      /* no-op for test harness or when BLoC not available */
    }
  }

  void _onOpenSettings(BuildContext context) {
    try {
      final bloc = context.read<MeetingBloc>();
      bloc.add(const MeetingOpenSettingsRequested());
    } catch (_) {
      /* no-op when BLoC not available */
    }
  }
}
