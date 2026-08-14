import '../entities/meeting_bootstrap.dart';
import '../entities/meeting_id.dart';
import '../entities/meeting_result.dart';

/// Intent-based backend boundary for creating and joining meetings.
///
/// Callers do not know request methods, participant `type` values, JSON shapes,
/// or the HTTP package used by the data implementation.
abstract interface class MeetingRepository {
  /// Creates a new meeting and returns credentials for its agent attendee.
  Future<MeetingResult<MeetingBootstrap>> createMeeting();

  /// Requests a new client attendee for the exact API-issued [meetingId].
  Future<MeetingResult<MeetingBootstrap>> joinMeeting(MeetingId meetingId);
}
