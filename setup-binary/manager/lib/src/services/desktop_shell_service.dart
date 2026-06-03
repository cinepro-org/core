import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// manages native window sizing, tray behavior, and browser handoff
class DesktopShellService with WindowListener, TrayListener {
  DesktopShellService._();

  static final instance = DesktopShellService._();

  bool _ready = false;
  bool _quitting = false;

  /// initializes bounded window sizing, tray icon, and native window listeners
  Future<void> init() async {
    if (_ready || !Platform.isWindows) return;
    await windowManager.ensureInitialized();
    windowManager.addListener(this);
    trayManager.addListener(this);

    const options = WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(900, 640),
      maximumSize: Size(1680, 1120),
      center: true,
      title: 'cinepro manager',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    await _setupTray();
    _ready = true;
  }

  /// restores the hidden tray window and focuses it for urgent manager states
  Future<void> showWindow() async {
    if (!Platform.isWindows) return;
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  /// @param message tooltip text shown on the tray icon while attention is needed
  ///
  /// opens the manager when a task fails or needs user attention
  Future<void> showImportant(String message) async {
    if (!_ready || !Platform.isWindows) return;
    await trayManager.setToolTip(message);
    await showWindow();
  }

  /// @param url backend or frontend url opened through the windows shell
  ///
  /// opens a local service url in the default browser without adding a web plugin
  Future<void> openUrl(String url) async {
    if (!Platform.isWindows) return;
    await Process.start(
        'rundll32',
        [
          'url.dll,FileProtocolHandler',
          url,
        ],
        runInShell: true);
  }

  /// @param installer verified setup exe downloaded by the manager
  ///
  /// launches the setup exe so windows can request elevation when needed
  Future<void> launchInstaller(String installer) async {
    if (!Platform.isWindows) return;
    await Process.start(installer, const [], runInShell: true);
  }

  /// exits from the tray menu and allows normal process cleanup to run
  Future<void> exitFromTray() async {
    if (!Platform.isWindows) return;
    _quitting = true;
    await trayManager.destroy();
    await windowManager.close();
  }

  /// releases native window and tray listeners during app shutdown
  Future<void> dispose() async {
    if (!Platform.isWindows) return;
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    await trayManager.destroy();
  }

  @override
  void onWindowMinimize() {
    if (_quitting || !Platform.isWindows) return;
    windowManager.hide();
  }

  @override
  void onTrayIconMouseDown() {
    showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  Future<void> _setupTray() async {
    await trayManager.setIcon('assets/cinepro-logo.png');
    await trayManager.setToolTip('cinepro manager');
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(
            key: 'title',
            label: 'cinepro manager',
            disabled: true,
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'open',
            label: 'Open',
            onClick: (_) => showWindow(),
          ),
          MenuItem(
            key: 'exit',
            label: 'Exit',
            onClick: (_) => exitFromTray(),
          ),
        ],
      ),
    );
  }
}
