import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/activity/detectable_app.dart';

/// Cambios de app en primer plano, desde `AppActivityMonitor.swift`.
class MacosAppActivity {
  static const _channel = EventChannel('com.pixelmate/app_activity');

  Stream<ForegroundApp> get foregroundApps => _channel
      .receiveBroadcastStream()
      .map((e) => ForegroundApp.fromMap(e as Map<Object?, Object?>));
}

/// Carga el catálogo incluido en la app y, si existe, el del usuario.
Future<AppCatalog> loadAppCatalog({String? userFilePath}) async {
  final bundled = AppCatalog.parse(jsonDecode(
          await rootBundle.loadString('assets/config/detectable_apps.json'))
      as Map<String, dynamic>);
  if (userFilePath == null) return bundled;

  final file = File(userFilePath);
  if (!await file.exists()) return bundled;
  try {
    final user = AppCatalog.parse(
      jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      onInvalid: (e) => debugPrint('Entrada inválida en $userFilePath: $e'),
    );
    return bundled.withUserApps(user);
  } catch (e) {
    debugPrint('No se pudo leer $userFilePath: $e');
    return bundled;
  }
}
