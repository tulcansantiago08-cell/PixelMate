import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../application/workday/workday_notifications.dart';

/// Notificaciones del Centro de notificaciones de macOS.
class SystemNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  var _nextId = 0;
  var _ready = false;

  /// Pide permiso la primera vez. Si el usuario lo niega, la app sigue
  /// funcionando y la mascota avisa con su globo.
  Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(requestBadgePermission: false),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('No se pudieron activar las notificaciones: $e');
    }
  }

  Future<void> show(WorkdayNotice notice) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: _plain(notice.title),
        body: _plain(notice.body),
        notificationDetails: const NotificationDetails(
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('No se pudo mostrar la notificación: $e');
    }
  }
}

/// Las notificaciones de macOS, sin emojis (como el resto de la interfaz).
String _plain(String s) => s
    .replaceAll(
        RegExp(
            r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
            r'\u{231A}\u{231B}\u{23E9}-\u{23FA}\u{25B6}\u{25C0}\u{FE0F}'
            r'\u{200D}\u{20E3}]',
            unicode: true),
        '')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();
