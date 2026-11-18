import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'personal_store.dart';

/// Letras de los días (lunes = 1 … domingo = 7).
const dayLetters = {1: 'L', 2: 'M', 3: 'X', 4: 'J', 5: 'V', 6: 'S', 7: 'D'};

const allDays = {1, 2, 3, 4, 5, 6, 7};
const weekdays = {1, 2, 3, 4, 5};

/// Una tarea de todos los días a una hora: suena como alarma y se marca
/// como hecha cada día.
class DailyTask {
  final String id;
  final String text;
  final int hour;
  final int minute;

  /// Días en que toca (1 = lunes … 7 = domingo).
  final Set<int> days;
  final bool enabled;

  /// Último día (aaaa-mm-dd) en que sonó y en que se hizo.
  final String? rangOn;
  final String? doneOn;

  const DailyTask({
    required this.id,
    required this.text,
    required this.hour,
    required this.minute,
    this.days = allDays,
    this.enabled = true,
    this.rangOn,
    this.doneOn,
  });

  String get time => '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}';

  /// "9:10 p. m." (como el reloj de la barra de menú en español).
  String get time12 => clock12(hour, minute);

  /// "Todos los días", "L a V" o "L X V".
  String get daysLabel {
    if (days.length == 7) return 'Todos los días';
    if (setEquals(days, weekdays)) return 'De lunes a viernes';
    if (setEquals(days, {6, 7})) return 'Fines de semana';
    return (days.toList()..sort()).map((d) => dayLetters[d]).join(' ');
  }

  bool isToday(DateTime now) => days.contains(now.weekday);
  bool doneToday(DateTime now) => doneOn == dayKey(now);

  DateTime at(DateTime day) =>
      DateTime(day.year, day.month, day.day, hour, minute);

  DailyTask copyWith({
    String? text,
    int? hour,
    int? minute,
    Set<int>? days,
    bool? enabled,
    String? rangOn,
    String? doneOn,
    bool clearDone = false,
  }) =>
      DailyTask(
        id: id,
        text: text ?? this.text,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        days: days ?? this.days,
        enabled: enabled ?? this.enabled,
        rangOn: rangOn ?? this.rangOn,
        doneOn: clearDone ? null : doneOn ?? this.doneOn,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'hour': hour,
        'minute': minute,
        'days': (days.toList()..sort()),
        'enabled': enabled,
        if (rangOn != null) 'rangOn': rangOn,
        if (doneOn != null) 'doneOn': doneOn,
      };

  factory DailyTask.fromJson(Map<String, dynamic> j) => DailyTask(
        id: j['id'] as String,
        text: j['text'] as String,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        days: j['days'] is List
            ? {for (final d in j['days'] as List) d as int}
            : allDays,
        enabled: j['enabled'] as bool? ?? true,
        rangOn: j['rangOn'] as String?,
        doneOn: j['doneOn'] as String?,
      );
}

/// "9:10 a. m.", "12:00 p. m.", "12:30 a. m.".
String clock12(int hour, int minute) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:${minute.toString().padLeft(2, '0')} '
      '${hour < 12 ? 'a. m.' : 'p. m.'}';
}

String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Las tareas diarias, guardadas solo en este Mac.
class DailyTaskStore extends ChangeNotifier {
  static const _key = 'daily.tasks';

  /// Prefijo del id de las alarmas que vienen de una tarea diaria.
  static const alarmPrefix = 'daily-';

  final SharedPreferences? _prefs;
  final List<DailyTask> _tasks = [];
  int _seq = 0;

  DailyTaskStore([this._prefs]) {
    final raw = _prefs?.getString(_key);
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          _tasks.add(DailyTask.fromJson(e as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('Tareas diarias: $e');
      }
    }
  }

  /// Ordenadas por hora.
  List<DailyTask> get tasks => [..._tasks]..sort(
      (a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

  /// Las de hoy (activas), por hora.
  List<DailyTask> today(DateTime now) => [
        for (final t in tasks)
          if (t.enabled && t.isToday(now)) t
      ];

  DailyTask? byId(String id) => _tasks.where((t) => t.id == id).firstOrNull;

  Future<void> _save() async {
    notifyListeners();
    await _prefs?.setString(
        _key, jsonEncode([for (final t in _tasks) t.toJson()]));
  }

  Future<DailyTask?> add(String text, int hour, int minute,
      {Set<int> days = allDays, DateTime? now}) async {
    final clean = text.trim();
    if (clean.isEmpty || days.isEmpty) return null;
    final t = DailyTask(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      text: clean,
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      days: days,
      // Si ya pasó la hora hoy, no suena hasta mañana (pero la del minuto
      // actual sí suena: es la que pones para probar).
      rangOn: now != null &&
              DateTime(now.year, now.month, now.day, hour, minute).isBefore(
                  DateTime(now.year, now.month, now.day, now.hour, now.minute))
          ? dayKey(now)
          : null,
    );
    _tasks.add(t);
    await _save();
    return t;
  }

  Future<void> _replace(DailyTask t) async {
    final i = _tasks.indexWhere((x) => x.id == t.id);
    if (i < 0) return;
    _tasks[i] = t;
    await _save();
  }

  Future<void> setEnabled(String id, bool on) async {
    final t = byId(id);
    if (t != null) await _replace(t.copyWith(enabled: on));
  }

  /// Marca o desmarca la tarea como hecha hoy.
  Future<void> setDone(String id, bool done, DateTime now) async {
    final t = byId(id);
    if (t == null) return;
    await _replace(
        done ? t.copyWith(doneOn: dayKey(now)) : t.copyWith(clearDone: true));
  }

  Future<void> remove(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _save();
  }

  /// Las que tienen que sonar ya: activas, de hoy, con su hora pasada hace
  /// menos de [window], sin hacer y sin haber sonado hoy. Las marca como
  /// sonadas. (Si abriste el Mac mucho después, no suena tarde.)
  Future<List<DailyTask>> takeDue(DateTime now,
      {Duration window = const Duration(minutes: 30)}) async {
    final key = dayKey(now);
    final due = <DailyTask>[];
    for (final t in today(now)) {
      final at = t.at(now);
      if (t.rangOn == key || t.doneToday(now) || at.isAfter(now)) continue;
      if (now.difference(at) <= window) due.add(t);
      await _replace(t.copyWith(rangOn: key));
    }
    return due;
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final dailyTaskStoreProvider =
    ChangeNotifierProvider<DailyTaskStore>((_) => DailyTaskStore());

/// Revisa cada 5 s si toca alguna tarea diaria y la hace sonar.
class DailyTaskScheduler {
  final DailyTaskStore store;
  final AlarmController alarms;
  final DateTime Function() now;
  Timer? _timer;

  DailyTaskScheduler(this.store, this.alarms,
      {DateTime Function()? now, Duration every = const Duration(seconds: 5)})
      : now = now ?? DateTime.now {
    _timer = Timer.periodic(every, (_) => check());
    scheduleMicrotask(check);
  }

  Future<List<DailyTask>> check() async {
    final t = now();
    final due = await store.takeDue(t);
    if (due.isNotEmpty) {
      alarms.ring([
        for (final d in due)
          ReminderItem('${DailyTaskStore.alarmPrefix}${d.id}', d.text, d.at(t),
              alarm: true)
      ]);
    }
    return due;
  }

  void dispose() => _timer?.cancel();
}

final dailyTaskSchedulerProvider = Provider<DailyTaskScheduler>((ref) {
  // `read`: la tienda avisa de cada cambio, y con `watch` el revisor se
  // apagaría (y nadie lo volvería a crear) al añadir o marcar una tarea.
  final s = DailyTaskScheduler(
      ref.read(dailyTaskStoreProvider), ref.read(alarmProvider.notifier));
  ref.onDispose(s.dispose);
  return s;
});
