import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/install_state.dart';
import '../models/release_manifest.dart';
import 'install_marker.dart';
import 'log_service.dart';
import 'release_client.dart';
import 'safe_zip_extractor.dart';
import 'state_store.dart';

/// describes the folder layout for one managed cinepro install
class InstallLayout {
  /// @param root folder chosen by the user for managed core, ui, and runtime files
  ///
  /// stores every derived path used during install, update, rollback, and cleanup
  const InstallLayout(this.root);

  final String root;

  String get current => p.join(root, 'current');
  String get previous => p.join(root, 'previous');
  String get staging => p.join(root, 'staging');
  String get runtime => p.join(root, 'runtime');
  String get frontendCurrent => p.join(root, 'ui', 'current');
  String get frontendPrevious => p.join(root, 'ui', 'previous');
  String get frontendStaging => p.join(root, 'ui', 'staging');
}

/// handles staged installs, safe updates, crash recovery, and managed uninstall cleanup
class InstallManager {
  /// @param state store durable transaction store used for recovery after crashes
  /// @param release client verified download client for core, runtime, and ui archives
  /// @param extractor zip extractor with path traversal and expanded size guards
  /// @param marker install ownership marker used before destructive cleanup
  /// @param log manager log sink used for user visible progress
  ///
  /// creates the install coordinator with all file operations kept behind services
  InstallManager({
    required this.stateStore,
    required this.releaseClient,
    required this.extractor,
    required this.marker,
    required this.log,
  });

  final StateStore stateStore;
  final ReleaseClient releaseClient;
  final SafeZipExtractor extractor;
  final InstallMarker marker;
  final LogService log;

  /// resumes or rolls back unfinished install work after a restart or crash
  Future<InstallState> recover() async {
    final state = await stateStore.load();
    if (!state.hasUnfinishedWork || state.installPath == null) {
      return state;
    }

    await log.write('recovering unfinished ${state.operation.name}');
    final layout = InstallLayout(state.installPath!);
    if (state.phase == InstallPhase.swapping) {
      await _finishOrRollbackSwap(layout);
    } else if (state.phase != InstallPhase.completed) {
      await _cleanStaging(layout);
    }
    final recovered = state.copyWith(
      operation: InstallOperation.completed,
      phase: InstallPhase.completed,
      updatedAt: DateTime.now(),
      message: 'recovery completed',
    );
    await stateStore.save(recovered);
    return recovered;
  }

  /// @param install root managed content folder chosen by the user
  /// @param manifest signed core manifest that already passed ed25519 verification
  /// @param frontend current ui main branch snapshot to install beside core
  /// @param on download progress callback that reports received and expected bytes
  ///
  /// installs or updates core, ui, and runtime through staging before swapping active folders
  Future<void> installOrUpdate({
    required String installRoot,
    required ReleaseManifest manifest,
    required FrontendSnapshot frontend,
    required void Function(int received, int total) onDownloadProgress,
  }) async {
    final layout = InstallLayout(installRoot);
    await Directory(layout.root).create(recursive: true);
    final hasCurrent = await Directory(layout.current).exists();
    final operation =
        hasCurrent ? InstallOperation.updating : InstallOperation.installing;
    await _save(
      InstallState(
        operation: operation,
        phase: InstallPhase.downloading,
        installPath: installRoot,
        targetTag: manifest.tag,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        message: 'downloading cinepro packages',
      ),
    );

    final zipPath = await releaseClient.downloadVerifiedAsset(
      asset: manifest.asset,
      downloadDir: p.join(layout.root, 'downloads'),
      onProgress: onDownloadProgress,
    );

    await _savePhase(
      layout.root,
      operation,
      InstallPhase.verifying,
      manifest.tag,
    );
    await _savePhase(
      layout.root,
      operation,
      InstallPhase.extracting,
      manifest.tag,
    );
    await extractor.extract(zipPath: zipPath, destinationPath: layout.staging);

    await _savePhase(
      layout.root,
      operation,
      InstallPhase.validating,
      manifest.tag,
    );
    final coreRoot = await _findCoreRoot(layout.staging);
    await _validateCoreRoot(coreRoot);
    await _ensureEnv(coreRoot);
    await _savePhase(
      layout.root,
      operation,
      InstallPhase.installingRuntime,
      manifest.tag,
    );
    await _ensureRuntime(
      layout: layout,
      manifest: manifest,
      onDownloadProgress: onDownloadProgress,
    );

    await _savePhase(
      layout.root,
      operation,
      InstallPhase.downloading,
      '${manifest.tag}+ui:${frontend.commit.substring(0, 7)}',
    );
    final frontendArchive = await releaseClient.downloadFrontendArchive(
      snapshot: frontend,
      downloadDir: p.join(layout.root, 'downloads'),
      onProgress: onDownloadProgress,
    );
    await _savePhase(
      layout.root,
      operation,
      InstallPhase.extracting,
      '${manifest.tag}+ui:${frontend.commit.substring(0, 7)}',
    );
    await extractor.extract(
      zipPath: frontendArchive.zipPath,
      destinationPath: layout.frontendStaging,
    );
    await _savePhase(
      layout.root,
      operation,
      InstallPhase.validating,
      '${manifest.tag}+ui:${frontend.commit.substring(0, 7)}',
    );
    final frontendRoot = await _findPackageRoot(
      layout.frontendStaging,
      label: 'cinepro frontend',
    );
    await _validateFrontendRoot(frontendRoot);
    await _ensureEnv(frontendRoot);

    await _savePhase(
      layout.root,
      operation,
      InstallPhase.swapping,
      manifest.tag,
    );
    await _swapIntoCurrent(layout, coreRoot);
    await _swapFrontendIntoCurrent(layout, frontendRoot);
    await marker.write(
      installRoot: layout.root,
      tag: manifest.tag,
      commit: manifest.commit,
      uiCommit: frontendArchive.snapshot.commit,
      uiSha256: frontendArchive.snapshot.downloadedSha256,
    );
    await _cleanStaging(layout);
    await _save(
      InstallState(
        operation: InstallOperation.completed,
        phase: InstallPhase.completed,
        installPath: installRoot,
        currentTag: manifest.tag,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        message: 'cinepro core is ready',
      ),
    );
    await log.write('install completed for ${manifest.tag}');
  }

  /// @param install root managed content folder selected in the manager
  /// @param remove core whether managed core, ui, runtime, and downloads should be removed
  /// @param remove logs whether the manager log file should be removed too
  /// @param log path absolute path to the manager log file
  ///
  /// removes only manager owned files after the user confirms the uninstall prompt
  Future<void> uninstall({
    required String installRoot,
    required bool removeCore,
    required bool removeLogs,
    required String logPath,
  }) async {
    final layout = InstallLayout(installRoot);
    await _save(
      InstallState(
        operation: InstallOperation.uninstalling,
        phase: InstallPhase.cleaning,
        installPath: installRoot,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        message: 'uninstalling managed cinepro files',
      ),
    );

    if (removeCore) {
      final owned = await marker.exists(layout.root);
      if (!owned) {
        throw StateError(
          'this folder is not marked as a cinepro manager install',
        );
      }
      if (await Directory(layout.root).exists()) {
        await Directory(layout.root).delete(recursive: true);
      }
    }

    if (removeLogs) {
      final logFile = File(logPath);
      if (await logFile.exists()) {
        await logFile.delete();
      }
    }

    await _save(
      InstallState(
        operation: InstallOperation.completed,
        phase: InstallPhase.completed,
        updatedAt: DateTime.now(),
        message: 'uninstall completed',
      ),
    );
  }

  Future<void> _save(InstallState state) async {
    await stateStore.save(state);
    if (state.message != null) {
      await log.write(state.message!);
    }
  }

  Future<void> _savePhase(
    String installRoot,
    InstallOperation operation,
    InstallPhase phase,
    String tag,
  ) async {
    await _save(
      InstallState(
        operation: operation,
        phase: phase,
        installPath: installRoot,
        targetTag: tag,
        startedAt: DateTime.now(),
        updatedAt: DateTime.now(),
        message: phase.name,
      ),
    );
  }

  Future<void> _swapIntoCurrent(InstallLayout layout, String coreRoot) async {
    final current = Directory(layout.current);
    final previous = Directory(layout.previous);
    if (await previous.exists()) {
      await previous.delete(recursive: true);
    }
    if (await current.exists()) {
      await current.rename(layout.previous);
    }
    await Directory(coreRoot).rename(layout.current);
  }

  Future<void> _swapFrontendIntoCurrent(
    InstallLayout layout,
    String frontendRoot,
  ) async {
    final current = Directory(layout.frontendCurrent);
    final previous = Directory(layout.frontendPrevious);
    if (await previous.exists()) {
      await previous.delete(recursive: true);
    }
    if (await current.exists()) {
      await current.rename(layout.frontendPrevious);
    }
    await Directory(frontendRoot).rename(layout.frontendCurrent);
  }

  Future<void> _finishOrRollbackSwap(InstallLayout layout) async {
    final current = Directory(layout.current);
    final previous = Directory(layout.previous);
    if (await current.exists()) {
      await _finishOrRollbackFrontendSwap(layout);
      return;
    }
    if (await previous.exists()) {
      await previous.rename(layout.current);
    }
    await _finishOrRollbackFrontendSwap(layout);
  }

  Future<void> _finishOrRollbackFrontendSwap(InstallLayout layout) async {
    final current = Directory(layout.frontendCurrent);
    final previous = Directory(layout.frontendPrevious);
    if (await current.exists()) {
      return;
    }
    if (await previous.exists()) {
      await previous.rename(layout.frontendCurrent);
    }
  }

  Future<void> _cleanStaging(InstallLayout layout) async {
    final staging = Directory(layout.staging);
    if (await staging.exists()) {
      await staging.delete(recursive: true);
    }
    final frontendStaging = Directory(layout.frontendStaging);
    if (await frontendStaging.exists()) {
      await frontendStaging.delete(recursive: true);
    }
  }

  Future<String> _findCoreRoot(String stagingPath) async {
    return _findPackageRoot(stagingPath, label: 'cinepro core');
  }

  Future<String> _findPackageRoot(
    String stagingPath, {
    required String label,
  }) async {
    final direct = File(p.join(stagingPath, 'package.json'));
    if (await direct.exists()) return stagingPath;

    await for (final entity in Directory(stagingPath).list()) {
      if (entity is! Directory) continue;
      final packageFile = File(p.join(entity.path, 'package.json'));
      if (await packageFile.exists()) return entity.path;
    }
    throw StateError('extracted archive does not contain $label');
  }

  Future<void> _validateCoreRoot(String coreRoot) async {
    final packageFile = File(p.join(coreRoot, 'package.json'));
    final envExample = File(p.join(coreRoot, '.env.example'));
    if (!await packageFile.exists() || !await envExample.exists()) {
      throw StateError('cinepro core validation failed');
    }
  }

  Future<void> _validateFrontendRoot(String frontendRoot) async {
    final packageFile = File(p.join(frontendRoot, 'package.json'));
    final sourceDir = Directory(p.join(frontendRoot, 'src'));
    if (!await packageFile.exists() || !await sourceDir.exists()) {
      throw StateError('cinepro frontend validation failed');
    }
  }

  Future<void> _ensureEnv(String coreRoot) async {
    final env = File(p.join(coreRoot, '.env'));
    final envExample = File(p.join(coreRoot, '.env.example'));
    if (!await env.exists() && await envExample.exists()) {
      await envExample.copy(env.path);
    }
  }

  Future<void> _ensureRuntime({
    required InstallLayout layout,
    required ReleaseManifest manifest,
    required void Function(int received, int total) onDownloadProgress,
  }) async {
    final versionFile = File(p.join(layout.runtime, 'node-version.txt'));
    final nodeFile = File(p.join(layout.runtime, 'node.exe'));
    if (await nodeFile.exists() &&
        await versionFile.exists() &&
        (await versionFile.readAsString()).trim() ==
            manifest.runtime.nodeVersion) {
      return;
    }

    final runtimeAsset = ReleaseAsset(
      name: 'node-${manifest.runtime.nodeVersion}-win-x64.zip',
      url: manifest.runtime.url,
      sha256: manifest.runtime.sha256,
      size: manifest.runtime.size,
    );
    final zipPath = await releaseClient.downloadVerifiedAsset(
      asset: runtimeAsset,
      downloadDir: p.join(layout.root, 'downloads'),
      onProgress: onDownloadProgress,
    );
    final runtimeStaging = p.join(layout.root, 'runtime-staging');
    await extractor.extract(zipPath: zipPath, destinationPath: runtimeStaging);
    final nodeRoot = await _findNodeRoot(runtimeStaging);

    final runtimeDir = Directory(layout.runtime);
    if (await runtimeDir.exists()) {
      await runtimeDir.delete(recursive: true);
    }
    await Directory(nodeRoot).rename(layout.runtime);
    await versionFile.writeAsString(manifest.runtime.nodeVersion, flush: true);
    final leftover = Directory(runtimeStaging);
    if (await leftover.exists()) {
      await leftover.delete(recursive: true);
    }
  }

  Future<String> _findNodeRoot(String stagingPath) async {
    final direct = File(p.join(stagingPath, 'node.exe'));
    if (await direct.exists()) return stagingPath;
    await for (final entity in Directory(stagingPath).list()) {
      if (entity is! Directory) continue;
      final nodeFile = File(p.join(entity.path, 'node.exe'));
      if (await nodeFile.exists()) return entity.path;
    }
    throw StateError('node runtime validation failed');
  }
}
