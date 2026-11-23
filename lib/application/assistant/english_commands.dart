import '../../core/i18n/language.dart';

/// Lleva órdenes comunes en inglés a su forma en español, para que el lector
/// de órdenes (que entiende español) las reconozca igual: «remind me in 20
/// minutes to call mom» → «recuérdame en 20 minutos to call mom».
///
/// Solo actúa con la app en inglés: en español el texto no se toca. Lo que la
/// persona quiere recordar o anotar se queda en sus palabras. El orden importa:
/// las frases largas van antes que las palabras sueltas que contienen.
String englishToSpanish(String text) {
  if (LanguageSettings.current != AppLanguage.en) return text;
  var t = text;
  for (final (pattern, spanish) in _phrases) {
    t = t.replaceAllMapped(pattern, (m) {
      var out = spanish;
      for (var i = 1; i <= m.groupCount; i++) {
        out = out.replaceAll('\$$i', m.group(i) ?? '');
      }
      return out;
    });
  }
  return t;
}

RegExp _re(String source) => RegExp('\\b(?:$source)\\b', caseSensitive: false);

final _phrases = <(RegExp, String)>[
  // Respuestas a «¿lo hago?».
  (_re(r'yes|yeah|yep|sure'), 'sí'),
  (_re(r'nope'), 'no'),
  // Cuándo.
  (_re(r'the day after tomorrow'), 'pasado mañana'),
  (_re(r'tomorrow'), 'mañana'),
  (_re(r'today'), 'hoy'),
  (_re(r'tonight'), 'hoy en la noche'),
  (_re(r'in (\d+) (?:minutes?|mins?)'), 'en \$1 minutos'),
  (_re(r'in (\d+) (?:hours?|hrs?)'), 'en \$1 horas'),
  (_re(r'in half an hour'), 'en media hora'),
  (_re(r'in an hour'), 'en una hora'),
  (_re(r'(\d+) more minutes'), '\$1 minutos más'),
  (_re(r'every day|daily'), 'todos los días'),
  (_re(r'monday to friday|on weekdays|weekdays'), 'de lunes a viernes'),
  (_re(r'(?:at|for) noon'), 'al mediodía'),
  (_re(r'at (\d{1,2}(?::\d{2})?)'), 'a las \$1'),
  (_re(r'on monday'), 'el lunes'),
  (_re(r'on tuesday'), 'el martes'),
  (_re(r'on wednesday'), 'el miércoles'),
  (_re(r'on thursday'), 'el jueves'),
  (_re(r'on friday'), 'el viernes'),
  (_re(r'on saturday'), 'el sábado'),
  (_re(r'on sunday'), 'el domingo'),
  // Recordatorios, alarmas y tareas.
  (_re(r'remind me(?: to)?'), 'recuérdame'),
  (_re(r'set an? alarm(?: for)?'), 'pon una alarma'),
  (_re(r'wake me up'), 'despiértame'),
  (_re(r'turn off the alarm|stop the alarm|alarm off'), 'apaga la alarma'),
  (_re(r'snooze(?: for)?'), 'pospón'),
  (_re(r'delete the alarm|remove the alarm'), 'quita la alarma'),
  (_re(r'add (?:a )?task|note down|write down|jot down|add to my list'), 'apunta'),
  (_re(r'take a note|take note'), 'toma nota'),
  (_re(r'mark (\d+) as done|i finished (?:task )?(\d+)'), 'marca la \$1\$2 como hecha'),
  (_re(r"what(?:'s| is) pending|what do i have pending|show my tasks|my to-?do list"), 'qué tengo pendiente'),
  (_re(r'what do i have'), 'qué tengo'),
  (_re(r'(?:add|put) (?:it )?(?:in|to|on) my calendar'), 'anota en mi calendario'),
  // Apps y web.
  (_re(r'open'), 'abre'),
  (_re(r'close|quit'), 'cierra'),
  (_re(r'hide'), 'oculta'),
  (_re(r'what apps (?:do i have|are) open'), 'qué apps tengo abiertas'),
  // Volumen.
  (_re(r'turn (?:the volume )?up(?: the volume)?|volume up|louder'), 'sube el volumen'),
  (_re(r'turn (?:the volume )?down(?: the volume)?|volume down|quieter'), 'baja el volumen'),
  (_re(r'set the volume to|volume to'), 'volumen al'),
  (_re(r'unmute'), 'activa el sonido'),
  (_re(r'mute'), 'silencia'),
  // Música y baile.
  (_re(r'pause the music'), 'pausa la música'),
  (_re(r'next song'), 'siguiente canción'),
  (_re(r'previous song'), 'canción anterior'),
  (_re(r'what song is playing'), 'qué canción suena'),
  (_re(r'play (.+?) on (youtube|spotify)'), 'reproduce \$1 en \$2'),
  (_re(r'play'), 'reproduce'),
  (_re(r'stop dancing'), 'para de bailar'),
  (_re(r'dance'), 'baila'),
  // Jornada y meta.
  (_re(r'start (?:my |a )?workday|start working'), 'empieza mi jornada'),
  (_re(r'start studying'), 'empieza a estudiar'),
  (_re(r'end (?:my |the )?workday|finish (?:my |the )?workday|stop working'), 'termina mi jornada'),
  (_re(r'pause (?:my |the )?workday'), 'pausa la jornada'),
  (_re(r'resume (?:my |the )?workday'), 'reanuda la jornada'),
  (_re(r'change my goal to (\d+) hours?'), 'cambia mi meta a \$1 horas'),
  // Cómo llamar a la persona.
  (_re(r'call me'), 'llámame'),
  (_re(r'my name is'), 'me llamo'),
];
