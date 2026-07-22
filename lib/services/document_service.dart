import 'package:flutter/services.dart';

abstract final class DocumentService {
  static const _channel = MethodChannel('com.lyf.reading_app/documents');

  static Future<bool> saveText({
    required String name,
    required String content,
    required String mimeType,
  }) async =>
      await _channel.invokeMethod<bool>('saveText', {
        'name': name,
        'content': content,
        'mimeType': mimeType,
      }) ??
      false;

  static Future<String?> openBackup() =>
      _channel.invokeMethod<String>('openBackup');

  static Future<bool> saveBytes({
    required String name,
    required Uint8List content,
    required String mimeType,
  }) async =>
      await _channel.invokeMethod<bool>('saveBytes', {
        'name': name,
        'content': content,
        'mimeType': mimeType,
      }) ??
      false;

  static Future<Uint8List?> openBackupBytes() =>
      _channel.invokeMethod<Uint8List>('openBackupBytes');
}
