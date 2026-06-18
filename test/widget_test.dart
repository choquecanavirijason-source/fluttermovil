import 'package:flutter_test/flutter_test.dart';

import 'package:test_face/core/config/env.dart';

void main() {
  test('Env.mediaUrl construye URLs absolutas', () {
    expect(Env.mediaUrl(null), isNull);
    expect(Env.mediaUrl('/media/x.png'), '${Env.host}/media/x.png');
    expect(Env.mediaUrl('https://cdn/x.png'), 'https://cdn/x.png');
  });
}
