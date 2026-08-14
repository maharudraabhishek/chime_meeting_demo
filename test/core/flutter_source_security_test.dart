import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Flutter source contains no upstream credential configuration', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    final credentialHeader = <String>['x', 'api', 'key'].join('-');
    final legacyCredentialName = <String>['HIPSTER', 'API', 'KEY'].join('_');
    final directUpstream = <String>[
      'https://',
      'assess.',
      'hipster-dev.',
      'com/',
      'api/',
    ].join();

    expect(<bool>[
      source.contains(credentialHeader),
      source.contains(legacyCredentialName),
      source.contains(directUpstream),
    ], everyElement(isFalse));
  });
}
