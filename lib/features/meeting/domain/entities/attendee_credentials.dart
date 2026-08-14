import 'package:equatable/equatable.dart';

/// Credentials issued by Hipster for one meeting attendee.
///
/// This entity must remain in memory only and must never be logged or exposed
/// in presentation state. The use cases pass it directly to the media gateway.
final class AttendeeCredentials extends Equatable {
  const AttendeeCredentials({
    required this.externalUserId,
    required this.attendeeId,
    required this.joinToken,
  });

  final String externalUserId;
  final String attendeeId;
  final String joinToken;

  @override
  List<Object> get props => <Object>[externalUserId, attendeeId, joinToken];

  /// Prevents credentials or bootstrap payloads from appearing in Equatable output.
  @override
  bool get stringify => false;
}
