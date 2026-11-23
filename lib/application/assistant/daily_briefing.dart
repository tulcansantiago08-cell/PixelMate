import '../../core/i18n/language.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../mascot/mascot_settings.dart';
import 'calendar_notes.dart';
import 'daily_tasks.dart';
import 'mac_actions.dart';
import 'personal_store.dart';

/// Algo que tienes un día, para la agenda.
class AgendaItem {
  /// "Todo el día" o "9:30 a. m.".
  final String time;
  final String text;

  /// Para ordenar: minutos desde la medianoche (-1: todo el día).
  final int order;

  const AgendaItem(this.time, this.text, this.order);

  @override
  String toString() => '$time $text';
}

/// Lo que tienes el [day]: notas del calendario, tareas diarias,
/// recordatorios y eventos del Calendario del Mac (sin repetir los que
/// copió PixelMate), por hora.
List<AgendaItem> agendaFor(
  DateTime day, {
  CalendarStore? notes,
  DailyTaskStore? daily,
  List<ReminderItem> reminders = const [],
  List<CalendarEvent> macEvents = const [],
}) {
  bool sameDay(DateTime a) =>
      a.year == day.year && a.month == day.month && a.day == day.day;
  final copied = {for (final n in notes?.notes ?? <CalendarNote>[]) n.macId};
  final items = <AgendaItem>[
    for (final n in notes?.onDay(day) ?? <CalendarNote>[])
      // Los recordatorios que ya avisaron solo quedan como registro.
      if (n.color != reminderColor)
        AgendaItem(n.timeLabel, n.alarm ? '${n.text} 🔔' : n.text,
            n.allDay ? -1 : n.hour! * 60 + n.minute),
    for (final t in daily?.tasks ?? <DailyTask>[])
      if (t.enabled && t.days.contains(day.weekday))
        AgendaItem(t.time12, tr('${t.text} (diaria)', '${t.text} (daily)'), t.hour * 60 + t.minute),
    for (final r in reminders)
      if (sameDay(r.due))
        AgendaItem(clock12(r.due.hour, r.due.minute), r.text,
            r.due.hour * 60 + r.due.minute),
    for (final e in macEvents)
      if (!copied.contains(e.id))
        AgendaItem(
            e.allDay ? tr('Todo el día', 'All day') : clock12(e.start.hour, e.start.minute),
            e.title,
            e.allDay ? -1 : e.start.hour * 60 + e.start.minute),
  ];
  items.sort((a, b) => a.order.compareTo(b.order));
  return items;
}

/// "☀️ Buenos días, Santi. Hoy tienes: …".
String briefingMessage(
    {String? userName, required List<AgendaItem> items, int pending = 0}) {
  final hi = userName == null || userName.isEmpty
      ? tr('☀️ Buenos días.', '☀️ Good morning.')
      : tr('☀️ Buenos días, $userName.', '☀️ Good morning, $userName.');
  final tasks = pending == 0
      ? ''
      : pending == 1
          ? tr('\n📝 Tienes 1 tarea pendiente.', '\n📝 You have 1 pending task.')
          : tr('\n📝 Tienes $pending tareas pendientes.', '\n📝 You have $pending pending tasks.');
  if (items.isEmpty) {
    return tr('$hi Hoy no tienes nada anotado. ¿Qué te gustaría lograr?$tasks', '$hi You have nothing noted today. What would you like to achieve?$tasks');
  }
  final shown = items.take(6).map((i) => '• ${i.time} · ${i.text}').join('\n');
  final more = items.length > 6 ? tr('\n…y ${items.length - 6} más.', '\n…and ${items.length - 6} more.') : '';
  return tr('$hi Hoy tienes:\n$shown$more$tasks', '$hi Today you have:\n$shown$more$tasks');
}

/// Da el resumen una vez al día, la primera vez que la app está despierta
/// desde las [fromHour] (si dormiste el Mac, al volver a usarlo).
class BriefingController extends StateNotifier<String?> {
  static const _key = 'briefing.lastDay';
  static const fromHour = 6;

  final SharedPreferences? _prefs;
  final bool Function() enabled;
  final Future<String> Function(DateTime now) compose;
  final DateTime Function() _now;
  Timer? _timer;
  Timer? _first;
  bool _busy = false;

  BriefingController(this._prefs,
      {required this.enabled,
      required this.compose,
      DateTime Function()? now,
      Duration every = const Duration(minutes: 1)})
      : _now = now ?? DateTime.now,
        super(null) {
    // Sin dónde guardar el día (pruebas), no hay resumen.
    if (_prefs == null) return;
    _timer = Timer.periodic(every, (_) => check());
    // Al abrir la app, un momento después (para no tapar el saludo).
    _first = Timer(const Duration(seconds: 20), check);
  }

  /// Si toca, prepara el resumen (y lo pone como estado). Devuelve si lo dio.
  Future<bool> check() async {
    final now = _now();
    if (_prefs == null || _busy || !enabled() || now.hour < fromHour) {
      return false;
    }
    final today = dayKey(now);
    if (_prefs?.getString(_key) == today) return false;
    _busy = true;
    try {
      await _prefs?.setString(_key, today);
      final message = await compose(now);
      if (mounted) state = message;
      return true;
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _first?.cancel();
    super.dispose();
  }
}

/// Se sobrescribe en `main()` con las preferencias guardadas.
final briefingPrefsProvider = Provider<SharedPreferences?>((_) => null);

final briefingProvider =
    StateNotifierProvider<BriefingController, String?>((ref) {
  return BriefingController(
    ref.watch(briefingPrefsProvider),
    enabled: () => ref.read(mascotSettingsProvider).morningBriefing,
    compose: (now) async {
      final notes = ref.read(calendarStoreProvider);
      var mac = const <CalendarEvent>[];
      if (notes.toMac) {
        try {
          mac = await ref.read(macActionsProvider).events(0);
        } catch (_) {}
      }
      final store = ref.read(personalStoreProvider);
      return briefingMessage(
        userName: ref.read(userNameProvider),
        items: agendaFor(now,
            notes: notes,
            daily: ref.read(dailyTaskStoreProvider),
            reminders: store.reminders,
            macEvents: mac),
        pending: store.pending.length,
      );
    },
  );
});
