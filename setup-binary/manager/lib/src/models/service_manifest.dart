/// describes one service managed by the app
class ManagedServiceSpec {
  const ManagedServiceSpec({
    required this.id,
    required this.type,
    required this.command,
    required this.arguments,
    required this.workingDirectory,
    required this.port,
    required this.healthUrl,
    required this.dependsOn,
  });

  final String id;
  final String type;
  final String command;
  final List<String> arguments;
  final String workingDirectory;
  final int port;
  final String healthUrl;
  final List<String> dependsOn;

  ManagedServiceSpec copyWith({
    String? command,
    List<String>? arguments,
    String? workingDirectory,
    int? port,
    String? healthUrl,
  }) {
    return ManagedServiceSpec(
      id: id,
      type: type,
      command: command ?? this.command,
      arguments: arguments ?? this.arguments,
      workingDirectory: workingDirectory ?? this.workingDirectory,
      port: port ?? this.port,
      healthUrl: healthUrl ?? this.healthUrl,
      dependsOn: dependsOn,
    );
  }
}

/// groups services that can be started by the manager
class ServiceManifest {
  const ServiceManifest({required this.services});

  final List<ManagedServiceSpec> services;

  ManagedServiceSpec byId(String id) {
    return services.firstWhere((service) => service.id == id);
  }

  static ServiceManifest defaultServices() {
    return const ServiceManifest(
      services: [
        ManagedServiceSpec(
          id: 'core',
          type: 'node',
          command: 'dist/server.js',
          arguments: [],
          workingDirectory: '.',
          port: 3000,
          healthUrl: 'http://localhost:3000/health',
          dependsOn: [],
        ),
        ManagedServiceSpec(
          id: 'frontend',
          type: 'npm',
          command: 'package.json',
          arguments: [],
          workingDirectory: 'ui/current',
          port: 5173,
          healthUrl: 'http://localhost:5173',
          dependsOn: ['core'],
        ),
      ],
    );
  }
}
