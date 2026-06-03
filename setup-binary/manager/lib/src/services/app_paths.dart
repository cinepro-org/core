import 'dart:io';

import 'package:path/path.dart' as p;

/// resolves the manager install folder, data folder, logs, cache, and content root
class AppPaths {
  /// @param app install dir folder where setup installed the manager exe
  /// @param data root local app data folder for state, logs, cache, and downloads
  /// @param state file durable install transaction state path
  /// @param log file manager log file path
  /// @param cache dir cache folder reserved for future manager data
  /// @param download dir manager download folder
  /// @param default install root default cinepro content folder
  ///
  /// creates resolved paths used by the manager and dashboard
  const AppPaths({
    required this.appInstallDir,
    required this.dataRoot,
    required this.stateFile,
    required this.logFile,
    required this.cacheDir,
    required this.downloadDir,
    required this.defaultInstallRoot,
  });

  final String appInstallDir;
  final String dataRoot;
  final String stateFile;
  final String logFile;
  final String cacheDir;
  final String downloadDir;
  final String defaultInstallRoot;

  /// resolves the windows app data paths used by the manager
  static Future<AppPaths> resolve() async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final userProfile = Platform.environment['USERPROFILE'];
    final root = localAppData ??
        (userProfile == null
            ? p.join(Directory.current.path, '.cinepro-manager')
            : p.join(userProfile, 'AppData', 'Local'));
    final dataRoot = p.join(root, 'CinePro Manager');
    final paths = AppPaths(
      appInstallDir: p.dirname(Platform.resolvedExecutable),
      dataRoot: dataRoot,
      stateFile: p.join(dataRoot, 'state.json'),
      logFile: p.join(dataRoot, 'logs', 'manager.log'),
      cacheDir: p.join(dataRoot, 'cache'),
      downloadDir: p.join(dataRoot, 'downloads'),
      defaultInstallRoot: p.join(root, 'CinePro'),
    );
    await paths.ensureCreated();
    return paths;
  }

  /// creates the directories needed before services start or logs are written
  Future<void> ensureCreated() async {
    await Directory(dataRoot).create(recursive: true);
    await Directory(p.dirname(logFile)).create(recursive: true);
    await Directory(cacheDir).create(recursive: true);
    await Directory(downloadDir).create(recursive: true);
    await Directory(defaultInstallRoot).create(recursive: true);
  }
}
