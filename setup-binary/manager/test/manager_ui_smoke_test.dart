import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cinepro_manager/src/app.dart';
import 'package:cinepro_manager/src/manager_controller.dart';
import 'package:cinepro_manager/src/models/env_entry.dart';
import 'package:cinepro_manager/src/models/release_manifest.dart';
import 'package:cinepro_manager/src/services/docker_service.dart';
import 'package:cinepro_manager/src/services/release_client.dart';
import 'package:cinepro_manager/src/theme/cinepro_theme.dart';

void main() {
  testWidgets('logs stay hidden until the user opens them', (tester) async {
    final controller = FakeManagerController();
    await _pumpManager(tester, controller);

    expect(
        find.text('logs will appear here after an action runs.'), findsNothing);

    await _tapText(tester, 'Logs');

    expect(find.text('Hide Logs'), findsOneWidget);
    expect(
      find.text('logs will appear here after an action runs.'),
      findsOneWidget,
    );
  });

  testWidgets('main manager controls respond to smoke taps', (tester) async {
    final controller = FakeManagerController(
      envEntries: const [
        EnvEntry(
          key: 'TMDB_API_KEY',
          value: 'test-key',
          description: 'required key used to fetch movie metadata',
          required: true,
          secret: true,
        ),
      ],
    );
    await _pumpManager(tester, controller);

    await _tapText(tester, 'Browse');
    await _tapText(tester, 'Check Updates');
    await _tapText(tester, 'Install Or Update');
    await _openMoreMenu(tester);
    await _tapText(tester, 'Update Manager');
    await _openMoreMenu(tester);
    await _tapText(tester, 'Changelog');
    await _openMoreMenu(tester);
    await _tapText(tester, 'Report Bug');
    await _openMoreMenu(tester);
    await _tapText(tester, 'Keyboard Shortcuts');
    await _tapText(tester, 'Close');
    await _openMoreMenu(tester);
    await _tapText(tester, 'Language (English)');
    await _tapText(tester, 'English');
    await _openMoreMenu(tester);
    await _tapText(tester, 'About CinePro Foundation');
    await _tapText(tester, 'Open Foundation');
    await _tapText(tester, 'Check Docker');
    await _tapText(tester, 'Start Redis');
    await _tapText(tester, 'Clear Redis Cache');
    await _tapText(tester, 'Stop Redis');
    await _tapText(tester, 'Start CinePro');
    await _tapText(tester, 'Open');
    await _tapText(tester, 'Open Frontend (http://localhost:6182)');
    await _tapText(tester, 'Stop All');
    await _tapText(tester, 'Health');

    await tester.enterText(find.byType(TextFormField).last, 'changed-key');
    await tester.pumpAndSettle();
    await _tapText(tester, 'Save Env');

    await _tapText(tester, 'Clear Logs');
    await _tapText(tester, 'Hide Logs');
    await _tapText(tester, 'Logs');

    controller.addTestNotice();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await _tapWidgetWithText<OutlinedButton>(tester, 'Uninstall');
    await _tapText(tester, 'Remove Logs');
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Uninstall'),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.chooseCount, 1);
    expect(controller.checkCount, 1);
    expect(controller.installCount, 1);
    expect(controller.managerUpdateCount, 1);
    expect(controller.changelogCount, 1);
    expect(controller.bugCount, 1);
    expect(controller.languageChangeCount, 1);
    expect(controller.foundationCount, 1);
    expect(controller.dockerCount, 1);
    expect(controller.redisStartCount, 1);
    expect(controller.redisStopCount, 1);
    expect(controller.redisClearCount, 1);
    expect(controller.startCount, 1);
    expect(controller.openFrontendCount, 1);
    expect(controller.stopCount, 1);
    expect(controller.healthCount, 1);
    expect(controller.saveCount, 1);
    expect(controller.clearCount, 1);
    expect(controller.uninstallCount, 1);
    expect(controller.updatedEnv['TMDB_API_KEY'], 'changed-key');
    expect(controller.lastRemoveCore, isTrue);
    expect(controller.lastRemoveLogs, isTrue);
  });
}

class FakeManagerController extends ChangeNotifier
    implements ManagerViewController {
  FakeManagerController({this.envEntries = const []});

  @override
  ManifestLookupResult? latestLookup;

  @override
  FrontendLookupResult? frontendLookup;

  @override
  ManagerUpdateLookupResult? managerUpdateLookup;

  @override
  DockerStatus? dockerStatus;

  @override
  List<EnvEntry> envEntries;

  @override
  List<String> logLines = const [];

  @override
  List<ManagerNotice> notices = const [];

  @override
  String managerInstallDir = r'C:\Program Files\CinePro Manager';

  @override
  String selectedInstallRoot = r'C:\CinePro';

  @override
  String status = 'ready';

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

  @override
  String coreUrl = 'http://localhost:3000';

  @override
  String frontendUrl = 'http://localhost:5173';

  @override
  String languageName = 'english';

  @override
  bool get managerUpdateAvailable =>
      managerUpdateLookup?.ready == true &&
      managerUpdateLookup?.updateAvailable == true;

  @override
  bool get coreUpdateReady => latestLookup?.ready == true;

  int chooseCount = 0;
  int checkCount = 0;
  int managerUpdateCheckCount = 0;
  int managerUpdateCount = 0;
  int bugCount = 0;
  int changelogCount = 0;
  int foundationCount = 0;
  int languageChangeCount = 0;
  int installCount = 0;
  int dockerCount = 0;
  int redisStartCount = 0;
  int redisStopCount = 0;
  int redisClearCount = 0;
  int startCount = 0;
  int openFrontendCount = 0;
  int stopCount = 0;
  int healthCount = 0;
  int saveCount = 0;
  int clearCount = 0;
  int uninstallCount = 0;
  bool? lastRemoveCore;
  bool? lastRemoveLogs;
  final updatedEnv = <String, String>{};

  @override
  Future<void> chooseInstallFolder() async {
    chooseCount++;
    selectedInstallRoot = r'C:\CineProTest';
    notifyListeners();
  }

  @override
  Future<void> checkForUpdates() async {
    checkCount++;
    latestLookup = ManifestLookupResult(
      release: _release(),
      manifest: null,
      ready: false,
      reason: 'this release has no signed windows manager manifest yet',
    );
    frontendLookup = const FrontendLookupResult(
      snapshot: FrontendSnapshot(
        commit: 'c7e523aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        branch: 'main',
        archiveUrl:
            'https://github.com/cinepro-org/ui/archive/refs/heads/main.zip',
      ),
      ready: true,
    );
    managerUpdateLookup = ManagerUpdateLookupResult(
      release: _release(),
      ready: true,
      updateAvailable: true,
      asset: 'cinepro-manager-setup-0.2.0.exe',
      url:
          'https://github.com/cinepro-org/core/releases/download/test/setup.exe',
      sha256:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      size: 12,
      version: '0.2.0',
    );
    showLogs();
  }

  @override
  Future<void> checkManagerUpdates() async {
    managerUpdateCheckCount++;
    managerUpdateLookup = ManagerUpdateLookupResult(
      release: _release(),
      ready: false,
      updateAvailable: false,
      reason: 'manager is already up to date',
    );
    notifyListeners();
  }

  @override
  Future<void> updateManager() async {
    managerUpdateCount++;
    showLogs();
  }

  @override
  Future<void> installOrUpdate() async {
    installCount++;
    showLogs();
  }

  @override
  Future<void> startCore() async {
    startCount++;
    logLines = const ['[test] cinepro core started'];
    coreRunning = true;
    frontendRunning = true;
    frontendUrl = 'http://localhost:6182';
    showLogs();
  }

  @override
  Future<void> stopServices() async {
    stopCount++;
    coreRunning = false;
    frontendRunning = false;
    frontendUrl = 'http://localhost:5173';
  }

  @override
  Future<void> checkHealth() async {
    healthCount++;
  }

  @override
  Future<void> checkDocker() async {
    dockerCount++;
    dockerStatus = const DockerStatus(
      cliFound: true,
      daemonRunning: true,
      desktopDetected: true,
      serviceDetected: true,
      serviceRunning: true,
      composeAvailable: true,
      redisContainerExists: true,
      redisRunning: false,
      redisPortBusy: false,
      summary: 'docker is ready for redis',
    );
    notifyListeners();
  }

  @override
  Future<void> startRedis() async {
    redisStartCount++;
    dockerStatus = const DockerStatus(
      cliFound: true,
      daemonRunning: true,
      desktopDetected: true,
      serviceDetected: true,
      serviceRunning: true,
      composeAvailable: true,
      redisContainerExists: true,
      redisRunning: true,
      redisPortBusy: false,
      summary: 'redis is running in docker',
    );
    notifyListeners();
  }

  @override
  Future<void> stopRedis() async {
    redisStopCount++;
  }

  @override
  Future<void> clearRedis() async {
    redisClearCount++;
  }

  @override
  Future<void> openCore() async {}

  @override
  Future<void> openFrontend() async {
    openFrontendCount++;
  }

  @override
  Future<void> openBugReport() async {
    bugCount++;
  }

  @override
  Future<void> openChangelog() async {
    changelogCount++;
  }

  @override
  Future<void> openFoundation() async {
    foundationCount++;
  }

  @override
  Future<void> saveEnv() async {
    saveCount++;
  }

  @override
  void updateEnv(String key, String value) {
    updatedEnv[key] = value;
  }

  @override
  void changeLanguage(String language) {
    languageChangeCount++;
    languageName = language;
    notifyListeners();
  }

  @override
  Future<void> clearLogs() async {
    clearCount++;
    logLines = const [];
    notifyListeners();
  }

  @override
  Future<void> uninstall({
    required bool removeCore,
    required bool removeLogs,
  }) async {
    uninstallCount++;
    lastRemoveCore = removeCore;
    lastRemoveLogs = removeLogs;
  }

  @override
  void toggleLogs() {
    logsVisible = !logsVisible;
    notifyListeners();
  }

  @override
  void showLogs() {
    logsVisible = true;
    notifyListeners();
  }

  @override
  void dismissNotice(String id) {
    notices = [
      for (final notice in notices)
        if (notice.id != id) notice,
    ];
    notifyListeners();
  }

  void addTestNotice() {
    notices = const [
      ManagerNotice(
        id: 'test-notice',
        key: 'test',
        title: 'Core Files Missing',
        message: 'The Core folder is missing.',
      ),
    ];
    notifyListeners();
  }

  GitHubRelease _release() {
    return GitHubRelease(
      tagName: 'main-test',
      name: 'main-test',
      body: '',
      htmlUrl: 'https://github.com/cinepro-org/core/releases',
      publishedAt: DateTime(2026),
    );
  }
}

Future<void> _pumpManager(
  WidgetTester tester,
  ManagerViewController controller,
) async {
  tester.view.physicalSize = const Size(1280, 920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: CineProTheme.light(),
      home: ManagerHome(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapText(
  WidgetTester tester,
  String text, {
  int skip = 0,
}) async {
  final finder = find.text(text).at(skip);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openMoreMenu(WidgetTester tester) async {
  final finder = find.byWidgetPredicate(
    (widget) => widget is PopupMenuButton<String> && widget.tooltip == 'More',
  );
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tapWidgetWithText<T extends Widget>(
  WidgetTester tester,
  String text,
) async {
  final finder = find.widgetWithText(T, text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
