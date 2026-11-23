import '../../core/i18n/language.dart';
import 'package:flutter/services.dart';

import '../../application/settings/backup.dart';

/// Diálogos "Guardar" y "Abrir" de macOS (ver `FileExport.swift`).
class MacosBackupFiles implements BackupFiles {
  static const _files = MethodChannel('com.pixelmate/files');
  static const _app = MethodChannel('com.pixelmate/app');

  @override
  Future<String?> save(String suggestedName, String content) =>
      _files.invokeMethod<String>('saveText', {
        'name': suggestedName,
        'content': content,
        'type': 'json',
        'title': tr('Guardar copia de seguridad', 'Save backup'),
      });

  @override
  Future<String?> open() => _files.invokeMethod<String>(
      'openText', {'title': tr('Restaurar copia de seguridad', 'Restore backup')});

  @override
  Future<void> relaunch() => _app.invokeMethod<void>('relaunch');
}
