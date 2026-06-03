import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'models/env_entry.dart';
import 'models/install_state.dart';
import 'models/service_manifest.dart';
import 'services/app_paths.dart';
import 'services/desktop_shell_service.dart';
import 'services/docker_service.dart';
import 'services/env_service.dart';
import 'services/frontend_url_detector.dart';
import 'services/hash_service.dart';
import 'services/health_service.dart';
import 'services/install_manager.dart';
import 'services/install_marker.dart';
import 'services/log_service.dart';
import 'services/manifest_verifier.dart';
import 'services/process_supervisor.dart';
import 'services/release_client.dart';
import 'services/safe_zip_extractor.dart';
import 'services/state_store.dart';

/// describes a closable message shown over the dashboard with a stable key
class ManagerNotice {
  /// @param id unique instance id used by the close button
  /// @param key stable dedupe key so repeated problems do not stack
  /// @param title short notice title shown in the toast card
  /// @param message readable detail shown under the title
  ///
  /// creates a notice that can be dismissed without clearing logs
  const ManagerNotice({
    required this.id,
    required this.key,
    required this.title,
    required this.message,
  });

  final String id;
  final String key;
  final String title;
  final String message;
}

/// describes the ui contract used by the dashboard and widget smoke tests
abstract class ManagerViewController implements Listenable {
  ManifestLookupResult? get latestLookup;
  FrontendLookupResult? get frontendLookup;
  ManagerUpdateLookupResult? get managerUpdateLookup;
  DockerStatus? get dockerStatus;
  List<EnvEntry> get envEntries;
  List<String> get logLines;
  List<ManagerNotice> get notices;
  String get managerInstallDir;
  String get selectedInstallRoot;
  String get status;
  String? get installedFrontendCommit;
  double get progress;
  bool get busy;
  bool get logsVisible;
  bool get coreRunning;
  bool get frontendRunning;
  String get coreUrl;
  String get frontendUrl;
  String get languageName;
  bool get managerUpdateAvailable;
  bool get coreUpdateReady;

  Future<void> chooseInstallFolder();
  Future<void> checkForUpdates();
  Future<void> checkManagerUpdates();
  Future<void> updateManager();
  Future<void> installOrUpdate();
  Future<void> startCore();
  Future<void> stopServices();
  Future<void> checkHealth();
  Future<void> checkDocker();
  Future<void> startRedis();
  Future<void> stopRedis();
  Future<void> clearRedis();
  Future<void> openCore();
  Future<void> openFrontend();
  Future<void> openBugReport();
  Future<void> openChangelog();
  Future<void> openFoundation();
  Future<void> saveEnv();
  void updateEnv(String key, String value);
  void changeLanguage(String language);
  Future<void> clearLogs();
  Future<void> uninstall({required bool removeCore, required bool removeLogs});
  void toggleLogs();
  void showLogs();
  void dismissNotice(String id);
}

/// coordinates installs, updates, services, env, notices, docker, and logs
class ManagerController extends ChangeNotifier
    implements ManagerViewController {
  /// @param paths resolved app, data, cache, log, and install folders
  /// @param http client shared http client for github and health checks
  /// @param log manager log sink and live log stream
  /// @param state store durable install transaction state
  /// @param release client github release and archive client
  /// @param install manager staged install, update, recovery, and uninstall service
  /// @param env service env reader, writer, and required value validator
  /// @param health service backend health endpoint client
  /// @param process supervisor managed process runner with exit events
  /// @param docker service docker and redis helper
  /// @param frontend url detector frontend url parser and port probe helper
  ///
  /// creates a controller with injected services so ui tests can replace it cleanly
  ManagerController._({
    required this.paths,
    required this.httpClient,
    required this.log,
    required this.stateStore,
    required this.releaseClient,
    required this.installManager,
    required this.envService,
    required this.healthService,
    required this.processSupervisor,
    required this.dockerService,
    required this.frontendUrlDetector,
  });

  static const releaseManifestPublicKeyBase64 =
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
  static const appVersion = '0.1.0';
  static const foundationName = 'cinepro foundation';
  static const foundationUrl = 'https://github.com/cinepro-org';
  static const bugReportUrl = 'https://github.com/cinepro-org/core/issues';
  static const changelogUrl = 'https://github.com/cinepro-org/core/releases';

  final AppPaths paths;
  final http.Client httpClient;
  final LogService log;
  final StateStore stateStore;
  final ReleaseClient releaseClient;
  final InstallManager installManager;
  final EnvService envService;
  final HealthService healthService;
  final ProcessSupervisor processSupervisor;
  final DockerService dockerService;
  final FrontendUrlDetector frontendUrlDetector;

  InstallState state = InstallState.idle();
  @override
  ManifestLookupResult? latestLookup;
  @override
  FrontendLookupResult? frontendLookup;
  @override
  ManagerUpdateLookupResult? managerUpdateLookup;
  @override
  DockerStatus? dockerStatus;
  @override
  List<EnvEntry> envEntries = const [];
  @override
  List<String> logLines = const [];
  @override
  List<ManagerNotice> notices = const [];
  @override
  String managerInstallDir = '';
  @override
  String selectedInstallRoot = '';
  @override
  String status = 'ready';
  @override
  String languageName = 'english';
  @override
  String? installedFrontendCommit;
  @override
  double progress = 0;
  @override
  bool busy = false;
  @override
  bool logsVisible = false;
  @override
  bool coreRunning = false;
  @override
  bool frontendRunning = false;
  ServiceManifest serviceManifest = ServiceManifest.defaultServices();
  String _frontendUrl = '';
  int _frontendPort = 0;
  Completer<String>? _frontendUrlReady;
  StreamSubscription<String>? _logSub;
  StreamSubscription<ServiceProcessEvent>? _processSub;
  StreamSubscription<ServiceProcessOutput>? _processOutputSub;
  StreamSubscription<FileSystemEvent>? _pathWatchSub;
  Timer? _pathCheckTimer;
  int _noticeCounter = 0;

  InstallLayout get layout => InstallLayout(selectedInstallRoot);
  @override
  String get coreUrl => _serviceBaseUrl();
  @override
  String get frontendUrl => _frontendUrl.isEmpty
      ? frontendUrlDetector.fallbackUrl(_currentFrontendPort)
      : _frontendUrl;
  @override
  bool get managerUpdateAvailable =>
      managerUpdateLookup?.ready == true &&
      managerUpdateLookup?.updateAvailable == true;
  @override
  bool get coreUpdateReady => latestLookup?.ready == true;
  int get _currentFrontendPort => _frontendPort == 0
      ? serviceManifest.byId('frontend').port
      : _frontendPort;

  /// creates the controller, wires services, and recovers unfinished work
  static Future<ManagerController> create({
    bool runSetupInstall = false,
  }) async {
    final paths = await AppPaths.resolve();
    final httpClient = http.Client();
    final log = LogService(paths.logFile);
    final hashService = HashService();
    final stateStore = StateStore(paths.stateFile);
    final releaseClient = ReleaseClient(
      httpClient: httpClient,
      hashService: hashService,
      verifier: ManifestVerifier(
        publicKeyBase64: releaseManifestPublicKeyBase64,
      ),
      log: log,
    );
    final controller = ManagerController._(
      paths: paths,
      httpClient: httpClient,
      log: log,
      stateStore: stateStore,
      releaseClient: releaseClient,
      installManager: InstallManager(
        stateStore: stateStore,
        releaseClient: releaseClient,
        extractor: const SafeZipExtractor(),
        marker: const InstallMarker(),
        log: log,
      ),
      envService: const EnvService(),
      healthService: HealthService(httpClient),
      processSupervisor: ProcessSupervisor(log: log),
      dockerService: const DockerService(),
      frontendUrlDetector: const FrontendUrlDetector(),
    );
    await controller._boot(runSetupInstall: runSetupInstall);
    return controller;
  }

  /// checks startup recovery, loads logs, watches files, and listens for service exits
  Future<void> _boot({required bool runSetupInstall}) async {
    managerInstallDir = paths.appInstallDir;
    selectedInstallRoot = paths.defaultInstallRoot;
    _resetFrontendUrl();
    state = await installManager.recover();
    if (state.installPath != null) {
      selectedInstallRoot = state.installPath!;
    }
    logLines = await log.tail();
    await _loadInstallMarker();
    _logSub = log.lines.listen((line) {
      logLines = [...logLines, line];
      if (logLines.length > 160) {
        logLines = logLines.sublist(logLines.length - 160);
      }
      notifyListeners();
    });
    _processSub = processSupervisor.events.listen(_handleServiceEvent);
    _processOutputSub = processSupervisor.outputs.listen(_handleServiceOutput);
    await loadEnv();
    _watchInstallRoot();
    unawaited(_validateManagedPaths(silent: true));
    notifyListeners();
    if (runSetupInstall) {
      _pushNotice(
        key: 'setup-install-started',
        title: 'Setup Completed',
        message:
            'CinePro Manager will now check GitHub releases and install verified CinePro files.',
      );
      unawaited(_startSetupInstallFlow());
    }
  }

  /// opens the native windows folder picker and reloads state for the selected root
  @override
  Future<void> chooseInstallFolder() async {
    final selected = await getDirectoryPath(
      initialDirectory: selectedInstallRoot,
    );
    if (selected == null || selected.isEmpty) return;
    selectedInstallRoot = selected;
    await loadEnv();
    await _loadInstallMarker();
    _watchInstallRoot();
    await _validateManagedPaths(silent: false);
    notifyListeners();
  }

  Future<void> _startSetupInstallFlow() async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (busy) return;
    await installOrUpdate();
  }

  /// checks core releases and ui main so the dashboard can show update readiness
  @override
  Future<void> checkForUpdates() async {
    await _runBusy('checking for updates', () async {
      latestLookup = await releaseClient.getLatestManagerManifest();
      frontendLookup = await releaseClient.getFrontendMainSnapshot();
      managerUpdateLookup = await releaseClient.getLatestManagerUpdate(
        appVersion,
      );
      final lookup = latestLookup!;
      final frontend = frontendLookup!;
      final managerUpdate = managerUpdateLookup!;
      final frontendStatus = frontend.ready
          ? 'UI main ${frontend.snapshot!.commit.substring(0, 7)} is available.'
          : _userMessage(frontend.reason, 'UI main could not be checked.');
      final managerStatus = managerUpdate.updateAvailable
          ? 'Manager update ${managerUpdate.version ?? managerUpdate.release.tagName} is available.'
          : _userMessage(managerUpdate.reason, 'Manager is up to date.');
      if (!lookup.ready) {
        final message = _userMessage(
          lookup.reason,
          'The latest Core release is not manager ready.',
        );
        _pushNotice(
          key: 'core-release-not-ready',
          title: 'Core Release Is Not Ready',
          message: message,
        );
        status = 'Update check completed. $frontendStatus $managerStatus';
      } else {
        _removeNoticeByKey('core-release-not-ready');
        status =
            'Core ${lookup.manifest!.tag} is ready. $frontendStatus $managerStatus';
      }
      if (!frontend.ready) {
        _pushNotice(
          key: 'frontend-update-not-ready',
          title: 'Frontend Check Failed',
          message: frontendStatus,
        );
      } else {
        _removeNoticeByKey('frontend-update-not-ready');
      }
    });
  }

  /// checks only the manager setup update state used by the help menu dot
  @override
  Future<void> checkManagerUpdates() async {
    await _runBusy('checking manager updates', () async {
      managerUpdateLookup = await releaseClient.getLatestManagerUpdate(
        appVersion,
      );
      final update = managerUpdateLookup!;
      if (!update.ready) {
        final message = _userMessage(
          update.reason,
          'The manager update asset is not ready.',
        );
        _pushNotice(
          key: 'manager-update-not-ready',
          title: 'Manager Update Is Not Ready',
          message: message,
        );
        status = message;
        return;
      }
      _removeNoticeByKey('manager-update-not-ready');
      status = update.updateAvailable
          ? 'Manager update ${update.version ?? update.release.tagName} is available.'
          : _userMessage(update.reason, 'Manager is up to date.');
    });
  }

  /// downloads the verified manager setup exe, launches it, and closes the manager
  @override
  Future<void> updateManager() async {
    await _runBusy('preparing manager update', () async {
      managerUpdateLookup ??= await releaseClient.getLatestManagerUpdate(
        appVersion,
      );
      final update = managerUpdateLookup!;
      if (!update.ready || !update.updateAvailable) {
        final message = _userMessage(
          update.reason,
          'The manager update is not ready.',
        );
        _pushNotice(
          key: 'manager-update-not-ready',
          title: 'Manager Update Is Not Ready',
          message: message,
        );
        status = message;
        return;
      }
      final setupPath = await releaseClient.downloadVerifiedManagerSetup(
        update: update,
        downloadDir: p.join(paths.downloadDir, 'manager-update'),
        onProgress: (received, total) {
          progress = total == 0 ? 0 : received / total;
          notifyListeners();
        },
      );
      progress = 1;
      status = 'Manager setup downloaded.';
      await log.write('launching manager update setup');
      await DesktopShellService.instance.launchInstaller(setupPath);
      await DesktopShellService.instance.exitFromTray();
    });
  }

  /// installs or updates core and ui only when the core manifest is signed
  @override
  Future<void> installOrUpdate() async {
    await _runBusy('preparing install', () async {
      latestLookup ??= await releaseClient.getLatestManagerManifest();
      frontendLookup ??= await releaseClient.getFrontendMainSnapshot();
      final manifest = latestLookup?.manifest;
      final frontend = frontendLookup?.snapshot;
      if (manifest == null) {
        final message = _userMessage(
          latestLookup?.reason,
          'No signed Core manifest was found.',
        );
        _pushNotice(
          key: 'core-release-not-ready',
          title: 'Core Release Is Not Ready',
          message: message,
        );
        status = message;
        return;
      }
      if (frontend == null) {
        final message = _userMessage(
          frontendLookup?.reason,
          'Frontend main could not be loaded.',
        );
        _pushNotice(
          key: 'frontend-update-not-ready',
          title: 'Frontend Check Failed',
          message: message,
        );
        status = message;
        return;
      }
      await installManager.installOrUpdate(
        installRoot: selectedInstallRoot,
        manifest: manifest,
        frontend: frontend,
        onDownloadProgress: (received, total) {
          progress = total == 0 ? 0 : received / total;
          notifyListeners();
        },
      );
      state = await stateStore.load();
      progress = 1;
      status = 'CinePro Core and UI are installed.';
      _removeNoticeByKey('core-release-not-ready');
      _removeNoticeByKey('frontend-update-not-ready');
      await loadEnv();
      await _loadInstallMarker();
      _watchInstallRoot();
    });
  }

  /// loads env values from the active core folder and clears them when core is absent
  Future<void> loadEnv() async {
    final current = Directory(layout.current);
    if (!await current.exists()) {
      envEntries = const [];
      return;
    }
    envEntries = await envService.load(layout.current);
  }

  /// saves edited env values back to the active core env file
  @override
  Future<void> saveEnv() async {
    await _runBusy('saving env', () async {
      await envService.save(layout.current, envEntries);
      status = 'env saved';
    });
  }

  /// @param key env variable name being edited by the user
  /// @param value new value held in memory until save env is clicked
  ///
  /// updates one env value in memory without writing the env file immediately
  @override
  void updateEnv(String key, String value) {
    envEntries = [
      for (final entry in envEntries)
        if (entry.key == key) entry.copyWith(value: value) else entry,
    ];
    notifyListeners();
  }

  /// starts cinepro core and then attempts to start the ui through bundled npm
  @override
  Future<void> startCore() async {
    await _runBusy('starting cinepro services', () async {
      final pathsOk = await _validateManagedPaths(silent: false);
      if (!pathsOk) {
        status = 'managed cinepro files need attention';
        return;
      }
      await loadEnv();
      final validation = envService.validate(envEntries);
      if (!validation.valid) {
        status =
            'missing required env: ${validation.missingRequiredKeys.join(', ')}';
        return;
      }
      await _warnIfRedisNeedsDocker();

      final node = File(p.join(layout.runtime, 'node.exe'));
      final npm = File(p.join(layout.runtime, 'npm.cmd'));
      final coreSpec = serviceManifest.byId('core');
      final server = File(p.join(layout.current, coreSpec.command));
      if (!await node.exists()) {
        status = 'bundled node runtime is not installed yet';
        return;
      }
      if (!await server.exists()) {
        status = 'this core package is not built for manager startup yet';
        return;
      }

      final env = {for (final entry in envEntries) entry.key: entry.value};
      env.putIfAbsent('NODE_ENV', () => 'production');
      await processSupervisor.start(
        id: coreSpec.id,
        executable: node.path,
        arguments: [server.path, ...coreSpec.arguments],
        workingDirectory: layout.current,
        environment: env,
      );
      coreRunning = true;
      final frontendStarted = await _startFrontend(npm: npm);
      status = frontendStarted
          ? 'cinepro core and ui are running'
          : 'cinepro core is running; ui is not ready yet';
    });
  }

  /// stops all services started by the manager and marks both badges inactive
  @override
  Future<void> stopServices() async {
    await _runBusy('stopping services', () async {
      await processSupervisor.stopAll();
      coreRunning = false;
      frontendRunning = false;
      _resetFrontendUrl();
      status = 'services stopped';
    });
  }

  /// checks core health using the current env host and port values
  @override
  Future<void> checkHealth() async {
    await _runBusy('checking health', () async {
      await loadEnv();
      final values = {for (final entry in envEntries) entry.key: entry.value};
      final host =
          values['HOST']?.isNotEmpty == true ? values['HOST']! : 'localhost';
      final port = int.tryParse(values['PORT'] ?? '') ?? 3000;
      final snapshot = await healthService.check(host: host, port: port);
      status = snapshot.ok ? 'health is ${snapshot.status}' : snapshot.status;
    });
  }

  /// checks docker and redis availability before any redis action is attempted
  @override
  Future<void> checkDocker() async {
    await _runBusy('checking docker', () async {
      dockerStatus = await dockerService.check();
      status = dockerStatus!.summary;
      if (!dockerStatus!.ready) {
        _pushNotice(
          key: 'docker-not-ready',
          title: 'Docker Not Ready',
          message: dockerStatus!.summary,
        );
      }
    });
  }

  /// starts or creates the managed redis container when docker is ready
  @override
  Future<void> startRedis() async {
    await _runBusy('starting redis', () async {
      await dockerService.startRedis();
      dockerStatus = await dockerService.check();
      _applyRedisEnvDefaults();
      status = 'redis is running';
    });
  }

  /// stops the managed redis container without deleting cache data or the container
  @override
  Future<void> stopRedis() async {
    await _runBusy('stopping redis', () async {
      await dockerService.stopRedis();
      dockerStatus = await dockerService.check();
      status = 'redis stopped';
    });
  }

  /// clears redis cache through docker after checking daemon and container readiness
  @override
  Future<void> clearRedis() async {
    await _runBusy('clearing redis cache', () async {
      await dockerService.clearRedis();
      dockerStatus = await dockerService.check();
      status = 'redis cache cleared';
    });
  }

  /// opens the backend url in the default windows browser
  @override
  Future<void> openCore() async {
    await DesktopShellService.instance.openUrl(coreUrl);
  }

  /// opens the frontend url in the default windows browser
  @override
  Future<void> openFrontend() async {
    await DesktopShellService.instance.openUrl(frontendUrl);
  }

  /// opens the github issues page for cinepro core bug reports
  @override
  Future<void> openBugReport() async {
    await DesktopShellService.instance.openUrl(bugReportUrl);
  }

  /// opens the github releases page so users can read update notes
  @override
  Future<void> openChangelog() async {
    await DesktopShellService.instance.openUrl(changelogUrl);
  }

  /// opens the cinepro foundation github organization page
  @override
  Future<void> openFoundation() async {
    await DesktopShellService.instance.openUrl(foundationUrl);
  }

  /// @param language selected display language name from the manager menu
  ///
  /// stores the current language choice for future translation support
  @override
  void changeLanguage(String language) {
    languageName = language;
    status = 'language set to $language';
    notifyListeners();
  }

  /// clears the app log file and refreshes the visible log panel
  @override
  Future<void> clearLogs() async {
    await log.clear();
    logLines = const [];
    notifyListeners();
  }

  @override
  void toggleLogs() {
    logsVisible = !logsVisible;
    notifyListeners();
  }

  @override
  void showLogs() {
    if (logsVisible) return;
    logsVisible = true;
    notifyListeners();
  }

  /// @param id notice id created when the toast was pushed
  ///
  /// removes one closable dashboard notice without changing logs
  @override
  void dismissNotice(String id) {
    notices = [
      for (final notice in notices)
        if (notice.id != id) notice,
    ];
    notifyListeners();
  }

  /// @param remove core whether managed core, ui, runtime, and downloads should be removed
  /// @param remove logs whether the manager log file should also be cleared
  ///
  /// uninstalls managed files only after the prompt confirms user intent
  @override
  Future<void> uninstall({
    required bool removeCore,
    required bool removeLogs,
  }) async {
    await _runBusy('uninstalling', () async {
      await processSupervisor.stopAll();
      coreRunning = false;
      await installManager.uninstall(
        installRoot: selectedInstallRoot,
        removeCore: removeCore,
        removeLogs: removeLogs,
        logPath: paths.logFile,
      );
      envEntries = const [];
      status = removeCore
          ? 'managed cinepro files removed'
          : 'cinepro manager detached';
    });
  }

  Future<void> _runBusy(String message, Future<void> Function() task) async {
    busy = true;
    logsVisible = true;
    status = _userMessage(message, message);
    progress = 0;
    notifyListeners();
    try {
      await log.write(message);
      await task();
    } on Object catch (error) {
      final message = _userMessage('$error', 'Something went wrong.');
      status = message;
      _pushNotice(
        key: 'manager-error',
        title: 'Something Went Wrong',
        message: message,
      );
      await log.write('error: $error');
      await DesktopShellService.instance.showImportant(
        'cinepro manager needs attention',
      );
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _loadInstallMarker() async {
    final marker = await installManager.marker.read(selectedInstallRoot);
    installedFrontendCommit = marker?.uiCommit;
  }

  void _handleServiceEvent(ServiceProcessEvent event) {
    if (event.id == 'core') {
      coreRunning = event.running;
    }
    if (event.id == 'frontend') {
      frontendRunning = event.running;
      if (!event.running) {
        _resetFrontendUrl();
      }
    }
    if (!event.running && !event.stoppedByManager) {
      _pushNotice(
        key: 'service-${event.id}-closed',
        title: '${_titleCase(event.id)} Closed',
        message:
            '${_titleCase(event.id)} stopped outside the manager with code ${event.exitCode ?? 'unknown'}.',
      );
      status = '${event.id} closed outside the manager';
    }
    if (event.running) {
      _removeNoticeByKey('service-${event.id}-closed');
    }
    notifyListeners();
  }

  void _handleServiceOutput(ServiceProcessOutput output) {
    if (output.id != 'frontend') return;
    final detected = frontendUrlDetector.fromProcessLine(
      line: output.line,
      coreUrl: coreUrl,
      expectedPort: _currentFrontendPort,
    );
    if (detected == null) return;
    final changed = _frontendUrl != detected;
    _frontendUrl = detected;
    final ready = _frontendUrlReady;
    if (ready != null && !ready.isCompleted) {
      ready.complete(detected);
    }
    if (!changed) return;
    unawaited(log.write('frontend url detected: $detected'));
    notifyListeners();
  }

  void _watchInstallRoot() {
    unawaited(_pathWatchSub?.cancel());
    _pathCheckTimer?.cancel();

    final root = Directory(selectedInstallRoot);
    if (root.existsSync()) {
      _pathWatchSub = root.watch().listen(
            (_) => unawaited(_validateManagedPaths(silent: false)),
            onError: (_) => unawaited(_validateManagedPaths(silent: true)),
          );
    }

    _pathCheckTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_validateManagedPaths(silent: true));
    });
  }

  Future<bool> _validateManagedPaths({required bool silent}) async {
    final marker = await installManager.marker.read(selectedInstallRoot);
    final hasManagedState = marker != null ||
        state.installPath == selectedInstallRoot ||
        installedFrontendCommit != null;
    if (!hasManagedState) {
      return true;
    }

    var ok = true;
    if (!await Directory(selectedInstallRoot).exists()) {
      ok = false;
      _pushMissingPathNotice(
        key: 'missing-root',
        title: 'Install Folder Missing',
        message: 'The managed CinePro folder was removed or moved.',
        silent: silent,
      );
    } else {
      _removeNoticeByKey('missing-root');
    }

    if (!await Directory(layout.current).exists()) {
      ok = false;
      _pushMissingPathNotice(
        key: 'missing-core',
        title: 'Core Files Missing',
        message: 'The Core folder is missing from the managed install.',
        silent: silent,
      );
    } else {
      _removeNoticeByKey('missing-core');
    }

    if (!await Directory(layout.runtime).exists()) {
      ok = false;
      _pushMissingPathNotice(
        key: 'missing-runtime',
        title: 'Runtime Missing',
        message: 'The bundled Node runtime is missing.',
        silent: silent,
      );
    } else {
      _removeNoticeByKey('missing-runtime');
    }

    final uiCommit = marker?.uiCommit ?? installedFrontendCommit;
    if ((uiCommit ?? '').isNotEmpty &&
        !await Directory(layout.frontendCurrent).exists()) {
      ok = false;
      _pushMissingPathNotice(
        key: 'missing-frontend',
        title: 'Frontend Files Missing',
        message: 'The UI folder is missing from the managed install.',
        silent: silent,
      );
    } else {
      _removeNoticeByKey('missing-frontend');
    }

    if (!ok && !silent) {
      await log.write('managed install path validation failed');
    }
    return ok;
  }

  void _pushMissingPathNotice({
    required String key,
    required String title,
    required String message,
    required bool silent,
  }) {
    _pushNotice(key: key, title: title, message: message);
    if (!silent) {
      showLogs();
    }
  }

  Future<void> _warnIfRedisNeedsDocker() async {
    final cacheType = _envValue('CACHE_TYPE').toLowerCase();
    if (cacheType != 'redis') return;
    dockerStatus = await dockerService.check();
    if (dockerStatus?.redisRunning == true) return;
    _pushNotice(
      key: 'redis-not-running',
      title: 'Redis Is Not Running',
      message:
          'CACHE_TYPE is set to redis, but the managed redis container is not running.',
    );
    await log.write('redis is enabled but not running');
  }

  void _applyRedisEnvDefaults() {
    if (envEntries.isEmpty) return;
    _setEnvValue('CACHE_TYPE', 'redis');
    _setEnvValue('REDIS_HOST', 'localhost');
    _setEnvValue('REDIS_PORT', '${DockerService.redisPort}');
    _removeNoticeByKey('redis-not-running');
  }

  String _envValue(String key) {
    for (final entry in envEntries) {
      if (entry.key == key) return entry.value.trim();
    }
    return '';
  }

  void _setEnvValue(String key, String value) {
    envEntries = [
      for (final entry in envEntries)
        if (entry.key == key) entry.copyWith(value: value) else entry,
    ];
  }

  void _pushNotice({
    required String key,
    required String title,
    required String message,
  }) {
    if (notices.any((notice) => notice.key == key)) return;
    _noticeCounter++;
    notices = [
      ManagerNotice(
        id: 'notice-$_noticeCounter',
        key: key,
        title: title,
        message: message,
      ),
      ...notices,
    ].take(4).toList();
    notifyListeners();
  }

  void _removeNoticeByKey(String key) {
    if (!notices.any((notice) => notice.key == key)) return;
    notices = [
      for (final notice in notices)
        if (notice.key != key) notice,
    ];
    notifyListeners();
  }

  String _serviceBaseUrl() {
    final host = _envValue('HOST').isEmpty ? 'localhost' : _envValue('HOST');
    final port = int.tryParse(_envValue('PORT')) ?? 3000;
    return 'http://$host:$port';
  }

  void _resetFrontendUrl() {
    _frontendPort = serviceManifest.byId('frontend').port;
    _frontendUrl = frontendUrlDetector.fallbackUrl(_frontendPort);
    _frontendUrlReady = null;
  }

  Future<String?> _waitForFrontendUrl(int port) async {
    final ready = _frontendUrlReady;
    final outputUrl = ready?.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () => '',
    );
    final portUrl = frontendUrlDetector
        .waitForLocalPort(port: port)
        .then((open) => open ? frontendUrlDetector.fallbackUrl(port) : '');
    final detected = await Future.any([
      if (outputUrl != null) outputUrl,
      portUrl,
    ]);
    if (detected.isEmpty) return null;
    _frontendUrl = detected;
    return detected;
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _userMessage(String? reason, String fallback) {
    final raw =
        (reason == null || reason.trim().isEmpty) ? fallback : reason.trim();
    final withoutPrefix = raw.replaceFirst(
      RegExp(r'^(stateerror|httpexception|exception):\s*',
          caseSensitive: false),
      '',
    );
    final normalized = withoutPrefix
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('ui', 'UI')
        .replaceAll('core', 'Core')
        .replaceAll('github', 'GitHub')
        .replaceAll('sha256', 'SHA256')
        .replaceAll('ed25519', 'Ed25519');
    final capitalized = normalized.isEmpty
        ? fallback
        : '${normalized[0].toUpperCase()}${normalized.substring(1)}';
    if (RegExp(r'[.!?]$').hasMatch(capitalized)) return capitalized;
    return '$capitalized.';
  }

  Future<bool> _startFrontend({required File npm}) async {
    final frontendSpec = serviceManifest.byId('frontend');
    if (processSupervisor.isRunning(frontendSpec.id)) {
      frontendRunning = true;
      return true;
    }

    final frontendRoot = Directory(layout.frontendCurrent);
    if (!await frontendRoot.exists()) {
      await log.write('frontend is not installed');
      return false;
    }
    if (!await npm.exists()) {
      await log.write('bundled npm is not installed');
      return false;
    }

    await _ensureFrontendDependencies(
      npmPath: npm.path,
      workingDirectory: frontendRoot.path,
    );
    final script = await _selectFrontendScript(frontendRoot.path);
    final frontendPort = await frontendUrlDetector.findAvailablePort(
      preferredPort: frontendSpec.port,
    );
    _frontendPort = frontendPort;
    _frontendUrl = frontendUrlDetector.fallbackUrl(frontendPort);
    _frontendUrlReady = Completer<String>();
    final values = {for (final entry in envEntries) entry.key: entry.value};
    final host =
        values['HOST']?.isNotEmpty == true ? values['HOST']! : 'localhost';
    final port = int.tryParse(values['PORT'] ?? '') ?? 3000;
    final coreUrl = 'http://$host:$port';
    final frontendEnv = {
      'NODE_ENV': script == 'dev' ? 'development' : 'production',
      'HOST': '127.0.0.1',
      'PORT': '$frontendPort',
      'VITE_HOST': '127.0.0.1',
      'VITE_PORT': '$frontendPort',
      'BROWSER': 'none',
      'CORE_URL': coreUrl,
      'CINEPRO_CORE_URL': coreUrl,
      'VITE_CINEPRO_CORE_URL': coreUrl,
    };
    await processSupervisor.start(
      id: frontendSpec.id,
      executable: npm.path,
      arguments: ['run', script],
      workingDirectory: frontendRoot.path,
      environment: frontendEnv,
      runInShell: true,
    );
    frontendRunning = true;
    notifyListeners();
    final detected = await _waitForFrontendUrl(frontendPort);
    if (detected == null) {
      await log.write('frontend url was not detected yet');
    } else {
      await log.write('frontend url ready: $detected');
    }
    return true;
  }

  Future<void> _ensureFrontendDependencies({
    required String npmPath,
    required String workingDirectory,
  }) async {
    final nodeModules = Directory(p.join(workingDirectory, 'node_modules'));
    if (await nodeModules.exists()) {
      return;
    }

    final hasLock =
        await File(p.join(workingDirectory, 'package-lock.json')).exists();
    final args = hasLock ? ['ci'] : ['install'];
    await log.write('installing frontend dependencies with npm ${args.first}');
    final result = await Process.run(
      npmPath,
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
    ).timeout(const Duration(minutes: 10));
    if (result.exitCode != 0) {
      final stderr = (result.stderr as String).trim();
      final stdout = (result.stdout as String).trim();
      if (stdout.isNotEmpty) {
        await log.write('frontend npm output: ${_shortLog(stdout)}');
      }
      if (stderr.isNotEmpty) {
        await log.write('frontend npm error: ${_shortLog(stderr)}');
      }
      throw StateError('frontend dependency install failed');
    }
    await log.write('frontend dependencies installed');
  }

  Future<String> _selectFrontendScript(String workingDirectory) async {
    final packageFile = File(p.join(workingDirectory, 'package.json'));
    final json =
        jsonDecode(await packageFile.readAsString()) as Map<String, Object?>;
    final scripts = json['scripts'] as Map<String, Object?>? ?? const {};
    for (final script in const ['start', 'preview', 'dev']) {
      if (scripts.containsKey(script)) {
        return script;
      }
    }
    throw StateError('frontend package has no start, preview, or dev script');
  }

  String _shortLog(String value) {
    return value.length <= 800 ? value : '${value.substring(0, 800)}...';
  }

  /// releases child processes and open resources
  Future<void> close() async {
    await _logSub?.cancel();
    await _processSub?.cancel();
    await _processOutputSub?.cancel();
    await _pathWatchSub?.cancel();
    _pathCheckTimer?.cancel();
    await processSupervisor.dispose();
    await log.dispose();
    httpClient.close();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
