import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/services/desktop_shell_service.dart';

/// starts the cinepro manager app
Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await DesktopShellService.instance.init();
  runApp(CineProManagerApp(startupArgs: arguments));
}
