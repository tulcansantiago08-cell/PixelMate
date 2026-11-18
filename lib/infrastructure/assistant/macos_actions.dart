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
  Future<String?> closeApp(String name) async {
    try {
      return await _channel.invokeMethod<String>('closeApp', name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> hideApp(String name) async {
    try {
      return await _channel.invokeMethod<String>('hideApp', name);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> runningApps() async {
    try {
      return (await _channel.invokeListMethod<String>('runningApps')) ?? [];
    } catch (_) {
      return [];
    }
  }

  @override
  Future<MediaResult> media(String action, {String? player}) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>(
          'media', {'action': action, 'player': player});
      return (
        player: r?['player'] as String?,
        track: r?['track'] as String?,
        error: r == null ? 'failed' : r['error'] as String?,
      );
    } catch (_) {
      return (player: null, track: null, error: 'failed');
    }
  }

  @override
  Future<VolumeLevel?> volume(String action, [int value = 0]) async {
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>(
          'volume', {'action': action, 'value': value});
      if (r == null) return null;
      return (level: (r['level'] as int?) ?? 0, muted: r['muted'] == true);
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
              id: raw['id'] as String? ?? '',
            )
      ];
    } on PlatformException catch (e) {
      if (e.code == 'denied') throw const CalendarDenied();
      rethrow;
    }
  }

  @override
  Future<String?> createEvent(String title, DateTime start,
      {int minutes = 60,
      bool allDay = false,
      int? alert,
      String? repeat}) async {
    try {
      final id = await _channel.invokeMethod<Object?>('createEvent', {
        'title': title,
        'start': start.millisecondsSinceEpoch,
        'minutes': minutes,
        'allDay': allDay,
        if (alert != null) 'alert': alert,
        if (repeat != null) 'repeat': repeat,
      });
      return id is String && id.isNotEmpty ? id : null;
    } on PlatformException catch (e) {
      if (e.code == 'denied') throw const CalendarDenied();
      rethrow;
    }
  }

  @override
  Future<bool> deleteEvent(String id) async {
    try {
      return await _channel.invokeMethod<bool>('deleteEvent', id) ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'denied') throw const CalendarDenied();
      rethrow;
    }
  }
}
