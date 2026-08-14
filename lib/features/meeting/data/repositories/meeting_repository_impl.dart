import '../../../../core/error/app_exception.dart';
import '../../domain/entities/meeting_bootstrap.dart';
import '../../domain/entities/meeting_failure.dart';
import '../../domain/entities/meeting_id.dart';
import '../../domain/entities/meeting_result.dart';
import '../../domain/repositories/meeting_repository.dart';
import '../datasources/meeting_api_data_source.dart';
import '../dto/meeting_bootstrap_dto.dart';
import '../mappers/meeting_bootstrap_mapper.dart';

/// Maps Hipster DTOs and infrastructure exceptions into the meeting domain.
final class MeetingRepositoryImpl implements MeetingRepository {
  const MeetingRepositoryImpl(this._dataSource);

  final MeetingApiDataSource _dataSource;

  /// Maps a successful create DTO or a typed infrastructure failure.
  @override
  Future<MeetingResult<MeetingBootstrap>> createMeeting() {
    return _execute(_dataSource.createMeeting, isJoinRequest: false);
  }

  /// Preserves the exact ID while classifying client rejections as invalid joins.
  @override
  Future<MeetingResult<MeetingBootstrap>> joinMeeting(MeetingId meetingId) {
    return _execute(
      () => _dataSource.joinMeeting(meetingId.value),
      isJoinRequest: true,
    );
  }

  /// Executes one REST operation and maps infrastructure failures to domain failures.
  Future<MeetingResult<MeetingBootstrap>> _execute(
    Future<MeetingBootstrapDto> Function() request, {
    required bool isJoinRequest,
  }) async {
    try {
      final dto = await request();
      return MeetingSuccess<MeetingBootstrap>(dto.toDomain());
    } on NetworkException {
      return const MeetingError<MeetingBootstrap>(
        MeetingFailure(MeetingFailureType.network),
      );
    } on RequestTimeoutException {
      return const MeetingError<MeetingBootstrap>(
        MeetingFailure(MeetingFailureType.timeout),
      );
    } on AppConfigurationException {
      return const MeetingError<MeetingBootstrap>(
        MeetingFailure(MeetingFailureType.configuration),
      );
    } on InvalidResponseException {
      return const MeetingError<MeetingBootstrap>(
        MeetingFailure(MeetingFailureType.invalidResponse),
      );
    } on ApiException catch (error) {
      // Map well-known HTTP status codes into stable domain failure categories.
      // 408 represents a client/request timeout. The Worker uses 504 when its
      // shorter upstream Hipster deadline expires, before Flutter's outer
      // transport deadline.
      final status = error.statusCode;
      final type = status == 408 || status == 504
          ? MeetingFailureType.timeout
          : (status == 401 || status == 403)
          ? MeetingFailureType.unauthorized
          : (status == 429)
          ? MeetingFailureType.rateLimited
          : (isJoinRequest && status >= 400 && status < 500)
          ? MeetingFailureType.invalidMeeting
          : MeetingFailureType.server;
      return MeetingError<MeetingBootstrap>(MeetingFailure(type));
    } catch (_) {
      return const MeetingError<MeetingBootstrap>(
        MeetingFailure(MeetingFailureType.unexpected),
      );
    }
  }
}
