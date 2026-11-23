import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../../application/settings/backup.dart';
import '../../application/stats/file_saver.dart';
import '../../core/i18n/language.dart';

/// Guardar un texto con el diálogo del sistema (Windows y Linux).
class PortableFileSaver implements FileSaver {
  @override
  Future<String?> saveText(String suggestedName, String content) =>
      saveWithDialog(suggestedName, content);
}

/// Copias de seguridad con los diálogos del sistema (Windows y Linux).
class PortableBackupFiles implements BackupFiles {
  @override
  Future<String?> save(String suggestedName, String content) =>
      saveWithDialog(suggestedName, content,
          type: const XTypeGroup(label: 'JSON', extensions: ['json']),
          title: tr('Guardar copia de seguridad', 'Save backup'));

  @override
  Future<String?> open() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
      confirmButtonText: tr('Restaurar', 'Restore'),
    );
    return file?.readAsString();
  }

  /// Vuelve a abrir la app para cargar los datos restaurados.
  @override
  Future<void> relaunch() async {
    await Process.start(Platform.resolvedExecutable, const [],
        mode: ProcessStartMode.detached);
    exit(0);
  }
}

/// Pregunta dónde guardar y escribe el archivo. Su ruta, o `null` si se
/// canceló.
Future<String?> saveWithDialog(String suggestedName, String content,
    {XTypeGroup? type, String? title}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    acceptedTypeGroups: [if (type != null) type],
    confirmButtonText: title,
  );
  if (location == null) return null;
  await File(location.path).writeAsString(content);
  return location.path;
}
