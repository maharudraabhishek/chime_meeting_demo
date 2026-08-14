import 'package:equatable/equatable.dart';

/// Whether a local or remote video source is currently available to render.
enum VideoAvailability { unavailable, available }

/// Cohesive snapshot of controllable and renderable meeting media.
///
/// Grouping these values prevents presentation state from becoming a loose set
/// of independently mutable flags.
final class MeetingMediaState extends Equatable {
  const MeetingMediaState({
    this.isMicrophoneEnabled = false,
    this.isCameraEnabled = false,
    this.localVideo = VideoAvailability.unavailable,
    this.remoteVideo = VideoAvailability.unavailable,
  });

  final bool isMicrophoneEnabled;
  final bool isCameraEnabled;
  final VideoAvailability localVideo;
  final VideoAvailability remoteVideo;

  @override
  List<Object> get props => <Object>[
    isMicrophoneEnabled,
    isCameraEnabled,
    localVideo,
    remoteVideo,
  ];
}
