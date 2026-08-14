import '../../../../core/error/app_exception.dart';
import '../../../../core/network/json_api_client.dart';
import '../dto/meeting_bootstrap_dto.dart';

/// REST boundary that owns meeting-gateway mechanics and response decoding.
abstract interface class MeetingApiDataSource {
  /// Creates an agent meeting using the adapter's isolated wire contract.
  Future<MeetingBootstrapDto> createMeeting();

  /// Creates a client attendee for the exact backend-issued [meetingId].
  Future<MeetingBootstrapDto> joinMeeting(String meetingId);
}

/// Meeting gateway implementation using Hipster's documented JSON contract.
final class HipsterMeetingApiDataSource implements MeetingApiDataSource {
  const HipsterMeetingApiDataSource(this._client);

  final JsonApiClient _client;

  /// Uses the documented JSON body contract for agent creation and requires
  /// create-only media placement fields.
  @override
  Future<MeetingBootstrapDto> createMeeting() async {
    final response = await _client.post(
      'meetings',
      body: const <String, Object?>{'type': 'agent'},
    );
    return _parseResponse(response, requireMediaPlacement: true);
  }

  /// Uses the documented JSON body contract for client join requests and accepts
  /// the smaller documented join response.
  @override
  Future<MeetingBootstrapDto> joinMeeting(String meetingId) async {
    final response = await _client.post(
      'meetings',
      body: <String, Object?>{'type': 'client', 'meeting_id': meetingId},
    );
    return _parseResponse(response, requireMediaPlacement: false);
  }

  /// Validates the Hipster success envelope before DTO construction.
  MeetingBootstrapDto _parseResponse(
    Map<String, Object?> response, {
    required bool requireMediaPlacement,
  }) {
    try {
      final status = response['status'];
      if (status is! String) {
        throw const FormatException('Missing status.');
      }
      if (status != 'success') {
        // Hipster may communicate an application error inside an HTTP 2xx
        // envelope. Treat it like a client/API rejection without retaining the
        // server message, which is not a stable domain contract.
        throw const ApiException(statusCode: 422);
      }

      final data = response['data'];
      if (data is! Map) {
        throw const FormatException('Missing data.');
      }
      return MeetingBootstrapDto.fromJson(
        Map<String, Object?>.from(data),
        requireMediaPlacement: requireMediaPlacement,
      );
    } on AppException {
      rethrow;
    } on FormatException {
      throw const InvalidResponseException();
    } catch (_) {
      throw const InvalidResponseException();
    }
  }
}
