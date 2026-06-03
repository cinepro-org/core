import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// stores manager logs and streams new log lines to the ui
class LogService {
  LogService(this.path);

  final String path;
  final _controller = StreamController<String>.broadcast();

  Stream<String> get lines => _controller.stream;

  /// appends one manager log line
  Future<void> write(String message) async {
    final now = DateTime.now().toIso8601String();
    final line = '[$now] $message';
    await Directory(p.dirname(path)).create(recursive: true);
    await File(
      path,
    ).writeAsString('$line\n', mode: FileMode.append, flush: true);
    _controller.add(line);
  }

  /// reads recent log lines for the dashboard
  Future<List<String>> tail({int maxLines = 120}) async {
    final file = File(path);
    if (!await file.exists()) return const [];
    final lines = await file.readAsLines();
    if (lines.length <= maxLines) return lines;
    return lines.sublist(lines.length - maxLines);
  }

  /// clears the log file when the user confirms it
  Future<void> clear() async {
    final file = File(path);
    if (await file.exists()) {
      await file.writeAsString('', flush: true);
    }
    _controller.add('[${DateTime.now().toIso8601String()}] logs cleared');
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
