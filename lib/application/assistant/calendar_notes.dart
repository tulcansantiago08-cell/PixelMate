import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'daily_tasks.dart';
import 'mac_actions.dart';
import 'personal_store.dart';
import 'reminders.dart';

const monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre'
];
const weekdayNames = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo'
];

/// "hoy", "mañana" o "el viernes 20 de noviembre".
String describeDay(DateTime day, DateTime now) {
  final d = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(now.year, now.month, now.day))
      .inDays;
  if (d == 0) return 'hoy';
  if (d == 1) return 'mañana';
  return 'el ${weekdayNames[day.weekday - 1].toLowerCase()} ${day.day} de '
      '${monthNames[day.month - 1]}';
}

/// Colores para marcar las notas del calendario (el índice se guarda).
const calendarColorNames = [
  'Naranja',
  'Azul',
  'Verde',
  'Morado',
  'Rosa',
  'Amarillo',
];

/// Algo anotado en el calendario: todo el día (sin hora) o a una hora, con
/// su color. Ese día te avisa: las de todo el día a las [noticeHour], las
/// otras a su hora (y si llevan alarma, suena).
class CalendarNote {
  /// Hora del aviso de las notas de todo el día.
  static const noticeHour = 8;

  final String id;
  final String text;

  /// El día (sin hora).
  final DateTime day;

  /// `null`: todo el día.
  final int? hour;
  final int minute;
  final bool alarm;
  final int color;

  /// Ya avisó.
  final bool notified;

  /// El evento creado en el Calendario del Mac, si se creó.
  final String? macId;

  CalendarNote({
    required this.id,
    required this.text,
    required DateTime day,
    this.hour,
    this.minute = 0,
    this.alarm = false,
    this.color = 0,
    this.notified = false,
    this.macId,
  }) : day = DateTime(day.year, day.month, day.day);

  bool get allDay => hour == null;

  /// Cuándo avisa.
  DateTime get at => DateTime(day.year, day.month, day.day, hour ?? noticeHour,
      hour == null ? 0 : minute);

  /// "Todo el día" o "9:30 a. m.".
  String get timeLabel => allDay ? 'Todo el día' : clock12(hour!, minute);

  bool on(DateTime d) =>
      day.year == d.year && day.month == d.month && day.day == d.day;

  CalendarNote copyWith({bool? notified, String? macId}) => CalendarNote(
        id: id,
        text: text,
        day: day,
        hour: hour,
        minute: minute,
        alarm: alarm,
        color: color,
        notified: notified ?? this.notified,
        macId: macId ?? this.macId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'day': dayKey(day),
        if (hour != null) 'hour': hour,
        if (hour != null) 'minute': minute,
        if (alarm) 'alarm': true,
        'color': color,
        if (notified) 'notified': true,
        if (macId != null) 'macId': macId,
      };

  factory CalendarNote.fromJson(Map<String, dynamic> j) => CalendarNote(
        id: j['id'] as String,
        text: j['text'] as String,
        day: DateTime.parse(j['day'] as String),
        hour: j['hour'] as int?,
        minute: j['minute'] as int? ?? 0,
        alarm: j['alarm'] == true,
        color:
            ((j['color'] as int?) ?? 0).clamp(0, calendarColorNames.length - 1),
        notified: j['notified'] == true,
        macId: j['macId'] as String?,
      );
}

/// Las notas del calendario, guardadas solo en este Mac.
class CalendarStore extends ChangeNotifier {
  static const _key = 'calendar.notes';
  static const _macKey = 'calendar.toMac';

  /// Lo más tarde que suena una alarma (si el Mac estaba dormido).
  static const lateAlarm = Duration(minutes: 30);

  final SharedPreferences? _prefs;
  final List<CalendarNote> _notes = [];
  int _seq = 0;
  bool _toMac;

  CalendarStore([this._prefs]) : _toMac = _prefs?.getBool(_macKey) ?? false {
    final raw = _prefs?.getString(_key);
    if (raw != null) {
      try {
        for (final e in jsonDecode(raw) as List) {
          _notes.add(CalendarNote.fromJson(e as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('Calendario: $e');
      }
    }
  }

  /// Si las notas nuevas también van al Calendario del Mac.
  bool get toMac => _toMac;
  Future<void> setToMac(bool on) async {
    _toMac = on;
    notifyListeners();
    await _prefs?.setBool(_macKey, on);
  }

  /// Por día y hora (las de todo el día primero).
  List<CalendarNote> get notes => [..._notes]..sort((a, b) {
      final d = a.day.compareTo(b.day);
      if (d != 0) return d;
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.at.compareTo(b.at);
    });

  List<CalendarNote> onDay(DateTime day) => [
        for (final n in notes)
          if (n.on(day)) n
      ];

  CalendarNote? byId(String id) => _notes.where((n) => n.id == id).firstOrNull;

  Future<void> _save() async {
    notifyListeners();
    await _prefs?.setString(
        _key, jsonEncode([for (final n in _notes) n.toJson()]));
  }

  /// Anota [text] el [day]; sin [hour], todo el día. Si su aviso ya pasó,
  /// no avisa (lo acabas de escribir).
  Future<CalendarNote?> add(String text, DateTime day,
      {int? hour,
      int minute = 0,
      bool alarm = false,
      int color = 0,
      DateTime? now}) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    var note = CalendarNote(
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      text: clean,
      day: day,
      hour: hour?.clamp(0, 23),
      minute: minute.clamp(0, 59),
      alarm: hour != null && alarm,
      color: color.clamp(0, calendarColorNames.length - 1),
    );
    if (now != null && note.at.isBefore(now)) {
      note = note.copyWith(notified: true);
    }
    _notes.add(note);
    await _save();
    return note;
  }

  Future<void> setMacId(String id, String macId) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    _notes[i] = _notes[i].copyWith(macId: macId);
    await _save();
  }

  Future<void> remove(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _save();
  }

  /// Las que tienen que avisar ya. Las marca como avisadas. Si el Mac
  /// estaba dormido: las de un día que ya pasó no avisan, y una alarma de
  /// hace más de [lateAlarm] llega como aviso, sin sonar.
  Future<List<CalendarNote>> takeDue(DateTime now) async {
    final due = <CalendarNote>[];
    var changed = false;
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      if (n.notified || n.at.isAfter(now)) continue;
      _notes[i] = n.copyWith(notified: true);
      changed = true;
      if (!n.on(now)) continue;
      due.add(n.alarm && now.difference(n.at) > lateAlarm
          ? CalendarNote(
              id: n.id,
              text: n.text,
              day: n.day,
              hour: n.hour,
              minute: n.minute,
              color: n.color)
          : n);
    }
    if (changed) await _save();
    return due..sort((a, b) => a.at.compareTo(b.at));
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final calendarStoreProvider =
    ChangeNotifierProvider<CalendarStore>((_) => CalendarStore());

/// Revisa cada 5 s si toca alguna nota: las alarmas suenan y las demás
/// llegan como aviso (estado de este notifier, igual que los recordatorios).
class CalendarScheduler extends StateNotifier<ReminderAlert?> {
  /// Prefijo del id de las alarmas que vienen del calendario.
  static const alarmPrefix = 'cal-';

  final CalendarStore store;
  final AlarmController alarms;
  final DateTime Function() _now;
  Timer? _timer;

  CalendarScheduler(this.store, this.alarms,
      {DateTime Function()? now, Duration every = const Duration(seconds: 5)})
      : _now = now ?? DateTime.now,
        super(null) {
    _timer = Timer.periodic(every, (_) => check());
    scheduleMicrotask(check);
  }

  Future<List<CalendarNote>> check() async {
    final t = _now();
    final due = await store.takeDue(t);
    if (due.isEmpty || !mounted) return due;
    final ring = [
      for (final n in due)
        if (n.alarm)
          ReminderItem('$alarmPrefix${n.id}', n.text, n.at, alarm: true)
    ];
    if (ring.isNotEmpty) alarms.ring(ring);
    final notices = [
      for (final n in due)
        if (!n.alarm)
          ReminderItem('$alarmPrefix${n.id}',
              n.allDay ? 'hoy es «${n.text}»' : n.text, n.allDay ? t : n.at)
    ];
    if (notices.isNotEmpty) state = ReminderAlert(notices, t);
    return due;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final calendarAlertProvider =
    StateNotifierProvider<CalendarScheduler, ReminderAlert?>((ref) =>
        // `read`: la tienda avisa de cada cambio; con `watch` se rehace.
        CalendarScheduler(
            ref.read(calendarStoreProvider), ref.read(alarmProvider.notifier)));

/// Qué decir si el Mac no deja usar su Calendario.
const calendarDeniedMessage =
    'Sin permiso para el Calendario del Mac: Ajustes del Sistema › '
    'Privacidad y seguridad › Calendarios › activa PixelMate.';

/// Copia [note] al Calendario del Mac (con aviso: las de todo el día a las
/// 8, las de hora 10 min antes, o a su hora si llevan alarma) y guarda el
/// id. Devuelve el problema, o `null` si fue bien.
Future<String?> copyToMacCalendar(
    CalendarStore store, MacActions mac, CalendarNote note) async {
  try {
    final id = await mac.createEvent(
      note.text,
      note.allDay ? note.day : note.at,
      allDay: note.allDay,
      alert: note.allDay
          ? CalendarNote.noticeHour * 60
          : note.alarm
              ? 0
              : 10,
    );
    if (id != null) await store.setMacId(note.id, id);
    return null;
  } on CalendarDenied {
    return calendarDeniedMessage;
  } catch (_) {
    return 'No pude guardarlo en el Calendario del Mac.';
  }
}

/// Borra [note] (y su copia en el Calendario del Mac, si la tiene).
Future<void> removeNote(
    CalendarStore store, MacActions mac, CalendarNote note) async {
  await store.remove(note.id);
  final id = note.macId;
  if (id == null) return;
  try {
    await mac.deleteEvent(id);
  } catch (_) {
    // Si no se puede, queda en el Calendario del Mac.
  }
}
