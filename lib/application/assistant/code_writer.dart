import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command_parser.dart';

/// Escribe código a partir de una descripción (con la IA del Mac).
abstract class CodeWriter {
  /// `null` si no hay IA disponible o falló.
  Future<String?> write(String language, String description);
}

/// Quita los bloques ``` que a veces añade la IA y los espacios de más.
String cleanCode(String raw) {
  final fenced = RegExp(r'```[\w+#-]*\s*\n([\s\S]*?)```').firstMatch(raw);
  final code = (fenced?.group(1) ?? raw).trim();
  return '$code\n';
}

/// "sumar" → "sumar.py"; "pida dos números y los multiplique" →
/// "pida_dos_numeros.py".
String codeFileName(String description, String language) {
  final words = fold(description)
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(RegExp(r'\s+'))
      .where((w) =>
          w.isNotEmpty &&
          !const {'el', 'la', 'los', 'las', 'un', 'una', 'de', 'y'}.contains(w))
      .take(3)
      .toList();
  final base = words.isEmpty ? 'script' : words.join('_');
  return '$base.${codeLanguages[language] ?? 'txt'}';
}

/// Para pruebas.
class FakeCodeWriter implements CodeWriter {
  final String? code;
  final List<String> asked = [];
  FakeCodeWriter([this.code = 'print(1 + 2)']);

  @override
  Future<String?> write(String language, String description) async {
    asked.add('$language: $description');
    return code;
  }
}

/// Se sobrescribe en `main()` con la IA de Apple.
final codeWriterProvider = Provider<CodeWriter>((_) => FakeCodeWriter(null));
