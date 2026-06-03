import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/install_state.dart';

/// stores the current install transaction state
class StateStore {
  StateStore(this.path);

  final String path;

  /// loads the last operation state from disk
  Future<InstallState> load() async {
    final file = File(path);
    if (!await file.exists()) return InstallState.idle();
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return InstallState.fromJson(json);
    } on Object {
      return InstallState.idle();
    }
  }

  /// writes state through a temporary file before replacing the old one
  Future<void> save(InstallState state) async {
    await Directory(p.dirname(path)).create(recursive: true);
    final tempPath = '$path.tmp';
    final temp = File(tempPath);
    await temp.writeAsString(state.encode(), flush: true);
    final target = File(path);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(path);
  }

  /// clears the saved state after completed work is stable
  Future<void> clear() async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
