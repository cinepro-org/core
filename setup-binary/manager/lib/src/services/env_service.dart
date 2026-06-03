import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/env_entry.dart';

/// reads, writes, and validates core env values
class EnvService {
  const EnvService();

  static const requiredKeys = {'TMDB_API_KEY'};

  /// @param install current path active core folder containing env and env example
  ///
  /// reads env values from the install folder and falls back when env example is missing
  Future<List<EnvEntry>> load(String installCurrentPath) async {
    final examplePath = p.join(installCurrentPath, '.env.example');
    final envPath = p.join(installCurrentPath, '.env');
    final example = File(examplePath);
    final env = File(envPath);

    final existing = await env.exists()
        ? _parseValues(await env.readAsLines())
        : <String, String>{};
    if (!await example.exists()) {
      return _fallbackEntries(existing);
    }

    final entries = <EnvEntry>[];
    for (final line in await example.readAsLines()) {
      final parsed = _parseExampleLine(line);
      if (parsed == null) continue;
      final value = existing[parsed.key] ?? parsed.value;
      entries.add(parsed.copyWith(value: value));
    }
    return entries;
  }

  /// @param install current path active core folder where env should be written
  /// @param entries env rows currently visible in the manager editor
  ///
  /// writes env values to the install folder with simple quoting for spaces and hashes
  Future<void> save(String installCurrentPath, List<EnvEntry> entries) async {
    final envPath = p.join(installCurrentPath, '.env');
    final lines = entries
        .map((entry) => '${entry.key}=${_formatValue(entry.value)}')
        .join('\n');
    await File(envPath).writeAsString('$lines\n', flush: true);
  }

  /// @param entries env rows loaded from the active install folder
  ///
  /// checks required env values before starting core
  EnvValidationResult validate(List<EnvEntry> entries) {
    final missing = <String>[];
    for (final key in requiredKeys) {
      final entry = entries.where((item) => item.key == key).firstOrNull;
      if (entry == null ||
          entry.value.trim().isEmpty ||
          entry.value.contains('your_')) {
        missing.add(key);
      }
    }
    return EnvValidationResult(
      valid: missing.isEmpty,
      missingRequiredKeys: missing,
    );
  }

  EnvEntry? _parseExampleLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    final optional = trimmed.startsWith('#');
    final body = optional ? trimmed.substring(1).trimLeft() : trimmed;
    final match = RegExp(
      r'^([A-Z0-9_]+)\s*=\s*([^#]*)(?:#\s*(.*))?$',
    ).firstMatch(body);
    if (match == null) return null;
    final key = match.group(1)!;
    final value = _cleanValue(match.group(2) ?? '');
    final description = match.group(3)?.trim() ?? _descriptionFor(key);
    return EnvEntry(
      key: key,
      value: optional ? '' : value,
      description: description,
      required: requiredKeys.contains(key),
      secret: key.contains('KEY') ||
          key.contains('PASSWORD') ||
          key.contains('SECRET'),
    );
  }

  Map<String, String> _parseValues(List<String> lines) {
    final values = <String, String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final index = trimmed.indexOf('=');
      if (index <= 0) continue;
      final key = trimmed.substring(0, index).trim();
      final value = _cleanValue(trimmed.substring(index + 1));
      values[key] = value;
    }
    return values;
  }

  List<EnvEntry> _fallbackEntries(Map<String, String> existing) {
    final keys = {
      'PORT',
      'HOST',
      'NODE_ENV',
      'TMDB_API_KEY',
      'TMDB_CACHE_TTL',
      'CACHE_TYPE',
      'REDIS_HOST',
      'REDIS_PORT',
      'REDIS_PASSWORD',
    };
    return keys.map((key) {
      return EnvEntry(
        key: key,
        value: existing[key] ?? '',
        description: _descriptionFor(key),
        required: requiredKeys.contains(key),
        secret: key.contains('KEY') || key.contains('PASSWORD'),
      );
    }).toList();
  }

  String _cleanValue(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  String _formatValue(String value) {
    if (value.contains(' ') || value.contains('#')) {
      return '"${value.replaceAll('"', r'\"')}"';
    }
    return value;
  }

  String _descriptionFor(String key) {
    return switch (key) {
      'TMDB_API_KEY' => 'required key used to fetch movie metadata',
      'CACHE_TYPE' => 'memory is simple, redis is faster when configured',
      'REDIS_HOST' => 'redis host used when redis cache is enabled',
      'REDIS_PORT' => 'redis port used when redis cache is enabled',
      'STREMIO_ADDON' => 'enables the stremio addon route',
      'MCP_ENABLED' => 'enables mcp support for local agents',
      'PUBLIC_URL' => 'public base url when core is exposed through a domain',
      _ => 'cinepro core setting',
    };
  }
}
