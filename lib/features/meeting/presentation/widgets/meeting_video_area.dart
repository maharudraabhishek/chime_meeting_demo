import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/meeting_media_state.dart';
import '../../domain/entities/meeting_video_role.dart';
import '../bloc/meeting_bloc.dart';
import '../bloc/meeting_event.dart';
import '../bloc/meeting_state.dart';
import 'meeting_video_view.dart';

/// Composes stable native local/remote Chime video surfaces for a 1:1 call.
///
/// PlatformViews stay mounted while connected so native tile binding does not
/// depend on whether the tile or Flutter view happens to be created first.
final class MeetingVideoArea extends StatelessWidget {
  const MeetingVideoArea({super.key});

  /// Builds stable remote/local PlatformViews and availability placeholders.
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MeetingBloc, MeetingState>(
      buildWhen: (previous, current) =>
          previous.media.localVideo != current.media.localVideo ||
          previous.media.remoteVideo != current.media.remoteVideo,
      builder: (context, state) {
        final bloc = context.read<MeetingBloc>();
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(color: Colors.black),
            MeetingVideoView(
              key: const ValueKey<String>('remote-chime-video-view'),
              role: MeetingVideoRole.remote,
              onSurfaceAttached: (elementId) => bloc.add(
                MeetingVideoSurfaceAttached(MeetingVideoRole.remote, elementId),
              ),
              onSurfaceDetached: (elementId) => bloc.add(
                MeetingVideoSurfaceDetached(MeetingVideoRole.remote, elementId),
              ),
            ),
            if (state.media.remoteVideo == VideoAvailability.unavailable)
              const _VideoPlaceholder(
                icon: Icons.person_outline,
                label: 'Waiting for remote video',
              ),
            Positioned(
              top: 88,
              right: 16,
              width: 120,
              height: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.white70),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      MeetingVideoView(
                        key: const ValueKey<String>('local-chime-video-view'),
                        role: MeetingVideoRole.local,
                        onSurfaceAttached: (elementId) => bloc.add(
                          MeetingVideoSurfaceAttached(
                            MeetingVideoRole.local,
                            elementId,
                          ),
                        ),
                        onSurfaceDetached: (elementId) => bloc.add(
                          MeetingVideoSurfaceDetached(
                            MeetingVideoRole.local,
                            elementId,
                          ),
                        ),
                      ),
                      if (state.media.localVideo ==
                          VideoAvailability.unavailable)
                        const _VideoPlaceholder(
                          icon: Icons.videocam_off_outlined,
                          label: 'Camera off',
                          compact: true,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Accessible placeholder shown while a local or remote video tile is absent.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({
    required this.icon,
    required this.label,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool compact;

  /// Builds a size-aware placeholder without owning meeting state.
  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Semantics(
          label: label,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: Colors.white70, size: compact ? 28 : 48),
              SizedBox(height: compact ? 6 : 12),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: compact ? 12 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
