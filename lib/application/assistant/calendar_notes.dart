import '../../core/i18n/language.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm.dart';
import 'alarm_settings.dart';
import 'daily_tasks.dart';
import 'mac_actions.dart';
import 'personal_store.dart';
import 'reminders.dart';

const _monthNamesEs = [
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
const _monthNamesEn = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'
];

/// Nombres de los meses en el idioma de la app ("noviembre" / "November").
List<String> get monthNames => tr('es', 'en') == 'en' ? _monthNamesEn : _monthNamesEs;

const _weekdayNamesEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];

/// Nombres de los días en el idioma de la app ("Lunes" / "Monday").
List<String> get weekdayNames => tr('es', 'en') == 'en' ? _weekdayNamesEn : _weekdayNamesEs;

/// "20 de noviembre" / "November 20".
String dayOfMonth(DateTime d) =>
    tr('${d.day} de ${monthNames[d.month - 1]}', '${monthNames[d.month - 1]} ${d.day}');

/// "Lunes 20 de noviembre" / "Monday, November 20".
String calendarLongDate(DateTime d) =>
    tr('${weekdayNames[d.weekday - 1]} ${dayOfMonth(d)}', '${weekdayNames[d.weekday - 1]}, ${dayOfMonth(d)}');

const _weekdayNamesEs = [
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
  if (d == 0) return tr('hoy', 'today');
  if (d == 1) return tr('mañana', 'tomorrow');
  return tr('el ${weekdayNames[day.weekday - 1].toLowerCase()} ${dayOfMonth(day)}',
      'on ${calendarLongDate(day)}');
}

/// Colores para marcar las notas del calendario (el índice se guarda).
const calendarColorNames = [
  'Naranja',
  'Azul',
  'Verde',
  'Morado',
  'Rosa',
  'Amarillo',
  'Gris',
];

/// Color de los recordatorios del chat que quedan en el calendario.
const reminderColor = 6;

/// Cada cuánto se repite una nota.
enum NoteRepeat {
  none,
  weekly,
  yearly;

  static NoteRepeat byName(Object? name) =>
      values.where((r) => r.name == name).firstOrNull ?? none;

  /// "", "cada semana" o "cada año".
  String get label => switch (this) {
        none => '',
        weekly => 'cada semana',
        yearly => 'cada año',
      };
}

/// Algo anotado en el calendario: todo el día (sin hora) o a una hora, con
/// su color, una vez o repitiéndose. Cada día que toca te avisa: las de todo
/// el día a las [noticeHour], las otras a su hora (y si llevan alarma,
/// suena).
class CalendarNote {
  /// Hora del aviso de las notas de todo el día.
  static const noticeHour = 8;

  final String id;
  final String text;

  /// El día (sin hora); si se repite, el primero.
  final DateTime day;

  /// `null`: todo el día.
  final int? hour;
  final int minute;
  final bool alarm;
  final int color;
  final NoteRepeat repeat;

  /// Último día (aaaa-mm-dd) en que avisó.
  final String? notifiedOn;

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
    this.repeat = NoteRepeat.none,
    this.notifiedOn,
    this.macId,
  }) : day = DateTime(day.year, day.month, day.day);

  bool get allDay => hour == null;

  /// Ya avisó alguna vez.
  bool get notified => notifiedOn != null;

  /// Cuándo avisa el [d] (el primer día, si no se dice).
  DateTime atOn(DateTime d) => DateTime(
      d.year, d.month, d.day, hour ?? noticeHour, hour == null ? 0 : minute);
  DateTime get at => atOn(day);

  /// "Todo el día" o "9:30 a. m.".
  String get timeLabel => allDay ? 'Todo el día' : clock12(hour!, minute);

  /// Si toca el [d] (contando las repeticiones).
  bool on(DateTime d) {
    final target = DateTime(d.year, d.month, d.day);
    if (target.isBefore(day)) return false;
    return switch (repeat) {
      NoteRepeat.none => target == day,
      NoteRepeat.weekly => target.weekday == day.weekday,
      NoteRepeat.yearly => target.month == day.month && target.day == day.day,
    };
  }

  CalendarNote copyWith({
    String? text,
    DateTime? day,
    int? hour,
    bool allDay = false,
    int? minute,
    bool? alarm,
    int? color,
    NoteRepeat? repeat,
    String? notifiedOn,
    bool clearNotified = false,
    String? macId,
    bool clearMac = false,
  }) {
    final h = allDay ? null : hour ?? this.hour;
    return CalendarNote(
      id: id,
      text: text ?? this.text,
      day: day ?? this.day,
      hour: h,
      minute: minute ?? this.minute,
      alarm: h != null && (alarm ?? this.alarm),
      color: color ?? this.color,
      repeat: repeat ?? this.repeat,
      notifiedOn: clearNotified ? null : notifiedOn ?? this.notifiedOn,
      macId: clearMac ? null : macId ?? this.macId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'day': dayKey(day),
        if (hour != null) 'hour': hour,
        if (hour != null) 'minute': minute,
        if (alarm) 'alarm': true,
        'color': color,
        if (repeat != NoteRepeat.none) 'repeat': repeat.name,
        if (notifiedOn != null) 'notifiedOn': notifiedOn,
        if (macId != null) 'macId': macId,
      };

  factory CalendarNote.fromJson(Map<String, dynamic> j) {
    final day = DateTime.parse(j['day'] as String);
    return CalendarNote(
      id: j['id'] as String,
      text: j['text'] as String,
      day: day,
      hour: j['hour'] as int?,
      minute: j['minute'] as int? ?? 0,
      alarm: j['alarm'] == true,
      color:
          ((j['color'] as int?) ?? 0).clamp(0, calendarColorNames.length - 1),
      repeat: NoteRepeat.byName(j['repeat']),
      // Las guardadas antes solo decían si ya avisó.
      notifiedOn: j['notifiedOn'] as String? ??
          (j['notified'] == true ? dayKey(day) : null),
      macId: j['macId'] as String?,
    );
  }
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

  /// Las que tocan ese día (con las que se repiten), por hora.
  List<CalendarNote> onDay(DateTime day) => [
        for (final n in _notes)
          if (n.on(day)) n
      ]..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          return a.atOn(day).compareTo(b.atOn(day));
        });

  CalendarNote? byId(String id) => _notes.where((n) => n.id == id).firstOrNull;

  Future<void> _save() async {
    notifyListeners();
    await _prefs?.setString(
        _key, jsonEncode([for (final n in _notes) n.toJson()]));
  }

  /// Si el aviso de hoy ya pasó (lo acabas de escribir), no avisa hoy.
  CalendarNote _skipPast(CalendarNote n, DateTime? now) =>
      now != null && n.on(now) && n.atOn(now).isBefore(now)
          ? n.copyWith(notifiedOn: dayKey(now))
          : n;

  /// Anota [text] el [day]; sin [hour], todo el día.
  Future<CalendarNote?> add(String text, DateTime day,
      {int? hour,
      int minute = 0,
      bool alarm = false,
      int color = 0,
      NoteRepeat repeat = NoteRepeat.none,
      DateTime? now}) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    final note = _skipPast(
        CalendarNote(
          id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
          text: clean,
          day: day,
          hour: hour?.clamp(0, 23),
          minute: minute.clamp(0, 59),
          alarm: hour != null && alarm,
          color: color.clamp(0, calendarColorNames.length - 1),
          repeat: repeat,
        ),
        now);
    _notes.add(note);
    await _save();
    return note;
  }

  /// Guarda un recordatorio que ya avisó, para que quede en el calendario.
  Future<void> addRecord(String id, String text, DateTime at) async {
    if (byId(id) != null) return;
    _notes.add(CalendarNote(
      id: id,
      text: text,
      day: at,
      hour: at.hour,
      minute: at.minute,
      color: reminderColor,
      notifiedOn: dayKey(at),
    ));
    await _save();
  }

  /// Cambia una nota. Si cambió el día o la hora, vuelve a avisar.
  Future<CalendarNote?> update(CalendarNote changed, {DateTime? now}) async {
    final i = _notes.indexWhere((n) => n.id == changed.id);
    if (i < 0 || changed.text.trim().isEmpty) return null;
    final old = _notes[i];
    var note = changed;
    if (old.at != changed.at ||
        old.day != changed.day ||
        old.repeat != changed.repeat) {
      note = _skipPast(changed.copyWith(clearNotified: true), now);
    }
    _notes[i] = note;
    await _save();
    return note;
  }

  Future<void> setMacId(String id, String? macId) async {
    final i = _notes.indexWhere((n) => n.id == id);
    if (i < 0) return;
    _notes[i] = macId == null
        ? _notes[i].copyWith(clearMac: true)
        : _notes[i].copyWith(macId: macId);
    await _save();
  }

  Future<void> remove(String id) async {
    _notes.removeWhere((n) => n.id == id);
    await _save();
  }

  /// Las que tienen que avisar ya: las de hoy cuya hora llegó y que hoy no
  /// han avisado. Las marca. Una alarma de hace más de [lateAlarm] (el Mac
  /// estaba dormido) llega como aviso, sin sonar.
  Future<List<CalendarNote>> takeDue(DateTime now) async {
    final key = dayKey(now);
    final due = <CalendarNote>[];
    for (var i = 0; i < _notes.length; i++) {
      final n = _notes[i];
      if (!n.on(now) || n.notifiedOn == key || n.atOn(now).isAfter(now)) {
        continue;
      }
      _notes[i] = n.copyWith(notifiedOn: key);
      final late = now.difference(n.atOn(now)) > lateAlarm;
      due.add(n.alarm && late ? n.copyWith(alarm: false) : n);
    }
    if (due.isNotEmpty) await _save();
    return due..sort((a, b) => a.atOn(now).compareTo(b.atOn(now)));
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

  /// Tareas diarias (para el aviso previo).
  final DailyTaskStore? daily;

  /// Minutos antes de una tarea con hora en que avisa (0: no avisa antes).
  final int Function() leadMinutes;

  /// Avisos previos ya dados (id + día).
  final Set<String> _early = {};

  CalendarScheduler(this.store, this.alarms,
      {DateTime Function()? now,
      Duration every = const Duration(seconds: 5),
      this.daily,
      int Function()? leadMinutes})
      : _now = now ?? DateTime.now,
        leadMinutes = leadMinutes ?? (() => 0),
        super(null) {
    _timer = Timer.periodic(every, (_) => check());
    scheduleMicrotask(check);
  }

  /// "en 10 min: Dentista" de lo que empieza dentro de [leadMinutes].
  List<ReminderItem> _upcoming(DateTime t) {
    final lead = leadMinutes();
    if (lead <= 0) return const [];
    final key = dayKey(t);
    final soon = <ReminderItem>[];
    void check(String id, String text, DateTime at) {
      final left = at.difference(t);
      if (left <= Duration.zero || left > Duration(minutes: lead)) return;
      if (!_early.add('$id@$key')) return;
      final minutes = (left.inSeconds / 60).ceil();
      soon.add(ReminderItem('early-$id',
          'en $minutes min: $text (${clock12(at.hour, at.minute)})', t));
    }

    for (final n in store.onDay(t)) {
      if (!n.allDay && n.notifiedOn != key) check(n.id, n.text, n.atOn(t));
    }
    for (final d in daily?.today(t) ?? <DailyTask>[]) {
      if (!d.doneToday(t)) check('daily-${d.id}', d.text, d.at(t));
    }
    return soon;
  }

  Future<List<CalendarNote>> check() async {
    final t = _now();
    final due = await store.takeDue(t);
    if (!mounted) return due;
    final soon = _upcoming(t);
    if (due.isEmpty) {
      if (soon.isNotEmpty) state = ReminderAlert(soon, t);
      return due;
    }
    final ring = [
      for (final n in due)
        if (n.alarm)
          ReminderItem('$alarmPrefix${n.id}', n.text, n.atOn(t), alarm: true)
    ];
    if (ring.isNotEmpty) alarms.ring(ring);
    final notices = [
      for (final n in due)
        if (!n.alarm)
          ReminderItem(
              '$alarmPrefix${n.id}',
              n.allDay ? 'hoy es «${n.text}»' : n.text,
              n.allDay ? t : n.atOn(t))
    ];
    if (notices.isNotEmpty || soon.isNotEmpty) {
      state = ReminderAlert([...soon, ...notices], t);
    }
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
          ref.read(calendarStoreProvider),
          ref.read(alarmProvider.notifier),
          daily: ref.read(dailyTaskStoreProvider),
          leadMinutes: () => ref.read(alarmSettingsProvider).leadMinutes,
        ));

/// Qué decir si el Mac no deja usar su Calendario.
const calendarDeniedMessage =
    'Sin permiso para el Calendario del Mac: Ajustes del Sistema › Privacidad y seguridad › Calendarios › activa PixelMate.';

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
      repeat: note.repeat == NoteRepeat.none ? null : note.repeat.name,
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

/// Guarda los cambios de [changed] (y rehace su copia en el Calendario del
/// Mac, si la tiene). Devuelve el problema con el Mac, o `null`.
Future<String?> editNote(
    CalendarStore store, MacActions mac, CalendarNote changed,
    {DateTime? now}) async {
  final old = store.byId(changed.id);
  final saved = await store.update(changed, now: now);
  if (saved == null || old?.macId == null) return null;
  try {
    await mac.deleteEvent(old!.macId!);
  } catch (_) {}
  await store.setMacId(saved.id, null);
  return copyToMacCalendar(store, mac, store.byId(saved.id)!);
}
