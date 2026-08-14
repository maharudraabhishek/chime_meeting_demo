import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../error/app_exception.dart';

/// Minimal JSON transport contract consumed by REST data sources.
///
/// Keeping this boundary small makes request construction and transport
/// failures independently testable without exposing `package:http` outside the
/// networking layer.
abstract interface class JsonApiClient {
  /// Sends a POST request and returns a decoded JSON object.
  ///
  /// Implementations throw only typed [AppException] instances. Response
  /// bodies are never logged because meeting responses contain join tokens.
  Future<Map<String, Object?>> post(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    Map<String, Object?> body = const <String, Object?>{},
  });
}

/// `package:http` implementation with centralized URL, header, and timeout
/// behavior for the public meeting gateway.
final class HttpJsonApiClient implements JsonApiClient {
  HttpJsonApiClient({required http.Client client, required AppConfig config})
    : _client = client,
      _config = config;

  final http.Client _client;
  final AppConfig _config;

  /// Builds a Worker/BFF request, applies the deadline, and decodes JSON.
  ///
  /// Raw response content is intentionally discarded on failures so attendee
  /// credentials cannot escape through exception text or diagnostic output.
  @override
  Future<Map<String, Object?>> post(
    String path, {
    Map<String, String> queryParameters = const <String, String>{},
    Map<String, Object?> body = const <String, Object?>{},
  }) async {
    try {
      final uri = _buildUri(path, queryParameters);
      final response = await _client
          .post(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: body.isEmpty ? null : jsonEncode(body),
          )
          .timeout(_config.requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final errorCode = _readSanitizedErrorCode(response.bodyBytes);
        final resultCategory = response.headers['x-gateway-result-category'];
        final requestId = response.headers['x-request-id'];
        if (kDebugMode) {
          debugPrint(
            '[MeetingGateway] status=${response.statusCode} '
            'errorCode=${errorCode ?? 'absent'} '
            'resultCategory=${resultCategory ?? 'absent'} '
            'requestId=${requestId ?? 'absent'}',
          );
        }
        throw ApiException(
          statusCode: response.statusCode,
          errorCode: errorCode,
          resultCategory: resultCategory,
          requestId: requestId,
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const InvalidResponseException();
      }
      return Map<String, Object?>.from(decoded);
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    } on FormatException {
      throw const InvalidResponseException();
    } catch (_) {
      // Keep unclassified implementation errors behind the typed boundary.
      throw const UnexpectedInfrastructureException();
    }
  }

  String? _readSanitizedErrorCode(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final error = decoded['error'];
      if (error is! Map<String, dynamic>) return null;
      final code = error['code'];
      return code is String && code.isNotEmpty ? code : null;
    } on FormatException {
      return null;
    }
  }

  /// Defensively validates configuration and resolves one gateway request URI.
  Uri _buildUri(String path, Map<String, String> queryParameters) {
    final baseUri = Uri.tryParse(_config.apiBaseUrl);
    if (baseUri == null ||
        !baseUri.hasScheme ||
        baseUri.host.isEmpty ||
        baseUri.scheme != 'https') {
      throw const AppConfigurationException();
    }

    final resolved = baseUri.resolve(path);
    if (queryParameters.isEmpty) {
      return resolved;
    }
    return resolved.replace(queryParameters: queryParameters);
  }
}
