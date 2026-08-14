import '../entities/meeting_bootstrap.dart';
import '../entities/meeting_failure.dart';
import '../entities/meeting_id.dart';
import '../entities/meeting_result.dart';
import '../gateways/meeting_media_gateway.dart';
import '../repositories/meeting_repository.dart';

/// Validates a user-supplied ID before requesting a client attendee.
final class JoinMeeting {
  const JoinMeeting(this._repository, this._mediaGateway);

  final MeetingRepository _repository;
  final MeetingMediaGateway _mediaGateway;

  /// Trims and validates [meetingIdInput] before invoking the repository.
  ///
  /// Invalid input becomes a normal domain result, keeping parsing exceptions
  /// out of BLoC event handling.
  Future<MeetingResult<MeetingId>> call(String meetingIdInput) async {
    try {
      final repositoryResult = await _repository.joinMeeting(
        MeetingId.fromUserInput(meetingIdInput),
      );
      return switch (repositoryResult) {
        MeetingSuccess(:final value) => _startMedia(value),
        MeetingError(:final failure) => MeetingError<MeetingId>(failure),
      };
    } on FormatException {
      return const MeetingError<MeetingId>(
        MeetingFailure(MeetingFailureType.invalidMeeting),
      );
    }
  }

  Future<MeetingResult<MeetingId>> _startMedia(
    MeetingBootstrap bootstrap,
  ) async {
    final mediaResult = await _mediaGateway.start(bootstrap);
    return switch (mediaResult) {
      MeetingSuccess() => MeetingSuccess<MeetingId>(bootstrap.meeting.id),
      MeetingError(:final failure) => MeetingError<MeetingId>(failure),
    };
  }
}
