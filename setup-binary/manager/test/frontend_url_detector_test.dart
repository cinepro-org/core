import 'package:flutter_test/flutter_test.dart';

import 'package:cinepro_manager/src/services/frontend_url_detector.dart';

void main() {
  const detector = FrontendUrlDetector();

  test('extracts the vite local url from process output', () {
    final url = detector.fromProcessLine(
      line: '\x1B[32m➜\x1B[0m  Local:   http://localhost:5174/',
      coreUrl: 'http://localhost:3000',
      expectedPort: 5174,
    );

    expect(url, 'http://localhost:5174');
  });

  test('normalizes wildcard hosts to localhost', () {
    final url = detector.fromProcessLine(
      line: 'server listening at http://0.0.0.0:5190/',
      coreUrl: 'http://localhost:3000',
      expectedPort: 5190,
    );

    expect(url, 'http://localhost:5190');
  });

  test('ignores backend env urls from frontend output', () {
    final url = detector.fromProcessLine(
      line: 'CORE_URL=http://localhost:3000',
      coreUrl: 'http://localhost:3000',
      expectedPort: 5173,
    );

    expect(url, isNull);
  });

  test('prefers the expected local frontend origin over network urls', () {
    final url = detector.fromProcessLine(
      line: 'Local: http://127.0.0.1:5178/ Network: http://192.168.1.20:5178/',
      coreUrl: 'http://localhost:3000',
      expectedPort: 5178,
    );

    expect(url, 'http://localhost:5178');
  });
}
