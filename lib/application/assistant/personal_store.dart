import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TaskItem {
  final String id;
  final String text;
  final bool done;
  final DateTime createdAt;

  const TaskItem(this.id, this.text,
      {this.done = false, required this.createdAt});

  TaskItem copyWith({bool? done}) =>
      TaskItem(id, text, done: done ?? this.done, createdAt: createdAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'done': done,
        'createdAt': createdAt.toIso8601String(),
      };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
        j['id'] as String,
        j['text'] as String,
        done: j['done'] as bool? ?? false,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

/// Cada cuánto se repite una alarma.
enum AlarmRepeat {
  none,
  daily,
  weekdays;

  static AlarmRepeat byName(Object? name) =>
      values.where((r) => r.name == name).firstOrNull ?? none;

  /// "todos los días", "de lunes a viernes" o "".
  String get label => switch (this) {
        none => '',
        daily => 'todos los días',
        weekdays => 'de lunes a viernes',
      };
}

class ReminderItem {
  final String id;
  final String text;
  final DateTime due;

  /// Suena como alarma (sonido que se repite hasta apagarla).
  final bool alarm;
  final AlarmRepeat repeat;

  const ReminderItem(this.id, this.text, this.due,
      {this.alarm = false, this.repeat = AlarmRepeat.none});

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'due': due.toIso8601String(),
        if (alarm) 'alarm': true,
        if (repeat != AlarmRepeat.none) 'repeat': repeat.name,
      };

  factory ReminderItem.fromJson(Map<String, dynamic> j) => ReminderItem(
        j['id'] as String,
        j['text'] as String,
        DateTime.parse(j['due'] as String),
        alarm: j['alarm'] == true,
        repeat: AlarmRepeat.byName(j['repeat']),
      );

  /// La siguiente vez que toca después de [now] (si se repite).
  DateTime? nextAfter(DateTime now) {
    if (repeat == AlarmRepeat.none) return null;
    var next = due;
    while (!next.isAfter(now) ||
        (repeat == AlarmRepeat.weekdays && next.weekday > DateTime.friday)) {
      next =
          DateTime(next.year, next.month, next.day + 1, next.hour, next.minute);
    }
    return next;
  }

  ReminderItem withDue(DateTime when) =>
      ReminderItem(id, text, when, alarm: alarm, repeat: repeat);
}

/// Tareas y recordatorios del usuario, guardados solo en este Mac.
class PersonalStore extends ChangeNotifier {
  static const _tasksKey = 'assistant.tasks';
  static const _remindersKey = 'assistant.reminders';

  final SharedPreferences? _prefs;
  final List<TaskItem> _tasks;
  final List<ReminderItem> _reminders;
  int _seq = 0;

  PersonalStore([this._prefs])
      : _tasks = _load(_prefs?.getString(_tasksKey), TaskItem.fromJson),
        _reminders =
            _load(_prefs?.getString(_remindersKey), ReminderItem.fromJson);

  static List<T> _load<T>(
      String? raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw == null) return [];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          fromJson(e as Map<String, dynamic>)
      ];
    } catch (_) {
      return []; // un archivo dañado no rompe la app
    }
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}-${_seq++}';

  Future<void> _save() async {
    await _prefs?.setString(
        _tasksKey, jsonEncode([for (final t in _tasks) t.toJson()]));
    await _prefs?.setString(
        _remindersKey, jsonEncode([for (final r in _reminders) r.toJson()]));
    notifyListeners();
  }

  /// Tareas por hacer, en el orden en que se apuntaron.
  List<TaskItem> get pending => [
        for (final t in _tasks)
          if (!t.done) t
      ];

  /// Hechas, la más reciente primero (las últimas 10).
  List<TaskItem> get done => [
        for (final t in _tasks.reversed)
          if (t.done) t
      ].take(10).toList();

  /// Recordatorios por llegar, el más próximo primero.
  List<ReminderItem> get reminders =>
      [..._reminders]..sort((a, b) => a.due.compareTo(b.due));

  Future<TaskItem> addTask(String text) async {
    final t = TaskItem(_id(), text.trim(), createdAt: DateTime.now());
    _tasks.add(t);
    await _save();
    return t;
  }

  /// Marca hecha la tarea número [number] de las pendientes (1 = primera).
  /// Devuelve la tarea, o `null` si ese número no existe.
  Future<TaskItem?> completeTask(int number) async {
    final list = pending;
    if (number < 1 || number > list.length) return null;
    return setDone(list[number - 1].id, true);
  }

  Future<TaskItem?> setDone(String id, bool done) async {
    final i = _tasks.indexWhere((t) => t.id == id);
    if (i < 0) return null;
    _tasks[i] = _tasks[i].copyWith(done: done);
    await _save();
    return _tasks[i];
  }

  Future<void> removeTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _save();
  }

  Future<ReminderItem> addReminder(String text, DateTime due,
      {bool alarm = false, AlarmRepeat repeat = AlarmRepeat.none}) async {
    final r =
        ReminderItem(_id(), text.trim(), due, alarm: alarm, repeat: repeat);
    _reminders.add(r);
    await _save();
    return r;
  }

  Future<void> removeReminder(String id) async {
    _reminders.removeWhere((r) => r.id == id);
    await _save();
  }

  /// Alarmas guardadas (por hora).
  List<ReminderItem> get alarms => [
        for (final r in reminders)
          if (r.alarm) r
      ];

  /// Saca y devuelve los recordatorios que ya tocan. Las alarmas que se
  /// repiten se quedan, con su próxima hora.
  Future<List<ReminderItem>> takeDue(DateTime now) async {
    final due = [
      for (final r in _reminders)
        if (!r.due.isAfter(now)) r
    ];
    if (due.isEmpty) return const [];
    _reminders.removeWhere((r) => !r.due.isAfter(now));
    for (final r in due) {
      final next = r.nextAfter(now);
      if (next != null) _reminders.add(r.withDue(next));
    }
    await _save();
    // Una alarma de hace más de [lateAlarm] (el Mac estaba dormido) ya no
    // suena: llega como recordatorio normal.
    return [
      for (final r in due)
        if (r.alarm && now.difference(r.due) > lateAlarm)
          ReminderItem(r.id, r.text, r.due)
        else
          r
    ]..sort((a, b) => a.due.compareTo(b.due));
  }

  /// Lo más tarde que suena una alarma.
  static const lateAlarm = Duration(minutes: 30);

  /// Texto breve para la IA (las pendientes numeradas).
  String describe() {
    final p = pending;
    final tasks = p.isEmpty
        ? 'Sin tareas pendientes.'
        : 'Tareas pendientes: '
            '${[
            for (var i = 0; i < p.length && i < 8; i++) '${i + 1}) ${p[i].text}'
          ].join('; ')}.';
    return tasks;
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final personalStoreProvider = Provider<PersonalStore>((_) => PersonalStore());
