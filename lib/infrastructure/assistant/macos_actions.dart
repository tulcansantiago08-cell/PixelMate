import 'package:flutter/services.dart';

import '../../application/assistant/mac_actions.dart';

class MacosActions implements MacActions {
  static const _channel = MethodChannel('com.pixelmate/assistant');

  @override
  Future<String?> openApp(String name) async {
    try {
      return await _channel.invokeMethod<String>('openApp', name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openUrl(Uri url, {String? browser}) async {
    try {
      return await _channel.invokeMethod<bool>(
              'openUrl', {'url': url.toString(), 'browser': browser}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SavedCode?> saveCode(String fileName, String content,
      {String? editor}) async {
    final r = await _channel.invokeMethod<Map<Object?, Object?>>(
        'saveCode', {'name': fileName, 'content': content, 'editor': editor});
    if (r == null) return null;
    return SavedCode(
        r['path'] as String? ?? fileName, r['editor'] as String? ?? '');
  }

  @override
  Future<List<CalendarEvent>> events(int dayOffset) async {
    try {
      final list =
          await _channel.invokeMethod<List<Object?>>('events', dayOffset) ??
              const [];
      return [
        for (final raw in list)
          if (raw is Map)
            CalendarEvent(
              raw['title'] as String? ?? '',
              DateTime.fromMillisecondsSinceEpoch(
                  (raw['start'] as num).toInt()),
              DateTime.fromMillisecondsSinceEpoch((raw['end'] as num).toInt()),
              allDay: raw['allDay'] as bool? ?? false,
            )
      ];
    } on PlatformException catch (e) {
      if (e.code == 'denied') throw const CalendarDenied();
      rethrow;
    }
  }

  @override
  Future<void> createEvent(String title, DateTime start,
      {int minutes = 60}) async {
    try {
      await _channel.invokeMethod<bool>('createEvent', {
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'minutes': minutes,
      });
    } on PlatformException catch (e) {
      if (e.code == 'denied') throw const CalendarDenied();
      rethrow;
    }
  }
}
