import 'dart:async';
import 'dart:io';

/// detects the real frontend url from process output and local port checks
class FrontendUrlDetector {
  const FrontendUrlDetector();

  /// @param port local frontend port selected before the web service starts
  ///
  /// returns the local fallback url used until the process announces its url
  String fallbackUrl(int port) => 'http://localhost:$port';

  /// @param line one stdout or stderr line emitted by the frontend process
  /// @param core url backend origin that must not be mistaken for the ui url
  /// @param expected port port requested by the manager before process start
  ///
  /// extracts the best frontend url from server output when one is present
  String? fromProcessLine({
    required String line,
    required String coreUrl,
    required int expectedPort,
  }) {
    final clean = _stripAnsi(line);
    final lower = clean.toLowerCase();
    if (lower.contains('core_url') ||
        lower.contains('cinepro_core_url') ||
        lower.contains('vite_cinepro_core_url')) {
      return null;
    }

    final core = Uri.tryParse(coreUrl);
    final candidates = <_UrlCandidate>[];
    for (final match in RegExp("https?://[^\\s<>\"']+").allMatches(clean)) {
      final raw = _trimUrl(match.group(0)!);
      final uri = Uri.tryParse(raw);
      if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) continue;
      if (core != null && _sameOrigin(uri, core)) continue;
      var score = 0;
      if (uri.hasPort && uri.port == expectedPort) score += 8;
      if (_isLoopback(uri.host)) score += 5;
      if (lower.contains('local') ||
          lower.contains('network') ||
          lower.contains('ready') ||
          lower.contains('listening') ||
          lower.contains('server')) {
        score += 4;
      }
      if (lower.contains('error')) score -= 3;
      candidates.add(_UrlCandidate(uri: uri, score: score));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((left, right) => right.score.compareTo(left.score));
    return _origin(candidates.first.uri);
  }

  /// @param preferred port first port the manager should try
  /// @param attempts number of sequential ports to inspect
  ///
  /// finds a local port that can be reserved before the frontend starts
  Future<int> findAvailablePort({
    required int preferredPort,
    int attempts = 40,
  }) async {
    for (var offset = 0; offset < attempts; offset++) {
      final port = preferredPort + offset;
      if (port <= 0 || port > 65535) break;
      if (await _canBind(port)) return port;
    }
    throw StateError('no frontend port is available near $preferredPort');
  }

  /// @param port selected local port to probe
  /// @param timeout total time allowed for the server to accept connections
  ///
  /// waits until the local frontend port accepts tcp connections
  Future<bool> waitForLocalPort({
    required int port,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          port,
          timeout: const Duration(milliseconds: 250),
        );
        socket.destroy();
        return true;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
    }
    return false;
  }

  Future<bool> _canBind(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      return true;
    } on Object {
      return false;
    } finally {
      await socket?.close();
    }
  }

  String _stripAnsi(String line) {
    return line.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  }

  String _trimUrl(String value) {
    return value.replaceAll(RegExp(r'[,.;)]+$'), '');
  }

  bool _sameOrigin(Uri left, Uri right) {
    return left.scheme == right.scheme &&
        _normalizedHost(left.host) == _normalizedHost(right.host) &&
        _effectivePort(left) == _effectivePort(right);
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    return uri.scheme == 'https' ? 443 : 80;
  }

  bool _isLoopback(String host) {
    final normalized = _normalizedHost(host);
    return normalized == 'localhost';
  }

  String _normalizedHost(String host) {
    final lower = host.toLowerCase();
    if (lower == 'localhost' ||
        lower == '127.0.0.1' ||
        lower == '::1' ||
        lower == '0.0.0.0' ||
        lower == '::') {
      return 'localhost';
    }
    return lower;
  }

  String _origin(Uri uri) {
    final host = _normalizedHost(uri.host);
    final port = uri.hasPort ? uri.port : null;
    return Uri(scheme: uri.scheme, host: host, port: port).toString();
  }
}

class _UrlCandidate {
  const _UrlCandidate({required this.uri, required this.score});

  final Uri uri;
  final int score;
}
