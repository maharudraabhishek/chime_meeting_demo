import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser bridge contains no upstream control-plane credentials', () {
    final files = Directory('web/chime_bridge')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              !file.path.contains(
                '${Platform.pathSeparator}node_modules${Platform.pathSeparator}',
              ) &&
              !file.path.contains(
                '${Platform.pathSeparator}.test-dist${Platform.pathSeparator}',
              ) &&
              (file.path.endsWith('.ts') ||
                  file.path.endsWith('.mjs') ||
                  file.path.endsWith('.js') ||
                  file.path.endsWith('.json')),
        );

    const forbidden = <String>[
      'assess.hipster-dev.com',
      'x-api-key',
      'HIPSTER_API_KEY',
      'localStorage',
      'sessionStorage',
    ];

    for (final file in files) {
      final contents = file.readAsStringSync();
      for (final value in forbidden) {
        expect(
          contents,
          isNot(contains(value)),
          reason: '${file.path} must not contain $value',
        );
      }
    }
  });

  test('web shell loads only the local Chime bridge bundle', () {
    final index = File('web/index.html').readAsStringSync();

    expect(index, contains('src="chime_bridge/dist/chime_web_bridge.js"'));
    expect(index, isNot(contains('src="http://')));
    expect(index, isNot(contains('src="https://')));
  });
}
