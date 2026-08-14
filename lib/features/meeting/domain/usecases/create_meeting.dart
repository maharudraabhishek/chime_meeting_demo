import '../entities/meeting_bootstrap.dart';
import '../entities/meeting_id.dart';
import '../entities/meeting_result.dart';
import '../gateways/meeting_media_gateway.dart';
import '../repositories/meeting_repository.dart';

/// Application boundary for creating a meeting and its agent attendee.
final class CreateMeeting {
  const CreateMeeting(this._repository, this._mediaGateway);

  final MeetingRepository _repository;
  final MeetingMediaGateway _mediaGateway;

  /// Creates backend credentials and immediately passes them to media.
  ///
  /// Only the non-sensitive meeting ID leaves this use case. A successful
  /// result means native startup was accepted; the media event stream remains
  /// the authority for the connected state.
  Future<MeetingResult<MeetingId>> call() async {
    final repositoryResult = await _repository.createMeeting();
    return switch (repositoryResult) {
      MeetingSuccess(:final value) => _startMedia(value),
      MeetingError(:final failure) => MeetingError<MeetingId>(failure),
    };
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
