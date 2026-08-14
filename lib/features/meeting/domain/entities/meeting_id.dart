import 'package:equatable/equatable.dart';

/// Non-empty identifier returned by Hipster and reused verbatim when joining.
final class MeetingId extends Equatable {
  const MeetingId._(this.value);

  /// Validates an API-issued identifier while preserving its exact value.
  factory MeetingId(String value) {
    if (value.trim().isEmpty) {
      throw const FormatException('Meeting ID must not be empty.');
    }
    return MeetingId._(value);
  }

  /// Removes accidental surrounding input whitespace before validation.
  factory MeetingId.fromUserInput(String value) {
    return MeetingId(value.trim());
  }

  final String value;

  @override
  List<Object> get props => <Object>[value];
}
