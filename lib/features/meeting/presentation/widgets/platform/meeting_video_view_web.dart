import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../../../domain/entities/meeting_video_role.dart';

typedef MeetingVideoSurfaceCallback = void Function(String elementId);

/// Flutter Web surface whose DOM element is bound by the media gateway.
final class MeetingVideoView extends StatefulWidget {
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
  State<MeetingVideoView> createState() => _MeetingVideoViewState();
}

final class _MeetingVideoViewState extends State<MeetingVideoView> {
  late final String _elementId =
      'chime-${widget.role.name}-video-${identityHashCode(this)}';
  bool _attached = false;
  web.ResizeObserver? _attachmentObserver;

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'video',
      onElementCreated: (element) {
        final video = element as web.HTMLVideoElement;
        video
          ..id = _elementId
          ..autoplay = true
          ..controls = false
          ..muted = true
          ..playsInline = true;
        video.style
          ..width = '100%'
          ..height = '100%'
          ..objectFit = 'cover'
          ..backgroundColor = 'black';

        // HtmlElementView creates the element before inserting it into the DOM.
        // Wait until it is queryable so the bridge cannot lose an element-first
        // or tile-first bind while resolving the stable identifier.
        _attachmentObserver?.disconnect();
        _attachmentObserver = web.ResizeObserver(
          (
                JSArray<web.ResizeObserverEntry> entries,
                web.ResizeObserver observer,
              ) {
                if (!_attached && mounted && video.isConnected) {
                  observer.disconnect();
                  _attachmentObserver = null;
                  // Meeting audio is owned by the bridge's hidden audio element.
                  // Muted video surfaces prevent duplicate playback.
                  _attached = true;
                  widget.onSurfaceAttached?.call(_elementId);
                }
              }
              .toJS,
        )..observe(video);
      },
    );
  }

  @override
  void dispose() {
    _attachmentObserver?.disconnect();
    _attachmentObserver = null;
    if (_attached) {
      widget.onSurfaceDetached?.call(_elementId);
    }
    super.dispose();
  }
}
