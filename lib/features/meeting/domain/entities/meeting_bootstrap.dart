import 'package:equatable/equatable.dart';

import 'attendee_credentials.dart';
import 'meeting.dart';

/// Complete backend result needed to bootstrap one attendee's media session.
///
/// Presentation receives only the meeting ID; credential ownership remains
/// below the UI boundary to reduce accidental disclosure.
final class MeetingBootstrap extends Equatable {
  const MeetingBootstrap({required this.meeting, required this.attendee});

  final Meeting meeting;
  final AttendeeCredentials attendee;

  @override
  List<Object> get props => <Object>[meeting, attendee];

  /// Prevents credentials or bootstrap payloads from appearing in Equatable output.
  @override
  bool get stringify => false;
}
