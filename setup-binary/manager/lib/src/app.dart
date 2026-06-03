import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'manager_controller.dart';
import 'models/env_entry.dart';
import 'theme/cinepro_theme.dart';

/// hosts the cinepro manager material app with the shared theme and bootstrap
class CineProManagerApp extends StatelessWidget {
  /// @param startup args command line arguments forwarded by the windows runner
  ///
  /// creates the manager app and keeps setup launch intent available
  const CineProManagerApp({super.key, this.startupArgs = const []});

  final List<String> startupArgs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'cinepro manager',
      theme: CineProTheme.light(),
      home: ManagerBootstrap(startupArgs: startupArgs),
    );
  }
}

/// creates the controller before showing the dashboard shell
class ManagerBootstrap extends StatefulWidget {
  /// @param startup args command line arguments used for setup launch behavior
  ///
  /// creates the bootstrap shell that owns the manager controller lifecycle
  const ManagerBootstrap({super.key, this.startupArgs = const []});

  final List<String> startupArgs;

  @override
  State<ManagerBootstrap> createState() => _ManagerBootstrapState();
}

class _ManagerBootstrapState extends State<ManagerBootstrap> {
  late final Future<ManagerController> _controllerFuture;
  ManagerController? _controller;

  @override
  void initState() {
    super.initState();
    _controllerFuture = ManagerController.create(
      runSetupInstall: widget.startupArgs.contains('--setup-install'),
    ).then((controller) {
      _controller = controller;
      return controller;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ManagerController>(
      future: _controllerFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return ManagerHome(controller: snapshot.data!);
      },
    );
  }
}

/// renders the main responsive manager screen with animated logs and notices
class ManagerHome extends StatelessWidget {
  /// @param controller dashboard state and commands used by every panel
  ///
  /// creates the responsive manager layout for wide and narrow windows
  const ManagerHome({super.key, required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: _shortcutBindings(context),
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Stack(
                children: [
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 980;
                        final content = wide
                            ? _wideLayout(context, constraints)
                            : _narrowLayout(context);
                        return SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: content,
                          ),
                        );
                      },
                    ),
                  ),
                  _NoticeStack(controller: controller),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Map<ShortcutActivator, VoidCallback> _shortcutBindings(
    BuildContext context,
  ) {
    return {
      const SingleActivator(LogicalKeyboardKey.keyU, control: true): () {
        if (controller.busy) return;
        if (controller.coreUpdateReady) {
          controller.installOrUpdate();
        } else {
          controller.checkForUpdates();
        }
      },
      const SingleActivator(
        LogicalKeyboardKey.keyU,
        control: true,
        shift: true,
      ): () {
        if (controller.busy) return;
        if (controller.managerUpdateAvailable) {
          controller.updateManager();
        } else {
          controller.checkManagerUpdates();
        }
      },
      const SingleActivator(LogicalKeyboardKey.keyR, control: true): () {
        if (!controller.busy) controller.startCore();
      },
      const SingleActivator(
        LogicalKeyboardKey.keyS,
        control: true,
        shift: true,
      ): () {
        if (!controller.busy) controller.stopServices();
      },
      const SingleActivator(LogicalKeyboardKey.keyL, control: true): () {
        controller.toggleLogs();
      },
      const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
        if (controller.coreRunning) controller.openCore();
      },
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
        if (controller.frontendRunning) controller.openFrontend();
      },
      const SingleActivator(LogicalKeyboardKey.f1): () {
        _showShortcutsDialog(context);
      },
    };
  }

  Widget _wideLayout(BuildContext context, BoxConstraints constraints) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: controller.logsVisible ? 1 : 0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final maxWidth = constraints.maxWidth - 48;
        final closedMainWidth = maxWidth.clamp(0, 920).toDouble();
        final logsWidth = (maxWidth * 0.38).clamp(340, 560).toDouble();
        final spacing = 18 * value;
        final openMainWidth =
            (maxWidth - logsWidth - spacing).clamp(520, maxWidth).toDouble();
        final mainWidth = ui.lerpDouble(
          closedMainWidth,
          openMainWidth,
          value,
        )!;
        final startGap = ((maxWidth - closedMainWidth) / 2) * (1 - value);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: startGap),
            SizedBox(width: mainWidth, child: _mainColumn()),
            if (value > 0) SizedBox(width: spacing),
            if (value > 0)
              ClipRect(
                child: SizedBox(
                  width: logsWidth * value,
                  child: Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset((1 - value) * 24, 0),
                      child: _LogsPanel(controller: controller),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _mainColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(controller: controller),
        const SizedBox(height: 18),
        _InstallPanel(controller: controller),
        const SizedBox(height: 18),
        _ServicePanel(controller: controller),
        const SizedBox(height: 18),
        _RedisPanel(controller: controller),
        const SizedBox(height: 18),
        _EnvPanel(controller: controller),
        const SizedBox(height: 18),
        _DangerPanel(controller: controller),
      ],
    );
  }

  Widget _narrowLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _mainColumn(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: controller.logsVisible
              ? Padding(
                  key: const ValueKey('logs-visible'),
                  padding: const EdgeInsets.only(top: 18),
                  child: _LogsPanel(controller: controller),
                )
              : const SizedBox.shrink(key: ValueKey('logs-hidden')),
        ),
      ],
    );
  }
}

/// renders the logo, current manager status, and log toggle action
class _Header extends StatelessWidget {
  /// @param controller status text and log visibility command
  ///
  /// creates the app header used at the top of the dashboard
  const _Header({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset('assets/cinepro-logo.png', width: 48, height: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'cinepro manager',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: CineProTheme.ink,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                controller.status,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: CineProTheme.muted),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: controller.toggleLogs,
          child: Text(controller.logsVisible ? 'Hide Logs' : 'Logs'),
        ),
        const SizedBox(width: 8),
        _MoreMenu(controller: controller),
      ],
    );
  }
}

/// renders manager menu actions, update indicator, help, and language controls
class _MoreMenu extends StatelessWidget {
  /// @param controller menu state and native shell commands
  ///
  /// creates the three dot menu used for secondary manager controls
  const _MoreMenu({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      onSelected: (value) => _handleSelection(context, value),
      itemBuilder: (context) {
        return [
          const PopupMenuItem(
            enabled: false,
            value: 'version',
            child: Text('CinePro Manager 0.1.0'),
          ),
          PopupMenuItem(
            value: 'manager-update',
            enabled: !controller.busy,
            child: Text(
              controller.managerUpdateAvailable
                  ? 'Update Manager'
                  : 'Check Manager Updates',
            ),
          ),
          const PopupMenuItem(
            value: 'changelog',
            child: Text('Changelog'),
          ),
          const PopupMenuItem(
            value: 'bug',
            child: Text('Report Bug'),
          ),
          const PopupMenuItem(
            value: 'shortcuts',
            child: Text('Keyboard Shortcuts'),
          ),
          PopupMenuItem(
            value: 'language',
            child: Text('Language (${_titleCase(controller.languageName)})'),
          ),
          const PopupMenuItem(
            value: 'foundation',
            child: Text('About CinePro Foundation'),
          ),
        ];
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.more_vert),
          ),
          if (controller.managerUpdateAvailable)
            Positioned(
              top: 7,
              right: 8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: CineProTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleSelection(BuildContext context, String value) {
    if (value == 'manager-update') {
      if (controller.managerUpdateAvailable) {
        controller.updateManager();
      } else {
        controller.checkManagerUpdates();
      }
    }
    if (value == 'changelog') {
      controller.openChangelog();
    }
    if (value == 'bug') {
      controller.openBugReport();
    }
    if (value == 'shortcuts') {
      _showShortcutsDialog(context);
    }
    if (value == 'language') {
      _showLanguageDialog(context, controller);
    }
    if (value == 'foundation') {
      _showFoundationDialog(context, controller);
    }
  }
}

/// shows the windows only keyboard shortcut reference
void _showShortcutsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Keyboard Shortcuts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Windows only shortcuts for the manager window.'),
            SizedBox(height: 12),
            _ShortcutRow(
                keysText: 'Ctrl + U', action: 'Check or update CinePro'),
            _ShortcutRow(
                keysText: 'Ctrl + Shift + U',
                action: 'Check or update manager'),
            _ShortcutRow(keysText: 'Ctrl + R', action: 'Start CinePro'),
            _ShortcutRow(
                keysText: 'Ctrl + Shift + S', action: 'Stop all services'),
            _ShortcutRow(keysText: 'Ctrl + L', action: 'Toggle logs'),
            _ShortcutRow(keysText: 'Ctrl + B', action: 'Open backend'),
            _ShortcutRow(keysText: 'Ctrl + F', action: 'Open frontend'),
            _ShortcutRow(keysText: 'F1', action: 'Show shortcuts'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

/// shows the language picker used by the manager shell
void _showLanguageDialog(
  BuildContext context,
  ManagerViewController controller,
) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Language'),
        content: ListTile(
          leading: controller.languageName == 'english'
              ? const Icon(Icons.check, color: CineProTheme.accent)
              : const SizedBox(width: 24),
          title: const Text('English'),
          onTap: () {
            controller.changeLanguage('english');
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

/// shows cinepro foundation attribution and project links
void _showFoundationDialog(
  BuildContext context,
  ManagerViewController controller,
) {
  showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('CinePro Foundation'),
        content: const Text(
          'CinePro Foundation — The Home of Open-Source Streaming, Built by the Community for the Community\n\ncinepro manager 0.1.0',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              controller.openFoundation();
            },
            child: const Text('Open Foundation'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

/// renders one row inside the shortcut reference dialog
class _ShortcutRow extends StatelessWidget {
  /// @param keys text key combination shown on the left
  /// @param action text command shown on the right
  ///
  /// creates a compact shortcut row that keeps long actions readable
  const _ShortcutRow({required this.keysText, required this.action});

  final String keysText;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              keysText,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(action)),
        ],
      ),
    );
  }
}

/// renders manager folder, content folder, update check, and install actions
class _InstallPanel extends StatelessWidget {
  /// @param controller install roots, update lookup state, and install commands
  ///
  /// creates the install panel that separates setup location from content location
  const _InstallPanel({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    final lookup = controller.latestLookup;
    final frontend = controller.frontendLookup;
    final installedFrontendCommit = controller.installedFrontendCommit;
    final updateActionLabel =
        controller.coreUpdateReady ? 'Update CinePro' : 'Check Updates';
    return _Panel(
      title: 'Install And Updates',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey(controller.managerInstallDir),
            readOnly: true,
            initialValue: controller.managerInstallDir,
            decoration: const InputDecoration(
              labelText: 'Manager App Folder',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey(controller.selectedInstallRoot),
                  readOnly: true,
                  initialValue: controller.selectedInstallRoot,
                  decoration: const InputDecoration(
                    labelText: 'CinePro Content Folder',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed:
                    controller.busy ? null : controller.chooseInstallFolder,
                child: const Text('Browse'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lookup?.ready == true)
            Text(
              'Ready to install ${lookup!.manifest!.tag}',
              style: const TextStyle(color: CineProTheme.ink),
            ),
          if (frontend?.ready == true) ...[
            const SizedBox(height: 8),
            Text(
              'UI main ${_shortCommit(frontend!.snapshot!.commit)} is available',
              style: const TextStyle(color: CineProTheme.ink),
            ),
          ],
          if (installedFrontendCommit != null) ...[
            const SizedBox(height: 8),
            Text(
              'installed ui ${_shortCommit(installedFrontendCommit)}',
              style: const TextStyle(color: CineProTheme.muted),
            ),
          ],
          if (lookup != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: controller.openChangelog,
                child: const Text('View Changelog'),
              ),
            ),
          ],
          if (controller.busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: controller.progress == 0 ? null : controller.progress,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: controller.busy
                    ? null
                    : controller.coreUpdateReady
                        ? controller.installOrUpdate
                        : controller.checkForUpdates,
                child: Text(updateActionLabel),
              ),
              FilledButton(
                onPressed: controller.busy ? null : controller.installOrUpdate,
                child: const Text('Install Or Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// renders backend and frontend service status plus launch actions
class _ServicePanel extends StatelessWidget {
  /// @param controller service status, start stop commands, and browser open commands
  ///
  /// creates the service panel with accessible open menu items
  const _ServicePanel({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Services',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusBadge(
                label: 'Backend',
                active: controller.coreRunning,
              ),
              _StatusBadge(
                label: 'Frontend',
                active: controller.frontendRunning,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: controller.busy ? null : controller.startCore,
                child: const Text('Start CinePro'),
              ),
              OutlinedButton(
                onPressed: controller.busy ? null : controller.stopServices,
                child: const Text('Stop All'),
              ),
              OutlinedButton(
                onPressed: controller.busy ? null : controller.checkHealth,
                child: const Text('Health'),
              ),
              _OpenServiceMenu(controller: controller),
            ],
          ),
        ],
      ),
    );
  }
}

/// renders docker detection and managed redis cache controls
class _RedisPanel extends StatelessWidget {
  /// @param controller docker state and redis action commands
  ///
  /// creates the redis panel without assuming docker exists
  const _RedisPanel({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.dockerStatus;
    final redisRunning = status?.redisRunning ?? false;
    return _Panel(
      title: 'Redis Cache',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              status?.summary ?? 'Check Docker before starting Redis.',
              key: ValueKey(status?.summary ?? 'not-checked'),
              style: const TextStyle(color: CineProTheme.muted),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusBadge(label: 'Docker', active: status?.ready ?? false),
              _StatusBadge(label: 'Redis', active: redisRunning),
              if (status?.desktopDetected == true)
                const _SoftBadge(label: 'Docker Desktop'),
              if (status?.composeAvailable == true)
                const _SoftBadge(label: 'Compose'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: controller.busy ? null : controller.checkDocker,
                child: const Text('Check Docker'),
              ),
              FilledButton(
                onPressed: controller.busy ? null : controller.startRedis,
                child: const Text('Start Redis'),
              ),
              OutlinedButton(
                onPressed: controller.busy ? null : controller.stopRedis,
                child: const Text('Stop Redis'),
              ),
              OutlinedButton(
                onPressed: controller.busy ? null : controller.clearRedis,
                child: const Text('Clear Redis Cache'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// renders the open service menu for backend and frontend browser links
class _OpenServiceMenu extends StatelessWidget {
  /// @param controller running state and urls for the backend and frontend
  ///
  /// creates a keyboard accessible menu for opening active services
  const _OpenServiceMenu({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.coreRunning || controller.frontendRunning;
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: 'Open service',
      onSelected: (value) {
        if (value == 'core') {
          controller.openCore();
        }
        if (value == 'frontend') {
          controller.openFrontend();
        }
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: 'core',
            enabled: controller.coreRunning,
            child: Text('Open Backend (${controller.coreUrl})'),
          ),
          PopupMenuItem(
            value: 'frontend',
            enabled: controller.frontendRunning,
            child: Text('Open Frontend (${controller.frontendUrl})'),
          ),
        ];
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: enabled ? CineProTheme.line : const Color(0xffeeeeee),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Text(
            'Open',
            style: TextStyle(
              color: enabled ? CineProTheme.ink : const Color(0xffaaaaaa),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// renders an animated running state badge for a service or dependency
class _StatusBadge extends StatelessWidget {
  /// @param label short service or dependency name shown in the badge
  /// @param active whether the badge should render as on or off
  ///
  /// creates a compact state badge with restrained cinepro accent styling
  const _StatusBadge({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x11f30f17) : const Color(0xfff5f5f5),
        border: Border.all(
          color: active ? CineProTheme.accent : CineProTheme.line,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label ${active ? 'On' : 'Off'}',
        style: TextStyle(
          color: active ? CineProTheme.accent : CineProTheme.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// renders a neutral capability badge for optional docker features
class _SoftBadge extends StatelessWidget {
  /// @param label capability text shown inside the badge
  ///
  /// creates a small neutral badge that does not look like an action
  const _SoftBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xfff7f7f7),
        border: Border.all(color: CineProTheme.line),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: CineProTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// renders the env editor from installed core values and required key hints
class _EnvPanel extends StatelessWidget {
  /// @param controller env entries and save command
  ///
  /// creates the environment panel after core files are installed
  const _EnvPanel({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.envEntries;
    return _Panel(
      title: 'Environment',
      child: entries.isEmpty
          ? const Text(
              'Install CinePro Core before editing environment values.')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  _EnvField(controller: controller, entry: entry),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: controller.busy ? null : controller.saveEnv,
                    child: const Text('Save Env'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// renders one editable env value with secret field handling
class _EnvField extends StatelessWidget {
  /// @param controller in memory env update command
  /// @param entry env entry metadata and current value
  ///
  /// creates a text field bound to one env entry
  const _EnvField({required this.controller, required this.entry});

  final ManagerViewController controller;
  final EnvEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        initialValue: entry.value,
        obscureText: entry.secret,
        onChanged: (value) => controller.updateEnv(entry.key, value),
        decoration: InputDecoration(
          labelText: entry.required ? '${entry.key} required' : entry.key,
          helperText: entry.description,
        ),
      ),
    );
  }
}

/// renders recent manager logs and the clear logs action
class _LogsPanel extends StatelessWidget {
  /// @param controller log lines and clear logs command
  ///
  /// creates the log panel that stays hidden until requested or activity starts
  const _LogsPanel({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Logs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff101010),
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              controller.logLines.isEmpty
                  ? 'logs will appear here after an action runs.'
                  : controller.logLines.join('\n'),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Consolas',
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: controller.busy ? null : controller.clearLogs,
              child: const Text('Clear Logs'),
            ),
          ),
        ],
      ),
    );
  }
}

/// renders uninstall actions and confirmation for manager owned files
class _DangerPanel extends StatelessWidget {
  /// @param controller uninstall command and busy state
  ///
  /// creates the uninstall panel with explicit core and log cleanup choices
  const _DangerPanel({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Uninstall',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remove managed CinePro files or detach this manager from the install.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed:
                controller.busy ? null : () => _confirmUninstall(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: CineProTheme.accent,
              side: const BorderSide(color: CineProTheme.accent),
            ),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUninstall(BuildContext context) async {
    var removeCore = true;
    var removeLogs = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Uninstall CinePro'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The manager will stop running services first. Core files are only removed when this folder is marked as a managed install.',
                  ),
                  CheckboxListTile(
                    value: removeCore,
                    onChanged: (value) =>
                        setState(() => removeCore = value ?? true),
                    title: const Text('Remove Managed Core Files'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: removeLogs,
                    onChanged: (value) =>
                        setState(() => removeLogs = value ?? false),
                    title: const Text('Remove Logs'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Uninstall'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed == true) {
      await controller.uninstall(
        removeCore: removeCore,
        removeLogs: removeLogs,
      );
    }
  }
}

/// renders closable dashboard notices above the main scroll area
class _NoticeStack extends StatelessWidget {
  /// @param controller active notices and dismiss command
  ///
  /// creates the floating notice stack without blocking the dashboard when empty
  const _NoticeStack({required this.controller});

  final ManagerViewController controller;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 18,
      right: 18,
      child: IgnorePointer(
        ignoring: controller.notices.isEmpty,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: controller.notices.isEmpty
              ? const SizedBox.shrink(key: ValueKey('empty-notices'))
              : ConstrainedBox(
                  key: ValueKey(controller.notices.length),
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final notice in controller.notices)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _NoticeCard(
                            notice: notice,
                            onClose: () => controller.dismissNotice(notice.id),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// renders one notice card with a close button
class _NoticeCard extends StatelessWidget {
  /// @param notice notice text and ids shown in the card
  /// @param on close callback fired by the close button
  ///
  /// creates one animated toast style notice
  const _NoticeCard({required this.notice, required this.onClose});

  final ManagerNotice notice;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset((1 - value) * 18, 0),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.white,
        elevation: 10,
        shadowColor: const Color(0x22000000),
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x22f30f17)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        notice.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: CineProTheme.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notice.message,
                        style: const TextStyle(color: CineProTheme.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// renders a bordered content group with consistent spacing and title styling
class _Panel extends StatelessWidget {
  /// @param title visible section title
  /// @param child section content rendered below the title
  ///
  /// creates the shared panel frame used by dashboard sections
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: CineProTheme.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

String _shortCommit(String commit) {
  return commit.length <= 7 ? commit : commit.substring(0, 7);
}

String _titleCase(String value) {
  return value
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
