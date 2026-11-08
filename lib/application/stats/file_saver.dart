import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Guardar un archivo donde elija el usuario.
abstract class FileSaver {
  /// Devuelve la ruta guardada o `null` si el usuario canceló.
  Future<String?> saveText(String suggestedName, String content);
}

/// Para pruebas: guarda en memoria.
class MemoryFileSaver implements FileSaver {
  final Map<String, String> files = {};
  bool cancel;
  MemoryFileSaver({this.cancel = false});

  @override
  Future<String?> saveText(String suggestedName, String content) async {
    if (cancel) return null;
    files[suggestedName] = content;
    return '/tmp/$suggestedName';
  }
}

/// Se sobrescribe en `main()` con el diálogo de macOS.
final fileSaverProvider = Provider<FileSaver>((_) => MemoryFileSaver());
