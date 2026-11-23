import '../../core/i18n/language.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mac_actions.dart';
import 'personal_store.dart';

/// Tus pendientes también en la app Recordatorios de Apple (y, por iCloud,
/// en el iPhone), si lo activas:
///
/// - Lo que apuntas en PixelMate (tareas y recordatorios con hora) se crea
///   allí; tachar o borrar aquí lo tacha o borra allí.
/// - Si lo marcas como hecho en el iPhone, aquí se tacha.
///
/// Los recordatorios con hora llevan su fecha pero sin aviso propio: el
/// aviso lo da PixelMate, para no sonar dos veces en el Mac.
class AppleRemindersSync extends ChangeNotifier {
  static const _onKey = 'apple.reminders';
  static const _linksKey = 'apple.reminders.links';

  final PersonalStore store;
  final MacActions mac;
  final SharedPreferences? _prefs;

  /// id de PixelMate ("task:…" o "rem:…") → id en Recordatorios.
  final Map<String, String> _links;

  /// Lo hecho que ya se mandó (id de tarea → hecho).
  final Map<String, bool> _sentDone = {};
  bool _enabled;
  bool _busy = false;
  bool _again = false;

  /// Por qué no se pudo (por ejemplo, sin permiso), o `null`.
  String? problem;

  AppleRemindersSync(this.store, this.mac, [this._prefs])
      : _enabled = _prefs?.getBool(_onKey) ?? false,
        _links = _loadLinks(_prefs?.getString(_linksKey)) {
    store.addListener(_onStoreChanged);
  }

  static Map<String, String> _loadLinks(String? raw) {
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  bool get enabled => _enabled;
  int get linked => _links.length;

  Future<void> setEnabled(bool on) async {
    _enabled = on;
    problem = null;
    await _prefs?.setBool(_onKey, on);
    notifyListeners();
    if (on) await push();
  }

  void _onStoreChanged() {
    if (_enabled) unawaited(push());
  }

  Future<void> _saveLinks() async =>
      _prefs?.setString(_linksKey, jsonEncode(_links));

  /// Lleva a Recordatorios lo nuevo, lo tachado y lo borrado.
  Future<void> push() async {
    if (!_enabled) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _pushOnce();
      } while (_again && _enabled);
    } on CalendarDenied {
      problem = tr('Sin permiso para Recordatorios: Ajustes del Sistema › Privacidad y seguridad › Recordatorios › activa PixelMate.', 'No permission for Reminders: System Settings › Privacy & Security › Reminders › turn on PixelMate.');
      _enabled = false;
      await _prefs?.setBool(_onKey, false);
      notifyListeners();
    } catch (e) {
      debugPrint('Recordatorios: $e');
    } finally {
      _busy = false;
    }
  }

  Future<void> _pushOnce() async {
    final tasks = {for (final t in store.allTasks) 'task:${t.id}': t};
    final reminders = {for (final r in store.reminders) 'rem:${r.id}': r};
    var changed = false;

    // Lo nuevo.
    for (final MapEntry(:key, :value) in tasks.entries) {
      if (_links.containsKey(key) || value.done) continue;
      final id = await mac.addAppleReminder(value.text);
      if (id != null) {
        _links[key] = id;
        _sentDone[key] = false;
        changed = true;
      }
    }
    for (final MapEntry(:key, :value) in reminders.entries) {
      if (_links.containsKey(key)) continue;
      final id = await mac.addAppleReminder(value.text, due: value.due);
      if (id != null) {
        _links[key] = id;
        changed = true;
      }
    }

    // Tachado o destachado aquí.
    for (final MapEntry(:key, :value) in tasks.entries) {
      final id = _links[key];
      if (id == null || _sentDone[key] == value.done) continue;
      await mac.setAppleReminderDone(id, value.done);
      _sentDone[key] = value.done;
    }

    // Lo que ya no está: una tarea borrada se borra; un recordatorio que ya
    // avisó se tacha (allí queda como hecho).
    for (final key in [..._links.keys]) {
      if (tasks.containsKey(key) || reminders.containsKey(key)) continue;
      final id = _links.remove(key)!;
      _sentDone.remove(key);
      changed = true;
      if (key.startsWith('task:')) {
        await mac.removeAppleReminder(id);
      } else {
        await mac.setAppleReminderDone(id, true);
      }
    }
    if (changed) await _saveLinks();
  }

  /// Trae de Recordatorios lo que tachaste en el iPhone.
  Future<int> pull() async {
    if (!_enabled) return 0;
    final tasks = {for (final t in store.allTasks) 'task:${t.id}': t};
    final ids = [
      for (final MapEntry(:key, :value) in _links.entries)
        if (tasks.containsKey(key)) value
    ];
    if (ids.isEmpty) return 0;
    final Map<String, bool> states;
    try {
      states = await mac.appleRemindersDone(ids);
    } catch (_) {
      return 0;
    }
    var count = 0;
    for (final MapEntry(:key, :value) in _links.entries) {
      final task = tasks[key];
      final doneThere = states[value];
      if (task == null || doneThere == null || doneThere == task.done) {
        continue;
      }
      _sentDone[key] = doneThere;
      await store.setDone(task.id, doneThere);
      count++;
    }
    return count;
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    super.dispose();
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final appleRemindersPrefsProvider = Provider<SharedPreferences?>((_) => null);

final appleRemindersProvider = ChangeNotifierProvider<AppleRemindersSync>(
  (ref) {
    final sync = AppleRemindersSync(
      ref.read(personalStoreProvider),
      ref.read(macActionsProvider),
      ref.read(appleRemindersPrefsProvider),
    );
    // Cada 2 minutos mira si tachaste algo en el iPhone.
    final timer = Timer.periodic(
        const Duration(minutes: 2), (_) => unawaited(sync.pull()));
    ref.onDispose(timer.cancel);
    return sync;
  },
);
