import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/app_lifecycle_listener.dart';

import '../../domain/entities/meeting_status.dart';
import '../../infrastructure/lifecycle/meeting_lifecycle_policy.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_event.dart';
import '../bloc/meeting_state.dart';
import 'meeting_lobby_page.dart';
import 'meeting_room_page.dart';

/// Presentation root that renders the lobby or active meeting.
///
/// Navigation between lobby and call UI is derived from [MeetingState] rather
/// than imperative route commands, keeping the BLoC lifecycle as the single
/// authority for meeting connectivity.
final class MeetingFlowPage extends StatefulWidget {
  const MeetingFlowPage({super.key});

  @override
  State<MeetingFlowPage> createState() => _MeetingFlowPageState();
}

class _MeetingFlowPageState extends State<MeetingFlowPage> {
  late final SimpleAppLifecycleObserver _appLifecycleListener;

  @override
  void initState() {
    super.initState();
    _appLifecycleListener = SimpleAppLifecycleObserver(
      onStateChange: (state) {
        if (!mounted || !shouldForwardMeetingLifecycle(state)) {
          return;
        }
        context.read<MeetingBloc>().add(MeetingLifecycleChanged(state));
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !shouldForwardMeetingLifecycle(AppLifecycleState.resumed)) {
        return;
      }
      context.read<MeetingBloc>().add(
        const MeetingInitialPermissionsRequested(),
      );
    });
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    super.dispose();
  }

  /// Selects lobby or call UI directly from the authoritative meeting status.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MeetingBloc, MeetingState>(
      buildWhen: (previous, current) => previous.status != current.status,
      builder: (context, state) {
        return state.status == MeetingStatus.connected ||
                state.status == MeetingStatus.reconnecting
            ? const MeetingRoomPage()
            : const MeetingLobbyPage();
      },
    );
  }
}
