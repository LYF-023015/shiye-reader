import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

abstract final class DiagnosticsService {
  static File? _logFile;

  static Future<void> initialize() async {
    final directory = await getApplicationSupportDirectory();
    _logFile = File(
      '${directory.path}${Platform.pathSeparator}shiye-errors.log',
    );
    final file = _logFile!;
    if (await file.exists() && await file.length() > 512 * 1024) {
      await file.writeAsString('');
    }
  }

  static Future<void> record(Object error, StackTrace stackTrace) async {
    final file = _logFile;
    if (file == null) return;
    try {
      await file.writeAsString(
        '[${DateTime.now().toIso8601String()}] $error\n$stackTrace\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException catch (writeError) {
      debugPrint('Could not write diagnostics: $writeError');
    }
  }
}
