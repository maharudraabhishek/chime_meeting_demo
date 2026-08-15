import 'package:chime_meeting/core/error/app_exception.dart';

/// Build-time configuration for the public meeting gateway.
///
/// The gateway URL is public configuration, while upstream credentials remain
/// server-side. Domain and presentation code never read environment definitions
/// directly.
final class AppConfig {
  factory AppConfig({
    required String apiBaseUrl,
    Duration requestTimeout = const Duration(seconds: 15),
  }) {
    return AppConfig._(
      apiBaseUrl: _validateAndNormalizeBaseUrl(apiBaseUrl),
      requestTimeout: requestTimeout,
    );
  }

  const AppConfig._({required this.apiBaseUrl, required this.requestTimeout});

  /// Creates the application configuration from Dart environment definitions.
  ///
  /// Raises [AppConfigurationException] when the public gateway URL is invalid.
  factory AppConfig.fromEnvironment() {
    const rawApiBaseUrl = String.fromEnvironment('MEETING_API_BASE_URL');
    return AppConfig(apiBaseUrl: rawApiBaseUrl);
  }

  final String apiBaseUrl;
  final Duration requestTimeout;

  static String _validateAndNormalizeBaseUrl(String rawValue) {
    final trimmedValue = rawValue.trim();
    final uri = Uri.tryParse(trimmedValue);
    if (trimmedValue.isEmpty ||
        uri == null ||
        !uri.isAbsolute ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      throw const AppConfigurationException(
        'MEETING_API_BASE_URL must be an absolute HTTPS URL.',
      );
    }

    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: normalizedPath).toString();
  }

  @override
  String toString() =>
      'AppConfig(apiBaseUrl: $apiBaseUrl, requestTimeout: $requestTimeout)';
}
