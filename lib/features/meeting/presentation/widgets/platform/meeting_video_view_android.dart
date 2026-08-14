import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/entities/meeting_video_role.dart';
import '../../../infrastructure/chime/chime_platform_bridge.dart';

typedef MeetingVideoSurfaceCallback = void Function(String elementId);

/// Native Chime render surface preserving the existing Android PlatformView.
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
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    return AndroidView(
      viewType: ChimePlatformBridge.videoViewType,
      creationParams: <String, Object>{'role': role.name},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
