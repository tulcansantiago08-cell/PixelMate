part of '../command_parser.dart';

// Anotar en el calendario: «anota en mi calendario el viernes…».

const _monthNumbers = {
  'enero': 1,
  'febrero': 2,
  'marzo': 3,
  'abril': 4,
  'mayo': 5,
  'junio': 6,
  'julio': 7,
  'agosto': 8,
  'septiembre': 9,
  'setiembre': 9,
  'octubre': 10,
  'noviembre': 11,
  'diciembre': 12,
};

final _noteVerb = RegExp(
    r'^(?:anota|apunta|escribe|pon|agrega|anade|guarda|marca)(?:me|lo|la)?\b');
final _noteWhere = RegExp(r'\b(?:en|a|al)\s+(?:el\s+|mi\s+)?calendario\b');
final _noteTime = RegExp(
    r'\ba las?\s+\d{1,2}(?:[:.]\d{2})?(?:\s*y\s*(?:media|cuarto|\d{1,2})(?:\s*minutos?)?)?'
    r'(?:\s*(?:de la (?:manana|tarde|noche)|am|pm|a\.\s?m\.|p\.\s?m\.))?');
final _noteDate = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b'
    r'|\b(?:para\s+)?(?:el\s+)?(?:dia\s+)?(\d{1,2})(?:\s+de\s+([a-z]+))?(?:\s+de\s+(\d{4}))?\b');
final _noteRelative = RegExp(r'\b(?:para\s+)?(pasado manana|manana|hoy)\b');
final _noteWeekday = RegExp(
    r'\b(?:para\s+)?(?:el\s+)?(?:proximo\s+)?(lunes|martes|miercoles|jueves|viernes|sabado|domingo)(?:\s+que viene)?\b');

/// El día de una nota: "hoy", "mañana", "el viernes", "el 20 (de
/// noviembre)", "20/11". `null` si no dice día.
({DateTime day, Match match})? _noteDay(String m, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final rel = _noteRelative.firstMatch(m);
  if (rel != null) {
    final d = switch (rel.group(1)) {
      'pasado manana' => 2,
      'manana' => 1,
      _ => 0,
    };
    return (day: DateTime(today.year, today.month, today.day + d), match: rel);
  }
  final wd = _noteWeekday.firstMatch(m);
  if (wd != null) {
    var d = (_weekdays[wd.group(1)]! - now.weekday) % 7;
    if (d == 0) d = 7;
    return (day: DateTime(today.year, today.month, today.day + d), match: wd);
  }
  for (final date in _noteDate.allMatches(m)) {
    final slash = date.group(1) != null;
    final n = int.parse(slash ? date.group(1)! : date.group(4)!);
    final monthWord = slash ? null : date.group(5);
    int? month = slash ? int.parse(date.group(2)!) : null;
    if (monthWord != null) {
      month = _monthNumbers[monthWord];
      if (month == null) continue; // "el 3 de la tarde"…
    }
    // Un número suelto solo cuenta con "el" delante ("el 20").
    if (!slash &&
        monthWord == null &&
        !RegExp(r'^(?:para\s+)?(?:el|dia)\s').hasMatch(date.group(0)!)) {
      continue;
    }
    if (n < 1 || n > 31 || (month != null && (month < 1 || month > 12))) {
      continue;
    }
    final yearText = slash ? date.group(3) : date.group(6);
    var year = yearText == null
        ? today.year
        : (yearText.length == 2
            ? 2000 + int.parse(yearText)
            : int.parse(yearText));
    var mo = month ?? today.month;
    var day = DateTime(year, mo, n);
    if (day.month != mo) continue; // 31 de febrero
    if (yearText == null && day.isBefore(today)) {
      // Ya pasó: el mes que viene (sin mes) o el año que viene.
      if (month == null) {
        mo += 1;
      } else {
        year += 1;
      }
      day = DateTime(year, mo, n);
    }
    return (day: day, match: date);
  }
  return null;
}

ParsedCommand? _calendarNote(String original, String m, DateTime now) {
  final verb = _noteVerb.firstMatch(m);
  final where = _noteWhere.firstMatch(m);
  if (verb == null || where == null) return null;
  final keep = List<bool>.filled(m.length, true);
  void drop(Match? x) {
    if (x == null) return;
    for (var i = x.start; i < x.end && i < keep.length; i++) {
      keep[i] = false;
    }
  }

  drop(verb);
  drop(where);
  final time = _noteTime.firstMatch(m);
  // La hora primero: "de la mañana" no es "mañana".
  final withoutTime = time == null
      ? m
      : m.replaceRange(time.start, time.end, ' ' * (time.end - time.start));
  final day = _noteDay(withoutTime, now);
  drop(time);
  drop(day?.match);
  final alarm = RegExp(r'\bcon alarma\b').firstMatch(m);
  drop(alarm);
  final every =
      RegExp(r'\b(?:cada|todos los|todas las)\s+(ano|anos|semana|semanas)\b')
          .firstMatch(m);
  drop(every);

  final b = StringBuffer();
  for (var i = 0; i < original.length && i < keep.length; i++) {
    b.write(keep[i] ? original[i] : ' ');
  }
  var text = b
      .toString()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(
          RegExp(r'^(?:que\s+(?:tengo\s+|hay\s+)?|de\s+|para\s+|:\s*)',
              caseSensitive: false),
          '')
      .replaceAll(RegExp(r'^[\s,.:;-]+|[\s,.:;-]+$'), '');
  if (text.isEmpty) return null;
  text = text[0].toUpperCase() + text.substring(1);

  DateTime? when = day?.day;
  var allDay = true;
  if (when != null && time != null) {
    final t = parseWhen(time.group(0)!, now);
    if (t != null) {
      when = DateTime(when.year, when.month, when.day, t.hour, t.minute);
      allDay = false;
    }
  }
  // Los cumpleaños y aniversarios se repiten cada año aunque no lo diga.
  final repeat = every != null
      ? (every.group(1)!.startsWith('ano') ? 'yearly' : 'weekly')
      : RegExp(r'\b(cumpleanos|aniversario)\b').hasMatch(fold(text))
          ? 'yearly'
          : null;
  return ParsedCommand(AssistantIntent.calendarNote,
      text: text,
      when: when,
      allDay: allDay,
      play: alarm != null,
      repeat: repeat);
}
