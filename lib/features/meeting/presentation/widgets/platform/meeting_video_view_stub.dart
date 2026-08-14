import 'package:flutter/widgets.dart';

import '../../../domain/entities/meeting_video_role.dart';

typedef MeetingVideoSurfaceCallback = void Function(String elementId);

/// Empty surface used on platforms without a meeting video implementation.
final class MeetingVideoView extends StatelessWidget {
  const MeetingVideoView({
    required this.role,
    this.onSurfaceAttached,
    this.onSurfaceDetached,
    super.key,
  });

  final MeetingVideoRole role;
  final MeetingVideoSurfaceCallback? onSurfaceAttached;
  final MeetingVideoSurfaceCallback? onSurfaceDetached;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
