import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// describes the marker for a manager owned install folder
class InstallMarkerSnapshot {
  /// @param tag installed core release tag recorded by the manager
  /// @param commit installed core commit recorded by the manager
  /// @param ui commit installed ui commit when the ui archive was installed
  /// @param ui sha256 recorded ui archive sha256 for diagnostics
  ///
  /// creates a marker snapshot read from cinepro managed install json
  const InstallMarkerSnapshot({
    required this.tag,
    required this.commit,
    this.uiCommit,
    this.uiSha256,
  });

  final String tag;
  final String commit;
  final String? uiCommit;
  final String? uiSha256;
}

/// writes and checks the managed install marker
class InstallMarker {
  const InstallMarker();

  static const fileName = 'cinepro-managed-install.json';

  /// @param install root managed content folder that receives the marker
  /// @param tag installed core release tag
  /// @param commit installed core commit
  /// @param ui commit installed ui commit when available
  /// @param ui sha256 recorded ui archive sha256 when available
  ///
  /// writes the marker that allows managed uninstall and path validation
  Future<void> write({
    required String installRoot,
    required String tag,
    required String commit,
    String? uiCommit,
    String? uiSha256,
  }) async {
    final file = File(p.join(installRoot, fileName));
    final json = const JsonEncoder.withIndent('  ').convert({
      'managedBy': 'cinepro-manager',
      'tag': tag,
      'commit': commit,
      'uiCommit': uiCommit,
      'uiSha256': uiSha256,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await file.writeAsString(json, flush: true);
  }

  /// @param install root managed content folder that may contain the marker
  ///
  /// reads the marker if it belongs to this manager
  Future<InstallMarkerSnapshot?> read(String installRoot) async {
    final file = File(p.join(installRoot, fileName));
    if (!await file.exists()) return null;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      if (json['managedBy'] != 'cinepro-manager') return null;
      return InstallMarkerSnapshot(
        tag: json['tag'] as String? ?? '',
        commit: json['commit'] as String? ?? '',
        uiCommit: json['uiCommit'] as String?,
        uiSha256: json['uiSha256'] as String?,
      );
    } on Object {
      return null;
    }
  }

  /// @param install root managed content folder checked before destructive cleanup
  ///
  /// checks that the manager owns this install folder
  Future<bool> exists(String installRoot) async {
    final file = File(p.join(installRoot, fileName));
    if (!await file.exists()) return false;
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return json['managedBy'] == 'cinepro-manager';
    } on Object {
      return false;
    }
  }
}
