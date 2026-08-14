import '../../domain/entities/attendee_credentials.dart';
import '../../domain/entities/meeting.dart';
import '../../domain/entities/meeting_bootstrap.dart';
import '../../domain/entities/meeting_id.dart';
import '../dto/meeting_bootstrap_dto.dart';

/// Converts validated REST DTOs into networking-agnostic domain entities.
extension MeetingBootstrapDtoMapper on MeetingBootstrapDto {
  /// Creates domain-owned values so DTOs cannot leak above the data boundary.
  MeetingBootstrap toDomain() {
    return MeetingBootstrap(
      meeting: Meeting(
        id: MeetingId(meeting.meetingId),
        externalMeetingId: meeting.externalMeetingId,
        mediaRegion: meeting.mediaRegion,
        mediaPlacement: meeting.mediaPlacement?.toDomain(),
      ),
      attendee: AttendeeCredentials(
        externalUserId: attendee.externalUserId,
        attendeeId: attendee.attendeeId,
        joinToken: attendee.joinToken,
      ),
    );
  }
}

/// Maps the data-layer media URL subset into its domain representation.
extension on MeetingMediaPlacementDto {
  /// Creates an SDK-agnostic media-placement entity.
  MeetingMediaPlacement toDomain() {
    return MeetingMediaPlacement(
      audioHostUrl: audioHostUrl,
      audioFallbackUrl: audioFallbackUrl,
      signalingUrl: signalingUrl,
      turnControlUrl: turnControlUrl,
      eventIngestionUrl: eventIngestionUrl,
    );
  }
}
