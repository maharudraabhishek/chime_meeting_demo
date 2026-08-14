/// Data-layer representation of the documented meeting bootstrap response.
///
/// DTOs validate only fields consumed by the application. They intentionally
/// omit unused capability and ARN fields and never cross into domain or UI.
final class MeetingBootstrapDto {
  const MeetingBootstrapDto({required this.meeting, required this.attendee});

  /// Parses the `data` object from a successful Hipster response envelope.
  factory MeetingBootstrapDto.fromJson(
    Map<String, Object?> json, {
    required bool requireMediaPlacement,
  }) {
    return MeetingBootstrapDto(
      meeting: MeetingDto.fromJson(
        _requiredObject(json, 'meeting'),
        requireMediaPlacement: requireMediaPlacement,
      ),
      attendee: AttendeeCredentialsDto.fromJson(
        _requiredObject(json, 'attendee'),
      ),
    );
  }

  final MeetingDto meeting;
  final AttendeeCredentialsDto attendee;
}

/// Meeting fields required by the domain and Chime media gateway.
final class MeetingDto {
  const MeetingDto({
    required this.meetingId,
    this.externalMeetingId,
    this.mediaRegion,
    this.mediaPlacement,
  });

  /// Parses meeting identity and optional Chime media placement.
  factory MeetingDto.fromJson(
    Map<String, Object?> json, {
    required bool requireMediaPlacement,
  }) {
    final placementJson = _optionalObject(json, 'MediaPlacement');
    if (requireMediaPlacement && placementJson == null) {
      throw const FormatException('Missing MediaPlacement.');
    }

    return MeetingDto(
      meetingId: _requiredString(json, 'MeetingId'),
      externalMeetingId: _optionalString(json, 'ExternalMeetingId'),
      mediaRegion: _optionalString(json, 'MediaRegion'),
      mediaPlacement: placementJson == null
          ? null
          : MeetingMediaPlacementDto.fromJson(placementJson),
    );
  }

  final String meetingId;
  final String? externalMeetingId;
  final String? mediaRegion;
  final MeetingMediaPlacementDto? mediaPlacement;
}

/// Media-placement fields consumed by the Android Amazon Chime session.
final class MeetingMediaPlacementDto {
  const MeetingMediaPlacementDto({
    required this.audioHostUrl,
    required this.audioFallbackUrl,
    required this.signalingUrl,
    required this.turnControlUrl,
    this.eventIngestionUrl,
  });

  /// Parses only the meeting URLs consumed by the Chime media layer.
  ///
  /// Screen-sharing URLs returned by Hipster are intentionally ignored because
  /// this app does not implement content sharing. Event ingestion is optional in
  /// the Amazon Chime Android session configuration.
  factory MeetingMediaPlacementDto.fromJson(Map<String, Object?> json) {
    return MeetingMediaPlacementDto(
      audioHostUrl: _requiredString(json, 'AudioHostUrl'),
      audioFallbackUrl: _requiredString(json, 'AudioFallbackUrl'),
      signalingUrl: _requiredString(json, 'SignalingUrl'),
      turnControlUrl: _requiredString(json, 'TurnControlUrl'),
      eventIngestionUrl: _optionalString(json, 'EventIngestionUrl'),
    );
  }

  final String audioHostUrl;
  final String audioFallbackUrl;
  final String signalingUrl;
  final String turnControlUrl;
  final String? eventIngestionUrl;
}

/// Attendee fields required to construct the native Chime session.
final class AttendeeCredentialsDto {
  const AttendeeCredentialsDto({
    required this.externalUserId,
    required this.attendeeId,
    required this.joinToken,
  });

  /// Requires all credential fields while ignoring unused capability metadata.
  factory AttendeeCredentialsDto.fromJson(Map<String, Object?> json) {
    return AttendeeCredentialsDto(
      externalUserId: _requiredString(json, 'ExternalUserId'),
      attendeeId: _requiredString(json, 'AttendeeId'),
      joinToken: _requiredString(json, 'JoinToken'),
    );
  }

  final String externalUserId;
  final String attendeeId;
  final String joinToken;
}

/// Reads a required nested JSON object and normalizes its map type.
Map<String, Object?> _requiredObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map) {
    throw FormatException('Missing or invalid $key.');
  }
  return Map<String, Object?>.from(value);
}

/// Reads an optional nested JSON object while rejecting invalid wire types.
Map<String, Object?>? _optionalObject(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw FormatException('Invalid $key.');
  }
  return Map<String, Object?>.from(value);
}

/// Reads a required non-empty string from a documented JSON field.
String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid $key.');
  }
  return value;
}

/// Reads an optional non-empty string from a documented JSON field.
String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key.');
  }
  return value;
}
