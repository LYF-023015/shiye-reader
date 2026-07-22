import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'services/diagnostics_service.dart';
import 'services/reading_store.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DiagnosticsService.initialize();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      DiagnosticsService.record(
        details.exception,
        details.stack ?? StackTrace.current,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(DiagnosticsService.record(error, stack));
    return true;
  };
  runZonedGuarded(
    () => runApp(const ReadingApp()),
    (error, stack) => unawaited(DiagnosticsService.record(error, stack)),
  );
}

class ReadingApp extends StatefulWidget {
  const ReadingApp({super.key});

  @override
  State<ReadingApp> createState() => _ReadingAppState();
}

class _ReadingAppState extends State<ReadingApp> {
  final ReadingStore _readingStore = ReadingStore();

  @override
  void initState() {
    super.initState();
    _readingStore.initialize();
  }

  @override
  void dispose() {
    _readingStore.flush();
    _readingStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _readingStore,
      builder: (context, _) {
        return MaterialApp(
          title: '拾页',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _readingStore.readerPreferences.themeMode,
          home: HomeShell(readingStore: _readingStore),
        );
      },
    );
  }
}
