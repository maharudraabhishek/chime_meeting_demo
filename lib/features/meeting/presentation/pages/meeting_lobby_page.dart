import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_id.dart';
import '../../domain/entities/meeting_status.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_event.dart';
import '../bloc/meeting_state.dart';
import '../widgets/meeting_failure_banner.dart';
import '../widgets/meeting_status_indicator.dart';
import 'meeting_event_log_page.dart';

/// Entry screen for creating a meeting or joining an existing meeting ID.
///
/// The page owns only presentation-local form state. Permissions, networking,
/// business rules, and Chime startup remain behind [MeetingBloc] and its
/// domain/infrastructure dependencies.
final class MeetingLobbyPage extends StatefulWidget {
  const MeetingLobbyPage({super.key});

  /// Creates the presentation-local state that owns the join form controller.
  @override
  State<MeetingLobbyPage> createState() => _MeetingLobbyPageState();
}

/// Owns transient join-form state without duplicating meeting application state.
class _MeetingLobbyPageState extends State<MeetingLobbyPage> {
  final GlobalKey<FormState> _joinFormKey = GlobalKey<FormState>();
  final TextEditingController _meetingIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _meetingIdController.addListener(_handleMeetingIdChanged);
  }

  /// Releases the text controller when the lobby leaves the widget tree.
  @override
  void dispose() {
    _meetingIdController.removeListener(_handleMeetingIdChanged);
    _meetingIdController.dispose();
    super.dispose();
  }

  void _handleMeetingIdChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  /// Builds the create/join experience from immutable BLoC state.
  @override
  Widget build(BuildContext context) {
    final meetingIdInput = _meetingIdController.text.trim();
    final isJoinEnabled =
        !_isJoiningInProgress() && _hasValidMeetingId(meetingIdInput);

    return Scaffold(
      appBar: AppBar(title: const Text('Chime Meeting')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: BlocBuilder<MeetingBloc, MeetingState>(
                builder: (context, state) {
                  final isJoining = state.status == MeetingStatus.joining;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        '1:1 video meeting',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create a meeting on this device, or enter the exact '
                        'meeting ID from the other participant.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: MeetingStatusIndicator(status: state.status),
                      ),
                      if (state.statusMessage != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          state.statusMessage!,
                          key: const Key('meeting-status-message'),
                        ),
                      ],
                      if (state.failure != null) ...<Widget>[
                        const SizedBox(height: 12),
                        MeetingFailureBanner(failure: state.failure!),
                      ],
                      if (isJoining && state.meetingId != null) ...<Widget>[
                        const SizedBox(height: 12),
                        SelectableText(
                          'Meeting ID: ${state.meetingId!.value}',
                          key: const Key('meeting-id-during-join'),
                        ),
                      ],
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        key: const Key('create-meeting-button'),
                        onPressed: isJoining
                            ? null
                            : () {
                                FocusScope.of(context).unfocus();
                                context.read<MeetingBloc>().add(
                                  const MeetingCreateRequested(),
                                );
                              },
                        icon: isJoining
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_call),
                        label: Text(
                          isJoining ? 'Starting meeting…' : 'Create meeting',
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: <Widget>[
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Form(
                        key: _joinFormKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            TextFormField(
                              key: const Key('meeting-id-field'),
                              controller: _meetingIdController,
                              enabled: !isJoining,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                border: OutlineInputBorder(),
                                labelText: 'Meeting ID',
                                hintText: 'Paste the meeting ID',
                              ),
                              validator: (value) => _hasValidMeetingId(value)
                                  ? null
                                  : 'Enter a meeting ID.',
                              onFieldSubmitted: isJoinEnabled
                                  ? (_) => _joinMeeting()
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              key: const Key('join-meeting-button'),
                              onPressed: isJoinEnabled ? _joinMeeting : null,
                              icon: const Icon(Icons.video_call_outlined),
                              label: const Text('Join meeting'),
                            ),
                          ],
                        ),
                      ),
                      if (state.eventLog.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 20),
                        TextButton.icon(
                          key: const Key('view-last-event-log-button'),
                          onPressed: isJoining
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => const MeetingEventLogPage(),
                                  ),
                                ),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: Text(
                            'View event log (${state.eventLog.length})',
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isJoiningInProgress() {
    final state = context.read<MeetingBloc>().state;
    return state.status == MeetingStatus.joining;
  }

  bool _hasValidMeetingId(String? value) {
    if (value == null) {
      return false;
    }
    try {
      MeetingId.fromUserInput(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Validates presentation input before requesting permissions or backend work.
  void _joinMeeting() {
    FocusScope.of(context).unfocus();
    final trimmedMeetingId = _meetingIdController.text.trim();
    if (!_hasValidMeetingId(trimmedMeetingId)) {
      _joinFormKey.currentState?.validate();
      return;
    }
    context.read<MeetingBloc>().add(MeetingJoinRequested(trimmedMeetingId));
  }
}
