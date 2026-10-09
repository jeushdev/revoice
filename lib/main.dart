import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_state.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Only Live captions rotates (it unlocks landscape itself).
  SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  runApp(ReviseApp(app: AppState()));
}

class ReviseApp extends StatelessWidget {
  const ReviseApp({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      app: app,
      child: MaterialApp(
        title: 'ReVise',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const HomeShell(),
      ),
    );
  }
}
