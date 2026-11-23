part of '../command_parser.dart';

// Alarmas: «pon una alarma a las 8 am reunión», «apaga la alarma».

/// Alarmas ([m] es [original] sin tildes). Ver [AssistantIntent.alarm].
ParsedCommand? _alarmCommand(String original, String m, DateTime now) {
  final t = m
      .replaceAll(RegExp(r'[¡!¿?.,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const theAlarm = r'(?:la\s+|esa\s+|esta\s+|las\s+)?alarmas?';

  // Mientras suena.
  if (RegExp('^(?:apaga|apagala|para|parala|deten|detenla|quita|quitala|silencia|silenciala|calla)(?:\\s+$theAlarm)?(?:\\s+ya)?\$')
          .hasMatch(t) &&
      (t.contains('alarma') ||
          RegExp(r'^(?:apagala|parala|detenla|quitala|silenciala)(?:\s+ya)?$')
              .hasMatch(t))) {
    return const ParsedCommand(AssistantIntent.alarmStop);
  }
  final snooze = RegExp(
          r'^(?:pospon(?:la|lo)?|posponer|aplaza(?:la)?|(?:dame|deja(?:me)?)\s+(?:dormir\s+)?|(?:otros?|unos?)\s+)?(?:(\d{1,2}|[a-z]+)\s+)?(?:minutos?|min)\s*(?:mas)?$|^(?:pospon(?:la|lo)?|posponer|aplaza(?:la)?|snooze)(?:\s+(?:la\s+)?alarma)?(?:\s+(\d{1,2}|[a-z]+)\s*(?:minutos?|min))?$')
      .firstMatch(t);
  if (snooze != null &&
      (t.startsWith('pospon') ||
          t.startsWith('aplaza') ||
          t.startsWith('snooze') ||
          t.endsWith('mas') ||
          t.startsWith('dame') ||
          t.startsWith('deja'))) {
    final n = snooze.group(1) ?? snooze.group(2);
    return ParsedCommand(AssistantIntent.alarmSnooze,
        number: n == null ? null : _num(n));
  }

  // Borrar una alarma guardada.
  if (RegExp(
          '^(?:quita|borra|elimina|cancela|desactiva|apaga)\\s+$theAlarm\\b.+')
      .hasMatch(t)) {
    final rest = t.replaceFirst(
        RegExp(
            '^(?:quita|borra|elimina|cancela|desactiva|apaga)\\s+$theAlarm\\s*(?:de\\s+|para\\s+)?'),
        '');
    final hour =
        RegExp(r'(?:las?\s+)?(\d{1,2})(?:[:.](\d{2}))?').firstMatch(rest);
    return ParsedCommand(AssistantIntent.alarmDelete,
        text: hour != null && rest.startsWith(RegExp(r'(?:las?\s+)?\d'))
            ? ''
            : rest,
        number: hour == null
            ? null
            : int.parse(hour.group(1)!) * 100 +
                int.parse(hour.group(2) ?? '0'));
  }

  // Poner una alarma.
  // "Pon una alarma…", "dame una alarma…", y también con la hora antes
  // ("a las 9 dame una alarma para…").
  const alarmVerbs =
      r'(?:pon(?:me|le)?|programa(?:me)?|crea(?:me)?|activa(?:me)?|agrega(?:me)?|anade(?:me)?|configura(?:me)?|dame|hazme|haz|quiero|necesito|coloca(?:me)?|establece|fija(?:me)?|ajusta(?:me)?)';
  final set =
      RegExp('^(?:$alarmVerbs\\s+)?(?:una?\\s+|la\\s+)?(?:nueva\\s+)?alarma\\b|^(?:despiertame|levantame)\\b|\\btareas? diarias?\\b|\\b$alarmVerbs\\s+(?:una?\\s+)?(?:nueva\\s+)?alarma\\b')
          .firstMatch(t);
  final remindWithAlarm =
      RegExp(r'^(?:recuerdame|avisame)\b.*\bcon (?:alarma|sonido)\b')
          .hasMatch(t);
  if (set == null && !remindWithAlarm) return null;
  final wakeUp = RegExp(r'^(?:despiertame|levantame)').hasMatch(t);

  String? repeat;
  if (RegExp(
          r'\b(?:todos los dias|cada dia|diaria|diarias|diariamente|siempre)\b')
      .hasMatch(t)) {
    repeat = 'daily';
  }
  if (RegExp(
          r'\b(?:de lunes a viernes|entre semana|dias de semana|dias laborables|dias habiles)\b')
      .hasMatch(t)) {
    repeat = 'weekdays';
  }

  const repeatPhrase =
      r'\b(?:(?:una?\s+|la\s+|mi\s+)?(?:nueva\s+)?tareas? diarias?|todos los d[ií]as|cada d[ií]a|diariamente|diaria|siempre|de lunes a viernes|entre semana|d[ií]as de semana|d[ií]as laborables|d[ií]as h[aá]biles|con (?:alarma|sonido))\b';
  final withoutRepeat =
      original.replaceAll(RegExp(repeatPhrase, caseSensitive: false), ' ');
  final when = alarmTime(withoutRepeat, now, morning: wakeUp);

  // El texto: sin la orden, la hora ni la repetición.
  var text = withoutRepeat;
  final verb = RegExp(
          r'(?:(?:pon(?:me|le)?|programa(?:me)?|crea(?:me)?|activa(?:me)?|agrega(?:me)?|añade(?:me)?|anade(?:me)?|configura(?:me)?|dame|hazme|haz|quiero|necesito|coloca(?:me)?|establece|fija(?:me)?|ajusta(?:me)?)\s+)?(?:una?\s+|la\s+)?(?:nueva\s+)?alarma\b|^(?:despiértame|despiertame|levántame|levantame|recuérdame|recuerdame|avísame|avisame)\b',
          caseSensitive: false)
      .firstMatch(text);
  if (verb != null) {
    text = '${text.substring(0, verb.start)} ${text.substring(verb.end)}';
  }
  // "…de hoy", "…para hoy".
  text = text.replaceAll(
      RegExp(r'\b(?:de hoy|para hoy)\b', caseSensitive: false), ' ');
  text = text.replaceAll(
      RegExp(r'\b(?:am|a\.m\.|pm|p\.m\.)(?=\s|$)', caseSensitive: false), ' ');
  text = cleanText(text)
      .replaceFirst(
          RegExp(
              r'^(?:(?:agrega(?:me)?|añade(?:me)?|anade(?:me)?|apunta(?:me)?|anota(?:me)?|crea(?:me)?|pon(?:me)?|programa(?:me)?|para|de|que diga|que se llame|se llame|que se llama|se llama|llamada|con el nombre(?: de)?|con el texto|y|:)\s+)+(?:(?:la|el)\s+)?',
              caseSensitive: false),
          '')
      .trim();
  text = cleanText(text);
  if (text.isEmpty) text = wakeUp ? '¡Hora de levantarse! ☀️' : 'Alarma';
  return ParsedCommand(AssistantIntent.alarm,
      text: text, when: when, repeat: repeat);
}

/// La hora de una alarma. Si no dice mañana o tarde ("a las 7"), la más
/// próxima de las dos (las 7 de la mañana o de la tarde); con
/// [morning] ("despiértame a las 6"), de la mañana.
DateTime? alarmTime(String message, DateTime now, {bool morning = false}) {
  final when = parseWhen(message, now);
  if (when == null) return null;
  final m = fold(message);
  final time = RegExp(r'\ba las?\s+(\d{1,2})').firstMatch(m);
  final explicitPart = RegExp(
          r'\b(?:de la manana|de la tarde|de la noche|am|a\.m|pm|p\.m|mediodia|medianoche|esta tarde|esta noche)\b')
      .hasMatch(m);
  if (time == null || explicitPart) return when;
  final said = int.parse(time.group(1)!);
  if (said < 1 || said > 12) return when;
  final morningHour = said == 12 ? 0 : said;
  final candidates = [morningHour, said == 12 ? 12 : said + 12];
  final explicitDay = RegExp(
          r'\b(?:hoy|manana|pasado manana|lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b')
      .hasMatch(m.replaceAll('de la manana', ''));
  DateTime at(int hour, int dayShift) =>
      DateTime(when.year, when.month, when.day + dayShift, hour, when.minute);
  if (morning) {
    var d = at(morningHour, 0);
    if (!explicitDay && !d.isAfter(now)) {
      d = DateTime(now.year, now.month, now.day + 1, morningHour, when.minute);
      if (DateTime(now.year, now.month, now.day, morningHour, when.minute)
          .isAfter(now)) {
        d = DateTime(now.year, now.month, now.day, morningHour, when.minute);
      }
    }
    return d;
  }
  if (explicitDay) return when;
  // Sin día: la próxima de las dos horas posibles.
  final options = <DateTime>[
    for (final h in candidates)
      for (final day in [0, 1])
        DateTime(now.year, now.month, now.day + day, h, when.minute),
  ].where((d) => d.isAfter(now)).toList()
    ..sort();
  return options.first;
}
