import 'package:chime_meeting/core/config/app_config.dart';
import 'package:chime_meeting/core/error/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('rejects a blank gateway URL', () {
      expect(
        () => AppConfig(apiBaseUrl: '   '),
        throwsA(isA<AppConfigurationException>()),
      );
    });

    test('rejects relative, hostless, and cleartext URLs', () {
      for (final value in <String>[
        'meetings',
        'https:///meetings',
        'http://example.test/',
      ]) {
        expect(
          () => AppConfig(apiBaseUrl: value),
          throwsA(isA<AppConfigurationException>()),
        );
      }
    });

    test('normalizes a valid HTTPS gateway URL with a trailing slash', () {
      final config = AppConfig(
        apiBaseUrl: '  https://gateway.example.test/base  ',
      );

      expect(config.apiBaseUrl, 'https://gateway.example.test/base/');
      expect(config.requestTimeout, const Duration(seconds: 15));
    });

    test('fromEnvironment uses the current HTTPS test gateway', () {
      final config = AppConfig.fromEnvironment();

      expect(Uri.parse(config.apiBaseUrl).scheme, 'https');
      expect(
        config.apiBaseUrl,
        'https://hipster-meeting-gateway.abhishek-kumar-developer09.workers.dev/',
      );
    });
  });
}
