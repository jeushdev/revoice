import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() => runApp(const ReviseApp());

class ReviseApp extends StatelessWidget {
  const ReviseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E5AAC);
    return MaterialApp(
      title: 'ReVise',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
