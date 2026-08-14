import 'package:equatable/equatable.dart';

import 'meeting_failure.dart';

/// Typed outcome used across meeting domain contracts.
sealed class MeetingResult<T> extends Equatable {
  const MeetingResult();

  /// Prevents credentials or bootstrap payloads from appearing in Equatable output.
  @override
  bool get stringify => false;
}

/// Successful meeting operation carrying its domain value.
final class MeetingSuccess<T> extends MeetingResult<T> {
  const MeetingSuccess(this.value);

  final T value;

  @override
  List<Object?> get props => <Object?>[value];
}

/// Failed meeting operation carrying a safe, typed failure.
final class MeetingError<T> extends MeetingResult<T> {
  const MeetingError(this.failure);

  final MeetingFailure failure;

  @override
  List<Object> get props => <Object>[failure];
}
