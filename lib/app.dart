/// The app widget: theme and the single home screen.
library;

import 'package:flutter/material.dart';

import 'app_state.dart';
import 'open_url.dart';
import 'screens/todos_screen.dart';

class TodosApp extends StatelessWidget {
  const TodosApp({super.key, required this.state, required this.openUrl});

  final AppState state;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Todos API sample | SimpleAPI',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF0066CC),
        useMaterial3: true,
        // A slightly smaller title so "SimpleAPI Todos" never truncates at 360px wide.
        appBarTheme: const AppBarTheme(titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
      ),
      // The app opens straight on content.
      home: TodosScreen(state: state, openUrl: openUrl),
    );
  }
}
