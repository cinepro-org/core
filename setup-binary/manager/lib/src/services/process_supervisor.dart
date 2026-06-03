import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'log_service.dart';
import 'windows_job_object.dart';

/// stores one running managed process and the id used by the dashboard
class ServiceProcess {
  /// @param id service id such as core or frontend
  /// @param process dart process handle assigned to the windows job object
  ///
  /// keeps the service id attached to the native process handle
  ServiceProcess({required this.id, required this.process});

  final String id;
  final Process process;
}

/// describes a managed service lifecycle event emitted to the controller
class ServiceProcessEvent {
  /// @param id service id that changed state
  /// @param running whether the process is now running
  /// @param exit code exit code when the process has stopped
  /// @param stopped by manager whether stop all requested this shutdown
  ///
  /// creates a service event used for badges, logs, and notices
  const ServiceProcessEvent({
    required this.id,
    required this.running,
    this.exitCode,
    this.stoppedByManager = false,
  });

  final String id;
  final bool running;
  final int? exitCode;
  final bool stoppedByManager;
}

/// describes one stdout or stderr line emitted by a managed service
class ServiceProcessOutput {
  /// @param id service id that emitted the line
  /// @param line text emitted by stdout or stderr
  /// @param error whether the line came from stderr
  ///
  /// creates one process output event before it is written to manager logs
  const ServiceProcessOutput({
    required this.id,
    required this.line,
    required this.error,
  });

  final String id;
  final String line;
  final bool error;
}

/// starts and stops services owned by the manager and tracks external exits
class ProcessSupervisor {
  /// @param log manager log sink used for process lifecycle and output lines
  ///
  /// creates the supervisor and prepares the windows job object
  ProcessSupervisor({required this.log}) {
    _job.create();
  }

  final LogService log;
  final WindowsJobObject _job = WindowsJobObject();
  final Map<String, ServiceProcess> _processes = {};
  final Set<String> _stopping = {};
  final _events = StreamController<ServiceProcessEvent>.broadcast();
  final _outputs = StreamController<ServiceProcessOutput>.broadcast();

  bool get hasRunningServices => _processes.isNotEmpty;
  Stream<ServiceProcessEvent> get events => _events.stream;
  Stream<ServiceProcessOutput> get outputs => _outputs.stream;
  bool isRunning(String id) => _processes.containsKey(id);

  /// @param id service id used for logs, process tracking, and status events
  /// @param executable executable path or command to start
  /// @param arguments process arguments passed without manual string joining
  /// @param working directory folder used as the process cwd
  /// @param environment env values merged into the process environment
  /// @param run in shell true when windows command wrappers like npm.cmd need shell mode
  ///
  /// starts a managed service process and emits lifecycle events for the ui
  Future<void> start({
    required String id,
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    bool runInShell = false,
  }) async {
    if (_processes.containsKey(id)) {
      await log.write('$id is already running');
      return;
    }

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
    _job.assignPid(process.pid);
    _processes[id] = ServiceProcess(id: id, process: process);
    await log.write('$id started with pid ${process.pid}');
    _addEvent(ServiceProcessEvent(id: id, running: true));
    _pipeOutput(id, process);
    unawaited(
      process.exitCode.then((code) async {
        _processes.remove(id);
        final stoppedByManager = _stopping.remove(id);
        final message = stoppedByManager
            ? '$id stopped by manager with code $code'
            : '$id closed outside the manager with code $code';
        await log.write(message);
        _addEvent(
          ServiceProcessEvent(
            id: id,
            running: false,
            exitCode: code,
            stoppedByManager: stoppedByManager,
          ),
        );
      }),
    );
  }

  /// stops all services started by this manager before forcing remaining children
  Future<void> stopAll() async {
    final running = _processes.values.toList();
    for (final item in running) {
      await log.write('stopping ${item.id}');
      _stopping.add(item.id);
      item.process.kill();
    }

    await Future.wait(
      running.map(
        (item) => item.process.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () => -1,
        ),
      ),
    );

    for (final item in running) {
      if (_processes.containsKey(item.id) && Platform.isWindows) {
        await Process.run('taskkill', [
          '/pid',
          '${item.process.pid}',
          '/t',
          '/f',
        ]);
      }
    }
    _processes.clear();
  }

  /// closes the event stream and job object when the app exits
  Future<void> dispose() async {
    await stopAll();
    await _events.close();
    await _outputs.close();
    _job.close();
  }

  void _pipeOutput(String id, Process process) {
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleOutput(id: id, line: line, error: false));
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _handleOutput(id: id, line: line, error: true));
  }

  void _handleOutput({
    required String id,
    required String line,
    required bool error,
  }) {
    _addOutput(ServiceProcessOutput(id: id, line: line, error: error));
    final prefix = error ? '$id error' : id;
    unawaited(log.write('$prefix: $line'));
  }

  void _addEvent(ServiceProcessEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  void _addOutput(ServiceProcessOutput output) {
    if (_outputs.isClosed) return;
    _outputs.add(output);
  }
}
