import 'dart:convert';

/// describes the current install transaction
enum InstallOperation {
  idle,
  installing,
  updating,
  rollingBack,
  uninstalling,
  completed,
  failed,
}

/// describes the current install transaction phase
enum InstallPhase {
  none,
  checking,
  downloading,
  verifying,
  extracting,
  validating,
  installingRuntime,
  swapping,
  starting,
  stopping,
  cleaning,
  completed,
  failed,
}

/// persists install and update recovery data used after crashes or restarts
class InstallState {
  /// @param operation current top level install operation
  /// @param phase current phase inside the operation
  /// @param install path managed content folder involved in the operation
  /// @param current tag installed core release tag after completion
  /// @param target tag release tag or ui marker currently being installed
  /// @param staging path optional staging path kept for future diagnostics
  /// @param backup path optional backup path kept for future diagnostics
  /// @param started at operation start timestamp
  /// @param updated at last state write timestamp
  /// @param message user visible status message persisted with the state
  ///
  /// creates a durable transaction state written through state store
  const InstallState({
    required this.operation,
    required this.phase,
    this.installPath,
    this.currentTag,
    this.targetTag,
    this.stagingPath,
    this.backupPath,
    this.startedAt,
    this.updatedAt,
    this.message,
  });

  factory InstallState.idle() {
    return const InstallState(
      operation: InstallOperation.idle,
      phase: InstallPhase.none,
    );
  }

  factory InstallState.fromJson(Map<String, Object?> json) {
    return InstallState(
      operation: _enumByName(
        InstallOperation.values,
        json['operation'] as String?,
        InstallOperation.idle,
      ),
      phase: _enumByName(
        InstallPhase.values,
        json['phase'] as String?,
        InstallPhase.none,
      ),
      installPath: json['installPath'] as String?,
      currentTag: json['currentTag'] as String?,
      targetTag: json['targetTag'] as String?,
      stagingPath: json['stagingPath'] as String?,
      backupPath: json['backupPath'] as String?,
      startedAt: _date(json['startedAt']),
      updatedAt: _date(json['updatedAt']),
      message: json['message'] as String?,
    );
  }

  final InstallOperation operation;
  final InstallPhase phase;
  final String? installPath;
  final String? currentTag;
  final String? targetTag;
  final String? stagingPath;
  final String? backupPath;
  final DateTime? startedAt;
  final DateTime? updatedAt;
  final String? message;

  bool get hasUnfinishedWork {
    return operation != InstallOperation.idle &&
        operation != InstallOperation.completed &&
        operation != InstallOperation.failed;
  }

  InstallState copyWith({
    InstallOperation? operation,
    InstallPhase? phase,
    String? installPath,
    String? currentTag,
    String? targetTag,
    String? stagingPath,
    String? backupPath,
    DateTime? startedAt,
    DateTime? updatedAt,
    String? message,
  }) {
    return InstallState(
      operation: operation ?? this.operation,
      phase: phase ?? this.phase,
      installPath: installPath ?? this.installPath,
      currentTag: currentTag ?? this.currentTag,
      targetTag: targetTag ?? this.targetTag,
      stagingPath: stagingPath ?? this.stagingPath,
      backupPath: backupPath ?? this.backupPath,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      message: message ?? this.message,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'operation': operation.name,
      'phase': phase.name,
      'installPath': installPath,
      'currentTag': currentTag,
      'targetTag': targetTag,
      'stagingPath': stagingPath,
      'backupPath': backupPath,
      'startedAt': startedAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'message': message,
    };
  }

  String encode() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  static DateTime? _date(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    if (name == null) return fallback;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }
}
