import 'package:equatable/equatable.dart';

import 'meeting_id.dart';

/// Backend meeting identity plus optional Chime media placement data.
///
/// Hipster's create response includes media placement, while its documented
/// join response includes only `MeetingId`. The nullable configuration models
/// that asymmetry rather than fabricating missing values.
final class Meeting extends Equatable {
  const Meeting({
    required this.id,
    this.externalMeetingId,
    this.mediaRegion,
    this.mediaPlacement,
  });

  final MeetingId id;
  final String? externalMeetingId;
  final String? mediaRegion;
  final MeetingMediaPlacement? mediaPlacement;

  @override
  List<Object?> get props => <Object?>[
    id,
    externalMeetingId,
    mediaRegion,
    mediaPlacement,
  ];
}

/// Chime meeting endpoints required by the Android media session.
///
/// Values remain opaque strings so the domain stays independent of Amazon
/// Chime SDK types. Content-sharing endpoints are intentionally excluded.
final class MeetingMediaPlacement extends Equatable {
  const MeetingMediaPlacement({
    required this.audioHostUrl,
    required this.audioFallbackUrl,
    required this.signalingUrl,
    required this.turnControlUrl,
    this.eventIngestionUrl,
  });

  final String audioHostUrl;
  final String audioFallbackUrl;
  final String signalingUrl;
  final String turnControlUrl;
  final String? eventIngestionUrl;

  @override
  List<Object?> get props => <Object?>[
    audioHostUrl,
    audioFallbackUrl,
    signalingUrl,
    turnControlUrl,
    eventIngestionUrl,
  ];
}
