import 'package:flutter/services.dart';

class PickedLocalFile {
  const PickedLocalFile({
    required this.name,
    required this.bytes,
    this.coverBytes,
  });

  final String name;
  final Uint8List bytes;
  final Uint8List? coverBytes;
}

abstract final class LocalFilePicker {
  static const _channel = MethodChannel('com.lyf.reading_app/file_picker');

  static Future<PickedLocalFile?> pick({required bool coverImage}) async {
    final value = await _channel.invokeMapMethod<String, Object?>('pickFile', {
      'coverImage': coverImage,
    });
    if (value == null) return null;
    final name = value['name'];
    final bytes = value['bytes'];
    final coverBytes = value['coverBytes'];
    if (name is! String || bytes is! Uint8List || bytes.isEmpty) return null;
    return PickedLocalFile(
      name: name,
      bytes: bytes,
      coverBytes: coverBytes is Uint8List && coverBytes.isNotEmpty
          ? coverBytes
          : null,
    );
  }
}
