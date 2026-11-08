import 'package:flutter/services.dart';

import '../../application/stats/file_saver.dart';

/// Diálogo "Guardar" de macOS (ver `FileExport.swift`).
class MacosFileSaver implements FileSaver {
  static const _channel = MethodChannel('com.pixelmate/files');

  @override
  Future<String?> saveText(String suggestedName, String content) =>
      _channel.invokeMethod<String>(
          'saveText', {'name': suggestedName, 'content': content});
}
