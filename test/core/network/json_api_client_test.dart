import 'package:chime_meeting/core/config/app_config.dart';
import 'package:chime_meeting/core/error/app_exception.dart';
import 'package:chime_meeting/core/network/json_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('HttpJsonApiClient', () {
    test(
      'resolves the gateway URL and sends only required JSON headers',
      () async {
        late http.Request capturedRequest;
        final client = HttpJsonApiClient(
          client: MockClient((request) async {
            capturedRequest = request;
            return http.Response('{"status":"success"}', 200);
          }),
          config: AppConfig(apiBaseUrl: 'https://example.test/api/'),
        );

        final response = await client.post(
          'meetings',
          body: const <String, Object?>{'type': 'agent'},
        );

        expect(
          capturedRequest.url,
          Uri.parse('https://example.test/api/meetings'),
        );
        expect(capturedRequest.headers['accept'], 'application/json');
        expect(capturedRequest.headers['content-type'], 'application/json');
        final credentialHeader = <String>['x', 'api', 'key'].join('-');
        expect(capturedRequest.headers, isNot(contains(credentialHeader)));
        expect(capturedRequest.body, '{"type":"agent"}');
        expect(response['status'], 'success');
      },
    );

    test('maps malformed JSON to a typed invalid response exception', () async {
      final client = HttpJsonApiClient(
        client: MockClient((request) async => http.Response('not-json', 200)),
        config: AppConfig(apiBaseUrl: 'https://example.test/api/'),
      );

      await expectLater(
        client.post('meetings'),
        throwsA(isA<InvalidResponseException>()),
      );
    });

    test('maps a non-success status without exposing its body', () async {
      final client = HttpJsonApiClient(
        client: MockClient(
          (request) async => http.Response('sensitive upstream body', 503),
        ),
        config: AppConfig(apiBaseUrl: 'https://example.test/api/'),
      );

      await expectLater(
        client.post('meetings'),
        throwsA(
          isA<ApiException>().having(
            (exception) => exception.statusCode,
            'statusCode',
            503,
          ),
        ),
      );
    });

    test('captures only sanitized Worker diagnostics on failure', () async {
      final client = HttpJsonApiClient(
        client: MockClient(
          (request) async => http.Response(
            '{"status":"error","error":{"code":"UPSTREAM_UNAVAILABLE"}}',
            502,
            headers: <String, String>{
              'x-gateway-result-category': 'upstream_tls_error',
              'x-request-id': 'safe-request-id',
            },
          ),
        ),
        config: AppConfig(apiBaseUrl: 'https://example.test/api/'),
      );

      await expectLater(
        client.post('meetings'),
        throwsA(
          isA<ApiException>()
              .having((exception) => exception.statusCode, 'statusCode', 502)
              .having(
                (exception) => exception.errorCode,
                'errorCode',
                'UPSTREAM_UNAVAILABLE',
              )
              .having(
                (exception) => exception.resultCategory,
                'resultCategory',
                'upstream_tls_error',
              )
              .having(
                (exception) => exception.requestId,
                'requestId',
                'safe-request-id',
              ),
        ),
      );
    });
  });
}
