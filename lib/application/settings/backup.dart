import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qué guarda la copia de seguridad: tus tareas, recordatorios, tareas
/// diarias, calendario, alarmas, ajustes de la mascota y del minijuego.
/// (Las estadísticas de las jornadas están en otra base de datos.)
const backupPrefixes = [
  'assistant.',
  'daily.',
  'calendar.',
  'alarm.',
  'mascot.',
  'user.',
  'goal.',
  'game.',
  'detection.',
  'shortcut.',
  'sound.',
  'guard.enabled',
  'updates.enabled',
  'onboarding.',
];

/// Lo que no vale la pena copiar (cambia solo o es de este Mac).
bool _skip(String key) =>
    key.startsWith('mascot.bottomRight') || key == 'briefing.lastDay';

bool _included(String key) =>
    !_skip(key) && backupPrefixes.any((p) => key.startsWith(p));

/// La copia de seguridad como JSON.
String makeBackup(SharedPreferences prefs, DateTime now) {
  final data = <String, Object?>{};
  for (final key in prefs.getKeys().toList()..sort()) {
    if (!_included(key)) continue;
    final v = prefs.get(key);
    data[key] = switch (v) {
      bool() => {'bool': v},
      int() => {'int': v},
      double() => {'double': v},
      String() => {'string': v},
      List() => {'list': v.map((e) => '$e').toList()},
      _ => null,
    };
  }
  return const JsonEncoder.withIndent('  ').convert({
    'app': 'PixelMate',
    'backup': 1,
    'created': now.toIso8601String(),
    'data': data,
  });
}

/// "pixelmate-copia-2026-11-18.json".
String backupFileName(DateTime now) =>
    'pixelmate-copia-${now.year}-${now.month.toString().padLeft(2, '0')}-'
    '${now.day.toString().padLeft(2, '0')}.json';

/// Restaura una copia. Devuelve cuántos datos restauró. Lanza
/// [FormatException] si no es una copia de PixelMate.
Future<int> restoreBackup(SharedPreferences prefs, String json) async {
  final Object? root;
  try {
    root = jsonDecode(json);
  } on FormatException {
    throw const FormatException('No es un archivo de copia válido.');
  }
  if (root is! Map || root['app'] != 'PixelMate' || root['data'] is! Map) {
    throw const FormatException('No es una copia de PixelMate.');
  }
  var count = 0;
  for (final MapEntry(:key, :value) in (root['data'] as Map).entries) {
    if (key is! String || !_included(key) || value is! Map) continue;
    final ok = switch (value) {
      {'bool': final bool v} => await prefs.setBool(key, v),
      {'int': final int v} => await prefs.setInt(key, v),
      {'double': final num v} => await prefs.setDouble(key, v.toDouble()),
      {'string': final String v} => await prefs.setString(key, v),
      {'list': final List v} =>
        await prefs.setStringList(key, [for (final e in v) '$e']),
      _ => false,
    };
    if (ok) count++;
  }
  return count;
}

/// Guardar y abrir la copia (diálogos de macOS; ver `FileExport.swift`).
abstract class BackupFiles {
  /// Devuelve la ruta guardada o `null` si se canceló.
  Future<String?> save(String suggestedName, String content);

  /// El contenido del archivo elegido, o `null` si se canceló.
  Future<String?> open();

  /// Vuelve a abrir PixelMate (para cargar lo restaurado).
  Future<void> relaunch();
}

/// Para pruebas.
class MemoryBackupFiles implements BackupFiles {
  final Map<String, String> saved = {};
  String? toOpen;
  bool relaunched = false;

  @override
  Future<String?> save(String suggestedName, String content) async {
    saved[suggestedName] = content;
    return '/tmp/$suggestedName';
  }

  @override
  Future<String?> open() async => toOpen;

  @override
  Future<void> relaunch() async => relaunched = true;
}

/// Se sobrescriben en `main()`.
final backupFilesProvider = Provider<BackupFiles>((_) => MemoryBackupFiles());
final backupPrefsProvider = Provider<SharedPreferences?>((_) => null);
