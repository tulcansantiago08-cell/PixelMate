import '../../core/i18n/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/calendar_notes.dart';
import '../../application/assistant/daily_tasks.dart';
import '../../application/assistant/mac_actions.dart';
import '../../application/assistant/personal_store.dart';
import '../../infrastructure/desktop/native_effects.dart';
import '../stats/stats_style.dart';
import 'time_field.dart';

/// Los colores para marcar notas (mismo orden que [calendarColorNames]).
const calendarColors = [
  Color(0xFFFF8A3D), // naranja
  Color(0xFF4F9DFF), // azul
  Color(0xFF34D399), // verde
  Color(0xFFA78BFA), // morado
  Color(0xFFF472B6), // rosa
  Color(0xFFFACC15), // amarillo
  Color(0xFF94A3B8), // gris (los recordatorios del chat)
];

/// Los recordatorios del chat se marcan en este color.
final _reminderColor = calendarColors[reminderColor];

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Calendario del mes: cada día con algo anotado se pinta del color de lo
/// que anotaste. Al elegir un día se ve lo que tiene (tus notas, los
/// recordatorios, las tareas diarias y, si está activado, tu Calendario del
/// Mac) y se pueden anotar cosas: todo el día o a una hora, con color, y
/// ese día te avisa.
class CalendarTab extends ConsumerStatefulWidget {
  /// Para pruebas: el "hoy" del calendario.
  final DateTime? today;
  const CalendarTab({super.key, this.today});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<CalendarTab> {
  late DateTime _now = widget.today ?? DateTime.now();
  late DateTime _month = DateTime(_now.year, _now.month);
  late DateTime _selected = DateTime(_now.year, _now.month, _now.day);

  bool _adding = false;
  final _text = TextEditingController();
  bool _allDay = true;
  int _hour = 9;
  int _minute = 0;
  bool _alarm = false;
  int _color = 1;
  NoteRepeat _repeat = NoteRepeat.none;
  String? _problem;

  /// La nota que se está cambiando (`null`: una nueva).
  CalendarNote? _editing;

  /// Aviso tras guardar (por ejemplo, sin permiso para el Calendario).
  String? _notice;

  /// Eventos del Calendario del Mac del día elegido.
  Future<List<CalendarEvent>>? _macEvents;
  DateTime? _macDay;

  /// Escribir directo en el día elegido (nota de todo el día).
  final _quick = TextEditingController();
  final _quickFocus = FocusNode();

  @override
  void dispose() {
    _quick.dispose();
    _quickFocus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Anota lo escrito en el campo rápido: todo el día, con el color elegido.
  Future<void> _quickSave() async {
    final text = _quick.text.trim();
    if (text.isEmpty) return;
    _now = widget.today ?? DateTime.now();
    final store = ref.read(calendarStoreProvider);
    final note = await store.add(text, _selected, color: _color, now: _now);
    String? notice;
    if (note != null && store.toMac) {
      notice =
          await copyToMacCalendar(store, ref.read(macActionsProvider), note);
    }
    if (!mounted) return;
    _quick.clear();
    setState(() {
      _notice = notice;
      _macDay = null;
    });
    _quickFocus.requestFocus(); // para seguir anotando
  }

  /// Abre el formulario completo (con hora y alarma) con lo ya escrito.
  void _openForm() {
    focusApp();
    setState(() {
      _editing = null;
      _text.text = _quick.text;
      _quick.clear();
      _adding = true;
      _problem = null;
      _notice = null;
    });
  }

  /// Abre [note] para cambiarla.
  void _edit(CalendarNote note) {
    focusApp();
    setState(() {
      _editing = note;
      _text.text = note.text;
      _allDay = note.allDay;
      _hour = note.hour ?? 9;
      _minute = note.allDay ? 0 : note.minute;
      _alarm = note.alarm;
      _color = note.color;
      _repeat = note.repeat;
      _adding = true;
      _problem = null;
      _notice = null;
    });
  }

  void _resetForm() {
    _text.clear();
    _editing = null;
    _allDay = true;
    _alarm = false;
    _repeat = NoteRepeat.none;
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) {
      setState(() => _problem = tr('Escribe qué quieres anotar.', 'Write what you want to note.'));
      return;
    }
    _now = widget.today ?? DateTime.now();
    final editing = _editing;
    final day = editing?.day ?? _selected;
    if (!_allDay && _repeat == NoteRepeat.none) {
      final when = DateTime(day.year, day.month, day.day, _hour, _minute);
      if (!when.isAfter(_now)) {
        setState(() => _problem = tr('Esa hora ya pasó: elige otra.', 'That time has passed: choose another.'));
        return;
      }
    }
    final store = ref.read(calendarStoreProvider);
    final mac = ref.read(macActionsProvider);
    String? notice;
    if (editing != null) {
      notice = await editNote(
          store,
          mac,
          editing.copyWith(
            text: text,
            allDay: _allDay,
            hour: _hour,
            minute: _allDay ? 0 : _minute,
            alarm: _alarm,
            color: _color,
            repeat: _repeat,
          ),
          now: _now);
    } else {
      final note = await store.add(text, day,
          hour: _allDay ? null : _hour,
          minute: _minute,
          alarm: _alarm,
          color: _color,
          repeat: _repeat,
          now: _now);
      if (note != null && store.toMac) {
        notice = await copyToMacCalendar(store, mac, note);
      }
    }
    if (!mounted) return;
    setState(() {
      _adding = false;
      _problem = null;
      _notice = notice;
      // La siguiente empieza otra vez como nota de todo el día.
      _resetForm();
      _macDay = null; // vuelve a leer el Calendario del Mac
    });
  }

  @override
  Widget build(BuildContext context) {
    // "Hoy" al día (por si el panel sigue abierto pasada la medianoche).
    _now = widget.today ?? DateTime.now();
    final reminders = ref.watch(personalStoreProvider);
    final notes = ref.watch(calendarStoreProvider);
    final daily = ref.watch(dailyTaskStoreProvider);
    return ListenableBuilder(
      listenable: reminders,
      builder: (context, _) {
        final dated = reminders.reminders;
        return ListView(
          padding: const EdgeInsets.only(right: 4, top: 4),
          children: [
            _header(),
            _grid(notes, dated),
            const SizedBox(height: 8),
            if (_adding) _form(notes) else ..._day(notes, dated, daily),
          ],
        );
      },
    );
  }

  Widget _header() {
    void move(int months) =>
        setState(() => _month = DateTime(_month.year, _month.month + months));
    Widget arrow(String key, IconData icon, String tip, int delta) => Tooltip(
          message: tip,
          child: InkWell(
            key: ValueKey(key),
            customBorder: const CircleBorder(),
            onTap: () => move(delta),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x0DFFFFFF),
                border: Border.all(color: StatsStyle.glassBorder),
              ),
              child: Icon(icon, size: 18, color: StatsStyle.textPrimary),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 10),
      // Un brillo del color de acento detrás del mes.
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1.4),
          radius: 1.1,
          colors: [
            StatsStyle.accent.withValues(alpha: 0.5),
            StatsStyle.accent.withValues(alpha: 0),
          ],
        ),
      ),
      child: Row(children: [
        arrow('cal-prev', Icons.chevron_left_rounded, tr('Mes anterior', 'Previous month'), -1),
        Expanded(
          child: Text(
            '${monthNames[_month.month - 1][0].toUpperCase()}${monthNames[_month.month - 1].substring(1)} ${_month.year}',
            key: const ValueKey('cal-month'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: StatsStyle.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
        ),
        arrow('cal-next', Icons.chevron_right_rounded, tr('Mes siguiente', 'Next month'), 1),
      ]),
    );
  }

  /// Los colores de lo anotado ese día (sin repetir, en orden).
  List<Color> _colorsOn(
      DateTime day, CalendarStore notes, List<ReminderItem> dated) {
    final colors = <Color>[
      for (final n in notes.onDay(day)) calendarColors[n.color],
      if (dated.any((r) => _sameDay(r.due, day))) _reminderColor,
    ];
    return colors.toSet().toList();
  }

  static List<String> get _weekdayShort => tr('es', 'en') == 'en'
      ? const ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']
      : const ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];

  Widget _grid(CalendarStore notes, List<ReminderItem> dated) {
    final first = DateTime(_month.year, _month.month);
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final blanks = first.weekday - 1; // la semana empieza en lunes
    final cells = <Widget>[
      for (final l in _weekdayShort)
        Center(
            child: Text(l,
                style: const TextStyle(
                    color: StatsStyle.textMuted,
                    fontSize: 10,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600))),
      // Los últimos días del mes anterior, apagados.
      for (var i = blanks; i > 0; i--)
        Center(
          child: Text('${DateTime(_month.year, _month.month, 1 - i).day}',
              style: const TextStyle(color: Color(0x33FFFFFF), fontSize: 14)),
        ),
      for (var d = 1; d <= days; d++)
        _cell(DateTime(_month.year, _month.month, d),
            _colorsOn(DateTime(_month.year, _month.month, d), notes, dated)),
    ];
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.05,
      children: cells,
    );
  }

  Widget _cell(DateTime day, List<Color> colors) {
    final selected = _sameDay(day, _selected);
    final today = _sameDay(day, _now);
    final past = day.isBefore(DateTime(_now.year, _now.month, _now.day));
    return Semantics(
      button: true,
      selected: selected,
      excludeSemantics: true,
      label: dayOfMonth(day) +
          (today ? tr(', hoy', ', today') : '') +
          (colors.isEmpty ? '' : tr(', con cosas anotadas', ', with notes')),
      child: InkWell(
        key: ValueKey('cal-day-${day.day}'),
        customBorder: const CircleBorder(),
        onTap: () {
          setState(() {
            _selected = day;
            _adding = false;
            _notice = null;
          });
          // Elegir un día y escribir: el teclado va directo a su campo.
          if (!past) {
            focusApp();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _quickFocus.requestFocus());
          }
        },
        child: Center(
          child: SizedBox(
            width: 34,
            height: 38,
            child: Stack(alignment: Alignment.center, children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? StatsStyle.accent : null,
                  border: today && !selected
                      ? Border.all(color: StatsStyle.accentLight, width: 1.5)
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: StatsStyle.accent.withValues(alpha: 0.6),
                              blurRadius: 14,
                              spreadRadius: 1),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text('${day.day}',
                    style: TextStyle(
                        color: selected
                            ? Colors.white
                            : past
                                ? StatsStyle.textMuted
                                : StatsStyle.textPrimary,
                        fontSize: 14,
                        fontWeight: selected || today
                            ? FontWeight.w600
                            : FontWeight.w400)),
              ),
              // Lo anotado ese día: un punto de cada color, debajo.
              if (colors.isNotEmpty)
                Positioned(
                  bottom: 0,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final c in colors.take(3))
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration:
                            BoxDecoration(shape: BoxShape.circle, color: c),
                      ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _day(
      CalendarStore notes, List<ReminderItem> dated, DailyTaskStore daily) {
    final mine = notes.onDay(_selected);
    final items = dated.where((r) => _sameDay(r.due, _selected)).toList();
    final routine = [
      for (final t in daily.tasks)
        if (t.enabled && t.days.contains(_selected.weekday)) t
    ];
    final isToday = _sameDay(_selected, _now);
    final past = _selected.isBefore(DateTime(_now.year, _now.month, _now.day));
    final mac = ref.read(macActionsProvider);
    final store = ref.read(personalStoreProvider);
    if (notes.toMac && (_macDay == null || !_sameDay(_macDay!, _selected))) {
      _macDay = _selected;
      final offset =
          DateTime.utc(_selected.year, _selected.month, _selected.day)
              .difference(DateTime.utc(_now.year, _now.month, _now.day))
              .inDays;
      _macEvents = mac.events(offset).catchError((_) => <CalendarEvent>[]);
    }
    final macIds = {for (final n in notes.notes) n.macId};
    return [
      Row(children: [
        Expanded(
          child: Text(
            calendarLongDate(_selected),
            key: const ValueKey('cal-selected'),
            style: const TextStyle(
                color: StatsStyle.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ),
        if (!past)
          TextButton(
            key: const ValueKey('cal-add'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: _openForm,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.schedule_rounded, size: 14),
              const SizedBox(width: 4),
              Text(tr('Con hora', 'With time'), style: const TextStyle(fontSize: 11)),
            ]),
          ),
      ]),
      if (!past) _quickRow(),
      if (_notice != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(_notice!,
              key: const ValueKey('cal-notice'),
              style: const TextStyle(color: Colors.amber, fontSize: 11)),
        ),
      if (mine.isEmpty && items.isEmpty && routine.isEmpty && !notes.toMac)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(tr('Nada para este día.', 'Nothing for this day.'),
              style: const TextStyle(color: StatsStyle.textMuted, fontSize: 11)),
        ),
      for (final n in mine)
        _row(
          key: ValueKey('cal-note-${n.id}'),
          color: calendarColors[n.color],
          icon: n.alarm
              ? Icons.notifications_active_outlined
              : (n.macId != null ? Icons.event_available_outlined : null),
          time: n.timeLabel,
          text: n.repeat == NoteRepeat.none
              ? n.text
              : '${n.text} · ${n.repeat.label}',
          onTap: () => _edit(n),
          onDelete: () => removeNote(notes, mac, n),
        ),
      for (final r in items)
        _row(
          key: ValueKey('cal-item-${r.id}'),
          color: _reminderColor,
          icon: r.alarm
              ? Icons.notifications_active_outlined
              : Icons.schedule_rounded,
          time: clock12(r.due.hour, r.due.minute),
          text: r.text,
          onDelete: () => store.removeReminder(r.id),
        ),
      for (final t in routine)
        _row(
          key: ValueKey('cal-daily-${t.id}'),
          icon: isToday && t.doneToday(_now)
              ? Icons.check_circle_outline_rounded
              : Icons.repeat_rounded,
          time: t.time12,
          text: tr('${t.text} (diaria)', '${t.text} (daily)'),
        ),
      if (notes.toMac)
        FutureBuilder<List<CalendarEvent>>(
          future: _macEvents,
          builder: (context, snap) {
            final events = [
              for (final e in snap.data ?? const <CalendarEvent>[])
                if (!macIds.contains(e.id)) e
            ];
            if (events.isEmpty) return const SizedBox();
            return Column(children: [
              for (final e in events)
                _row(
                  key: ValueKey('cal-mac-${e.id}-${e.title}'),
                  icon: Icons.event_available_outlined,
                  time: e.allDay
                      ? tr('Todo el día', 'All day')
                      : clock12(e.start.hour, e.start.minute),
                  text: e.title,
                ),
            ]);
          },
        ),
    ];
  }

  /// Escribir y ↩: se anota en el día elegido (todo el día), del color
  /// marcado. «Con hora» abre el formulario completo.
  Widget _quickRow() => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('cal-quick'),
              controller: _quick,
              focusNode: _quickFocus,
              onTap: focusApp,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: tr('Anotar en este día', 'Note on this day'),
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(Icons.edit_note,
                      size: 18, color: calendarColors[_color]),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                suffixIcon: IconButton(
                  key: const ValueKey('cal-quick-save'),
                  tooltip: tr('Anotar', 'Note'),
                  visualDensity: VisualDensity.compact,
                  onPressed: _quickSave,
                  icon: const Icon(Icons.check,
                      size: 18, color: StatsStyle.textSecondary),
                ),
              ),
              onSubmitted: (_) => _quickSave(),
            ),
            const SizedBox(height: 4),
            _colorPicker(size: 16),
          ],
        ),
      );

  Widget _colorPicker({double size = 22}) => Wrap(spacing: 6, children: [
        for (var i = 0; i < calendarColors.length; i++)
          Tooltip(
            message: calendarColorNames[i],
            child: InkWell(
              key: ValueKey('cal-color-$i'),
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _color = i),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: calendarColors[i],
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: _color == i ? Colors.white : Colors.transparent,
                      width: 2),
                ),
                child: _color == i
                    ? Icon(Icons.check, size: size * 0.6, color: Colors.white)
                    : null,
              ),
            ),
          ),
      ]);

  Widget _row(
          {required Key key,
          Color? color,
          IconData? icon,
          required String time,
          required String text,
          VoidCallback? onTap,
          VoidCallback? onDelete}) =>
      InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: color ?? StatsStyle.grid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 66,
                child: Text(time,
                    style: const TextStyle(
                        color: StatsStyle.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
              if (icon != null)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Icon(icon, size: 14, color: StatsStyle.accentLight),
                ),
              Expanded(
                child: Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: StatsStyle.textSecondary, fontSize: 11)),
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: tr('Borrar', 'Delete'),
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline,
                      size: 16, color: StatsStyle.textMuted),
                ),
            ]),
          ));

  Widget _form(CalendarStore notes) {
    const small = TextStyle(color: StatsStyle.textSecondary, fontSize: 11);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _editing == null
              ? tr('Anotar el ${dayOfMonth(_selected)}', 'Note on ${dayOfMonth(_selected)}')
              : tr('Cambiar la nota', 'Change the note'),
          style: const TextStyle(
              color: StatsStyle.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
        TextField(
          key: const ValueKey('cal-text'),
          controller: _text,
          autofocus: true,
          onTap: focusApp,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            hintText: tr('¿Qué quieres anotar?', 'What do you want to note?'),
            hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
            isDense: true,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 6),
        Text(tr('Color', 'Color'), style: small),
        const SizedBox(height: 2),
        _colorPicker(),
        const SizedBox(height: 6),
        Text(tr('Repetir', 'Repeat'), style: small),
        Wrap(spacing: 4, children: [
          for (final r in NoteRepeat.values)
            ChoiceChip(
              key: ValueKey('cal-repeat-${r.name}'),
              label: Text(r == NoteRepeat.none ? 'No' : r.label,
                  style: const TextStyle(fontSize: 11)),
              selected: _repeat == r,
              visualDensity: VisualDensity.compact,
              showCheckmark: false,
              onSelected: (_) => setState(() => _repeat = r),
            ),
        ]),
        SwitchListTile(
          key: const ValueKey('cal-allday'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
              _allDay
                  ? tr('Todo el día (te aviso a las ${clock12(CalendarNote.noticeHour, 0)})', "All day (I'll remind you at ${clock12(CalendarNote.noticeHour, 0)})")
                  : tr('Todo el día', 'All day'),
              style: small),
          value: _allDay,
          onChanged: (v) => setState(() => _allDay = v),
        ),
        if (!_allDay) ...[
          TimeField(
            keyPrefix: 'cal',
            hour: _hour,
            minute: _minute,
            onChanged: (h, m) => setState(() {
              _hour = h;
              _minute = m;
            }),
          ),
          SwitchListTile(
            key: const ValueKey('cal-alarm'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
                _alarm
                    ? tr('Con alarma (suena hasta apagarla)', 'With alarm (rings until you turn it off)')
                    : tr('Con alarma (si no, solo un aviso)', 'With alarm (otherwise, just a notice)'),
                style: small),
            value: _alarm,
            onChanged: (v) => setState(() => _alarm = v),
          ),
        ],
        SwitchListTile(
          key: const ValueKey('cal-mac'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(tr('También en el Calendario del Mac', 'Also in the Mac Calendar'), style: small),
          value: notes.toMac,
          onChanged: (v) => notes.setToMac(v),
        ),
        if (_problem != null)
          Text(_problem!,
              key: const ValueKey('cal-problem'),
              style: const TextStyle(color: Colors.amber, fontSize: 11)),
        Row(children: [
          TextButton(
            onPressed: () => setState(() {
              _adding = false;
              _resetForm();
            }),
            child: Text(tr('Cancelar', 'Cancel'), style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          FilledButton(
            key: const ValueKey('cal-save'),
            onPressed: _save,
            child: Text(tr('Guardar', 'Save'), style: const TextStyle(fontSize: 12)),
          ),
        ]),
      ],
    );
  }
}
