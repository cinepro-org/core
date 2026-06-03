import 'dart:async';
import 'dart:io';

/// describes the local docker and redis state found by the manager
class DockerStatus {
  /// @param cli found whether docker is available from the current process path
  /// @param daemon running whether docker info can talk to the daemon
  /// @param desktop detected whether docker desktop is visible in windows processes
  /// @param service detected whether the windows docker service exists
  /// @param service running whether the windows docker service is running
  /// @param compose available whether docker compose is available
  /// @param redis container exists whether the managed redis container exists
  /// @param redis running whether the managed redis container is running
  /// @param redis port busy whether port 6379 is occupied by something else
  /// @param summary short user facing state message
  ///
  /// stores all docker checks needed before redis actions can run
  const DockerStatus({
    required this.cliFound,
    required this.daemonRunning,
    required this.desktopDetected,
    required this.serviceDetected,
    required this.serviceRunning,
    required this.composeAvailable,
    required this.redisContainerExists,
    required this.redisRunning,
    required this.redisPortBusy,
    required this.summary,
  });

  final bool cliFound;
  final bool daemonRunning;
  final bool desktopDetected;
  final bool serviceDetected;
  final bool serviceRunning;
  final bool composeAvailable;
  final bool redisContainerExists;
  final bool redisRunning;
  final bool redisPortBusy;
  final String summary;

  bool get ready => cliFound && daemonRunning;
}

/// runs docker checks and manages the redis cache container with guarded commands
class DockerService {
  const DockerService();

  static const redisContainerName = 'cinepro-redis';
  static const redisImage = 'redis:7-alpine';
  static const redisPort = 6379;

  /// checks docker through cli, daemon, service, process, port, and container state
  Future<DockerStatus> check() async {
    final cliFound = await _commandExists('docker');
    final desktopDetected = Platform.isWindows &&
        await _isProcessRunning(
          'Docker Desktop.exe',
        );
    final serviceState = Platform.isWindows
        ? await _windowsServiceState('com.docker.service')
        : null;
    final serviceDetected = serviceState != null;
    final serviceRunning = serviceState == 'RUNNING';

    if (!cliFound) {
      return DockerStatus(
        cliFound: false,
        daemonRunning: false,
        desktopDetected: desktopDetected,
        serviceDetected: serviceDetected,
        serviceRunning: serviceRunning,
        composeAvailable: false,
        redisContainerExists: false,
        redisRunning: false,
        redisPortBusy: await _isPortBusy(redisPort),
        summary: 'docker cli was not found',
      );
    }

    final daemonRunning = (await _runDocker(['info'])).exitCode == 0;
    final composeAvailable =
        (await _runDocker(['compose', 'version'])).exitCode == 0;
    final redisState = daemonRunning
        ? await _redisState()
        : const _RedisState(exists: false, running: false);
    final portBusy = await _isPortBusy(redisPort);

    return DockerStatus(
      cliFound: cliFound,
      daemonRunning: daemonRunning,
      desktopDetected: desktopDetected,
      serviceDetected: serviceDetected,
      serviceRunning: serviceRunning,
      composeAvailable: composeAvailable,
      redisContainerExists: redisState.exists,
      redisRunning: redisState.running,
      redisPortBusy: portBusy && !redisState.running,
      summary: _summary(
        cliFound: cliFound,
        daemonRunning: daemonRunning,
        desktopDetected: desktopDetected,
        serviceDetected: serviceDetected,
        serviceRunning: serviceRunning,
        redisExists: redisState.exists,
        redisRunning: redisState.running,
        portBusy: portBusy && !redisState.running,
      ),
    );
  }

  /// starts the managed redis container or reuses it when it already exists
  Future<void> startRedis() async {
    final status = await check();
    if (!status.cliFound) {
      throw StateError('docker cli was not found');
    }
    if (!status.daemonRunning) {
      throw StateError('docker daemon is not running');
    }
    if (status.redisRunning) {
      return;
    }
    if (status.redisPortBusy) {
      throw StateError('port 6379 is already in use');
    }
    if (status.redisContainerExists) {
      final started = await _runDocker(['start', redisContainerName]);
      _throwOnFailure(started, 'redis container could not start');
      return;
    }

    final created = await _runDocker([
      'run',
      '-d',
      '--name',
      redisContainerName,
      '-p',
      '$redisPort:6379',
      redisImage,
    ]);
    _throwOnFailure(created, 'redis container could not be created');
  }

  /// stops the managed redis container if docker is ready and the container exists
  Future<void> stopRedis() async {
    final status = await check();
    if (!status.ready || !status.redisContainerExists) {
      return;
    }
    final stopped = await _runDocker(['stop', redisContainerName]);
    _throwOnFailure(stopped, 'redis container could not stop');
  }

  /// clears the managed redis cache without removing or recreating the container
  Future<void> clearRedis() async {
    final status = await check();
    if (!status.ready) {
      throw StateError('docker is not ready');
    }
    if (!status.redisRunning) {
      throw StateError('redis is not running');
    }
    final cleared = await _runDocker([
      'exec',
      redisContainerName,
      'redis-cli',
      'FLUSHDB',
    ]);
    _throwOnFailure(cleared, 'redis cache could not be cleared');
  }

  Future<bool> _commandExists(String command) async {
    final check = Platform.isWindows
        ? await _run('where', [command])
        : await _run('which', [command]);
    return check.exitCode == 0;
  }

  Future<_CommandResult> _runDocker(List<String> arguments) {
    return _run('docker', arguments, timeout: const Duration(seconds: 12));
  }

  Future<_RedisState> _redisState() async {
    final result = await _runDocker([
      'inspect',
      '-f',
      '{{.State.Running}}',
      redisContainerName,
    ]);
    if (result.exitCode != 0) {
      return const _RedisState(exists: false, running: false);
    }
    return _RedisState(
      exists: true,
      running: result.stdout.trim().toLowerCase() == 'true',
    );
  }

  Future<bool> _isProcessRunning(String imageName) async {
    final result = await _run('tasklist', [
      '/FI',
      'IMAGENAME eq $imageName',
      '/NH',
    ]);
    return result.exitCode == 0 &&
        result.stdout.toLowerCase().contains(imageName.toLowerCase());
  }

  Future<String?> _windowsServiceState(String serviceName) async {
    final result = await _run('sc', ['query', serviceName]);
    if (result.exitCode != 0) return null;
    final match = RegExp(r'STATE\s+:\s+\d+\s+(\w+)').firstMatch(
      result.stdout,
    );
    return match?.group(1);
  }

  Future<bool> _isPortBusy(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return false;
    } on SocketException {
      return true;
    }
  }

  Future<_CommandResult> _run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: Platform.isWindows,
      ).timeout(timeout);
      return _CommandResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    } on Object catch (error) {
      return _CommandResult(exitCode: -1, stdout: '', stderr: '$error');
    }
  }

  void _throwOnFailure(_CommandResult result, String message) {
    if (result.exitCode == 0) return;
    final detail = result.stderr.trim().isEmpty
        ? result.stdout.trim()
        : result.stderr.trim();
    throw StateError(detail.isEmpty ? message : '$message: $detail');
  }

  String _summary({
    required bool cliFound,
    required bool daemonRunning,
    required bool desktopDetected,
    required bool serviceDetected,
    required bool serviceRunning,
    required bool redisExists,
    required bool redisRunning,
    required bool portBusy,
  }) {
    if (!cliFound) return 'docker cli was not found';
    if (!daemonRunning && desktopDetected) {
      return 'docker desktop was found, but the daemon is not ready';
    }
    if (!daemonRunning && serviceDetected && !serviceRunning) {
      return 'docker service exists but is not running';
    }
    if (!daemonRunning) return 'docker daemon is not running';
    if (redisRunning) return 'redis is running in docker';
    if (redisExists) return 'redis container exists but is stopped';
    if (portBusy) return 'port 6379 is already used by another app';
    return 'docker is ready for redis';
  }
}

class _RedisState {
  const _RedisState({required this.exists, required this.running});

  final bool exists;
  final bool running;
}

class _CommandResult {
  const _CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}
