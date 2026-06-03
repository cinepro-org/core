import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// describes one core health check result
class HealthSnapshot {
  const HealthSnapshot({
    required this.ok,
    required this.status,
    required this.details,
  });

  final bool ok;
  final String status;
  final Map<String, Object?> details;
}

/// reads health data from the running core service
class HealthService {
  HealthService(this.httpClient);

  final http.Client httpClient;

  /// reads the core health contract when it exists
  Future<HealthSnapshot> check({
    required String host,
    required int port,
  }) async {
    final uri = Uri.parse('http://$host:$port/health');
    try {
      final response =
          await httpClient.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return HealthSnapshot(
          ok: false,
          status: 'http ${response.statusCode}',
          details: const {},
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, Object?>) {
        final status = (decoded['status'] as String?) ?? 'healthy';
        return HealthSnapshot(
          ok: status == 'healthy',
          status: status,
          details: decoded,
        );
      }
      return const HealthSnapshot(ok: true, status: 'reachable', details: {});
    } on SocketException {
      return const HealthSnapshot(
        ok: false,
        status: 'not reachable',
        details: {},
      );
    } on Object {
      return const HealthSnapshot(
        ok: false,
        status: 'health check failed',
        details: {},
      );
    }
  }
}
