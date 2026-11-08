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
        title: notice.title,
        body: notice.body,
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
