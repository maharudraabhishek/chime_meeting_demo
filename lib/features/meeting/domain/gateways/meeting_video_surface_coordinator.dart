import '../entities/meeting_video_role.dart';

/// Coordinates Flutter-owned video surfaces with the active media adapter.
///
/// The surface is represented only by a stable platform identifier. Widgets do
/// not call a browser or native SDK, and implementations retain ownership of
/// tile binding and stale-session protection.
abstract interface class MeetingVideoSurfaceCoordinator {
  Future<void> attachVideoSurface(MeetingVideoRole role, String elementId);

  Future<void> detachVideoSurface(MeetingVideoRole role, String elementId);
}
