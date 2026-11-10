/// Intérprete de órdenes claras en español ("abre Spotify", "recuérdame en
/// 20 minutos…", "apunta…"). Es exacto e instantáneo; lo que no entiende lo
/// decide la IA.
library;

/// Qué pidió el usuario.
enum AssistantIntent {
  remind,
  addTask,
  completeTask,
  showPending,
  open,
  showAgenda,
  createEvent,
  createCode,
}

class ParsedCommand {
  final AssistantIntent intent;

  /// Recordatorio, tarea, app/web o título del evento.
  final String text;

  /// Cuándo (recordatorios y eventos).
  final DateTime? when;

  /// Número de tarea (1 = la primera), si lo dijo.
  final int? number;

  /// Para la agenda: 0 hoy, 1 mañana.
  final int dayOffset;

  /// Abrir: navegador pedido ("en Brave"), o `null` para el predeterminado.
  final String? browser;

  /// Abrir: buscar [text] dentro de este sitio ("youtube", "spotify",
  /// "google"), o `null` si es abrir una app o web sin más.
  final String? searchIn;

  /// "Reproduce X": darle play al primer resultado, no solo buscar.
  final bool play;

  /// Crear código: lenguaje ("python") y editor donde abrirlo ("Visual
  /// Studio Code"), o `null` para el predeterminado.
  final String? language;
  final String? editor;

  const ParsedCommand(this.intent,
      {this.text = '',
      this.when,
      this.number,
      this.dayOffset = 0,
      this.browser,
      this.searchIn,
      this.play = false,
      this.language,
      this.editor});

  @override
  String toString() => 'ParsedCommand($intent, "$text", $when, n=$number, '
      'd=$dayOffset, browser=$browser, in=$searchIn, play=$play, '
      'lang=$language, editor=$editor)';
}

/// Navegadores que se pueden pedir con "en …".
const browserNames = {
  'brave': 'Brave',
  'safari': 'Safari',
  'chrome': 'Chrome',
  'google chrome': 'Chrome',
  'firefox': 'Firefox',
  'arc': 'Arc',
  'edge': 'Edge',
  'opera': 'Opera',
};

final _browserPhrase = RegExp(
    r'\s*\b(?:en|con|desde)\s+(?:el\s+)?(?:navegador\s+)?(google chrome|brave|safari|chrome|firefox|arc|edge|opera)\b');

/// "una canción de Bad Bunny en YouTube" → (youtube, "Bad Bunny").
final _searchPhrase = RegExp(
    r'^(?:(?:una?|la|el|los|las)\s+)?(?:(?:cancion(?:es)?|video(?:s)?|musica|tema|tutorial|playlist|lista)\s+)?(?:(?:de|del|sobre)\s+)?(.*?)\s*\b(?:en|de)\s+(youtube|spotify|google)\s*$');

final _siteSuffix = RegExp(r'\s*\b(?:en|de)\s+(?:youtube|spotify|google)\s*$');

/// Abrir algo: app, web, búsqueda en un sitio, con navegador opcional.
/// [what] es el texto tras el verbo, tal como lo escribió el usuario.
ParsedCommand? _openCommand(String what,
    {bool play = false, bool defaultYoutube = false}) {
  var original = what.trim();
  var folded = fold(original);
  String? browser;
  final b = _browserPhrase.firstMatch(folded);
  if (b != null) {
    browser = browserNames[b.group(1)!];
    original =
        (original.substring(0, b.start) + original.substring(b.end)).trim();
    folded = fold(original);
  }
  final search = _searchPhrase.firstMatch(folded);
  if (search != null) {
    final site = search.group(2)!;
    // El grupo de la búsqueda termina justo antes de " en youtube" (fold no
    // cambia la longitud, así que las posiciones valen para el original).
    final q = search.group(1)!;
    final end = _siteSuffix.firstMatch(folded)!.start;
    final query = cleanText(original.substring(end - q.length, end));
    // "abre youtube" o "una canción en YouTube" sin nada que buscar: el sitio.
    return ParsedCommand(AssistantIntent.open,
        text: query.isEmpty ? site : query,
        browser: browser,
        searchIn: query.isEmpty ? null : site,
        play: play && query.isNotEmpty);
  }
  if (defaultYoutube) {
    // "reproduce Despacito": sin sitio, en YouTube.
    final query = cleanText(original.replaceFirst(
        RegExp(
            r'^(?:(?:una?|la|el)\s+)?(?:(?:cancion|canción|video|vídeo|musica|música|tema)\s+)?(?:de\s+)?(?:algo\s+de\s+)?',
            caseSensitive: false),
        ''));
    if (query.isNotEmpty) {
      return ParsedCommand(AssistantIntent.open,
          text: query, browser: browser, searchIn: 'youtube', play: play);
    }
  }
  final name = cleanText(original);
  if (name.isEmpty) {
    return browser == null
        ? null
        : ParsedCommand(AssistantIntent.open, text: browser);
  }
  return ParsedCommand(AssistantIntent.open, text: name, browser: browser);
}

/// Quita tildes y pasa a minúsculas, para comparar.
String fold(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunaeiouun';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

const _numbers = {
  'un': 1,
  'una': 1,
  'uno': 1,
  'dos': 2,
  'tres': 3,
  'cuatro': 4,
  'cinco': 5,
  'seis': 6,
  'siete': 7,
  'ocho': 8,
  'nueve': 9,
  'diez': 10,
  'once': 11,
  'doce': 12,
  'quince': 15,
  'veinte': 20,
  'treinta': 30,
  'cuarenta': 40,
  'cuarenta y cinco': 45,
};

const _ordinals = {
  'primera': 1,
  'segunda': 2,
  'tercera': 3,
  'cuarta': 4,
  'quinta': 5,
  'sexta': 6,
  'septima': 7,
  'octava': 8,
  'novena': 9,
  'decima': 10,
};

int? _num(String s) => int.tryParse(s) ?? _numbers[s];

const _weekdays = {
  'lunes': DateTime.monday,
  'martes': DateTime.tuesday,
  'miercoles': DateTime.wednesday,
  'jueves': DateTime.thursday,
  'viernes': DateTime.friday,
  'sabado': DateTime.saturday,
  'domingo': DateTime.sunday,
};

/// Lo que se quita del texto al sacar la hora o el día.
final _timePhrase = RegExp(
    r'\b(dentro de|en)\s+(media hora|un cuarto de hora|(\d+|[a-z]+( y [a-z]+)?)\s*(minutos?|mins?|horas?|h))\b'
    r'|\b(a las|a la)\s+\d{1,2}([:.]\d{2})?(\s*y\s*(media|cuarto))?(\s*(de la (manana|tarde|noche)|am|pm|hrs?|h))?'
    r'|\b(al mediodia|a medianoche|esta (tarde|noche|manana))'
    r'|\b(pasado manana|manana|hoy)\b'
    r'|\b(el\s+)?(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b');

/// Cuándo, a partir de la frase. `null` si no dice una hora.
///
/// - "en 20 minutos", "en una hora", "en media hora", "dentro de 2 horas"
/// - "a las 5" (de 1 a 7 sin más se entiende de la tarde), "a las 5 de la
///   mañana", "a las 17:30", "a las 9 y media", "al mediodía"
/// - con "mañana", "pasado mañana", "hoy" o un día de la semana.
/// Si la hora ya pasó hoy y no dijo día, es mañana.
DateTime? parseWhen(String message, DateTime now) {
  final m = fold(message);
  final rel = RegExp(
          r'\b(?:dentro de|en)\s+(media hora|un cuarto de hora|(\d+|[a-z]+(?: y [a-z]+)?)\s*(minutos?|mins?|horas?|h)\b)')
      .firstMatch(m);
  if (rel != null) {
    if (rel.group(1) == 'media hora')
      return now.add(const Duration(minutes: 30));
    if (rel.group(1) == 'un cuarto de hora') {
      return now.add(const Duration(minutes: 15));
    }
    final n = _num(rel.group(2)!);
    if (n != null) {
      final unit = rel.group(3)!;
      return now.add(
          unit.startsWith('h') ? Duration(hours: n) : Duration(minutes: n));
    }
  }

  // Día.
  var dayOffset = -1; // -1 = no dijo
  if (RegExp(r'\bpasado manana\b').hasMatch(m)) {
    dayOffset = 2;
  } else if (RegExp(r'\bmanana\b').hasMatch(
      m.replaceAll('de la manana', '').replaceAll('esta manana', ''))) {
    dayOffset = 1;
  } else if (RegExp(r'\bhoy\b').hasMatch(m)) {
    dayOffset = 0;
  } else {
    for (final MapEntry(key: name, value: wd) in _weekdays.entries) {
      if (RegExp('\\b$name\\b').hasMatch(m)) {
        dayOffset = (wd - now.weekday) % 7;
        if (dayOffset == 0) dayOffset = 7; // "el martes" un martes: el próximo
        break;
      }
    }
  }

  // Hora.
  int? hour;
  var minute = 0;
  if (RegExp(r'\bal mediodia\b').hasMatch(m)) {
    hour = 12;
  } else if (RegExp(r'\ba medianoche\b').hasMatch(m)) {
    hour = 0;
    if (dayOffset < 1) dayOffset = 1;
  } else {
    final t = RegExp(
            r'\ba las?\s+(\d{1,2})(?:[:.](\d{2}))?(?:\s*y\s*(media|cuarto))?(?:\s*(de la manana|de la tarde|de la noche|am|pm))?')
        .firstMatch(m);
    if (t != null) {
      hour = int.parse(t.group(1)!);
      minute = t.group(2) != null
          ? int.parse(t.group(2)!)
          : t.group(3) == 'media'
              ? 30
              : t.group(3) == 'cuarto'
                  ? 15
                  : 0;
      final part = t.group(4);
      if ((part == 'de la tarde' || part == 'de la noche' || part == 'pm') &&
          hour < 12) {
        hour += 12;
      } else if ((part == 'de la manana' || part == 'am') && hour == 12) {
        hour = 0;
      } else if (part == null && hour >= 1 && hour <= 7) {
        hour += 12; // "a las 5" casi siempre es de la tarde
      }
      if (hour > 23 || minute > 59) return null;
    } else if (RegExp(r'\besta tarde\b').hasMatch(m)) {
      hour = 17;
    } else if (RegExp(r'\besta noche\b').hasMatch(m)) {
      hour = 21;
    }
  }
  if (hour == null) {
    // Solo un día ("mañana"): a las 9.
    if (dayOffset > 0) hour = 9;
    if (hour == null) return null;
  }

  var date = DateTime(now.year, now.month,
      now.day + (dayOffset < 0 ? 0 : dayOffset), hour, minute);
  if (dayOffset < 0 && !date.isAfter(now)) {
    date = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }
  return date;
}

/// Limpia el texto de la acción: sin la hora, sin muletillas.
String cleanText(String s) {
  var t = s.trim();
  // Se trabaja sobre la versión sin tildes para ubicar, y se recorta el
  // original en las mismas posiciones (fold conserva la longitud).
  for (var i = 0; i < 3; i++) {
    final f = fold(t);
    final match = _timePhrase.firstMatch(f);
    if (match == null) break;
    t = (t.substring(0, match.start) + t.substring(match.end)).trim();
  }
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ');
  t = t.replaceFirst(RegExp(r'^(que|de|a)\s+', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'[\s,.;:!¡?¿]+$'), '');
  t = t.replaceAll(RegExp(r'^[\s,.;:]+'), '');
  return t;
}

/// Lenguajes que se pueden pedir y su extensión de archivo.
const codeLanguages = {
  'python': 'py',
  'javascript': 'js',
  'typescript': 'ts',
  'swift': 'swift',
  'dart': 'dart',
  'java': 'java',
  'bash': 'sh',
  'html': 'html',
  'css': 'css',
  'ruby': 'rb',
  'go': 'go',
  'php': 'php',
  'sql': 'sql',
  'kotlin': 'kt',
  'c++': 'cpp',
  'c#': 'cs',
  'rust': 'rs',
};

const _languageAliases = {
  'js': 'javascript',
  'ts': 'typescript',
  'py': 'python',
  'shell': 'bash',
  'cpp': 'c++',
};

/// Editores que se pueden pedir ("en VS Code").
const editorNames = {
  'visual studio code': 'Visual Studio Code',
  'vs code': 'Visual Studio Code',
  'vscode': 'Visual Studio Code',
  'vs': 'Visual Studio Code',
  'code': 'Visual Studio Code',
  'xcode': 'Xcode',
  'sublime text': 'Sublime Text',
  'sublime': 'Sublime Text',
  'cursor': 'Cursor',
  'zed': 'Zed',
  'pycharm': 'PyCharm',
  'intellij': 'IntelliJ IDEA',
  'android studio': 'Android Studio',
  'textedit': 'TextEdit',
  'editor de texto': 'TextEdit',
};

final _codeRequest = RegExp(
    r'\b(?:haz(?:me)?|crea(?:me)?|escribe(?:me)?|genera(?:me)?|programa(?:me)?|hacer|crear|escribir|generar|necesito)\s+(?:un|una|el|la)?\s*(script|programa|codigo|archivo|funcion)\b');

final _editorPhrase = RegExp(
    r'\b(?:(?:en|con|desde)\s+(?:el\s+)?)?(visual studio code|vs code|vscode|android studio|sublime text|editor de texto|xcode|sublime|cursor|pycharm|intellij|textedit|zed|vs)\b');

/// "abre VS Code y haz un script de Python para sumar" → crear código.
ParsedCommand? _codeCommand(String original) {
  final folded = fold(original);
  final request = _codeRequest.firstMatch(folded);
  if (request == null) return null;

  // Editor (en cualquier parte de la frase).
  String? editor;
  final e = _editorPhrase.firstMatch(folded);
  if (e != null) editor = editorNames[e.group(1)!];

  // Lo que va después de "un script…": lenguaje y descripción.
  var rest = original.substring(request.end);
  var restFolded = fold(rest);
  String? language;
  final lang = RegExp(
          r'\b(?:de|en)\s+(python|javascript|typescript|swift|dart|java|bash|shell|html|css|ruby|go|php|sql|kotlin|rust|js|ts|py|cpp|c\+\+|c#)\b')
      .firstMatch(restFolded);
  if (lang != null) {
    final name = lang.group(1)!;
    language = _languageAliases[name] ?? name;
    rest = rest.substring(0, lang.start) + rest.substring(lang.end);
    restFolded = fold(rest);
  }
  final ed = _editorPhrase.firstMatch(restFolded);
  if (ed != null) {
    rest = rest.substring(0, ed.start) + rest.substring(ed.end);
  }
  var description = rest
      .replaceFirst(
          RegExp(r'^\s*(?:(?:para|que|con|de|el cual|y que)\s+)',
              caseSensitive: false),
          '')
      .trim();
  description = description.replaceAll(RegExp(r'[\s,.;:!¡?¿]+$'), '');
  if (description.isEmpty) return null;
  return ParsedCommand(AssistantIntent.createCode,
      text: description, language: language ?? 'python', editor: editor);
}

/// Verbos con los que empiezan las órdenes (sin tildes).
const _verbs = [
  'reproduce',
  'reproduceme',
  'reproducir',
  'recuerdame',
  'recordarme',
  'acuerdame',
  'avisame',
  'abre',
  'abreme',
  'abrir',
  'apunta',
  'anota',
  'agrega',
  'anade',
  'busca',
  'buscame',
  'ponme',
  'toca',
  'tocame',
  'crea',
  'creame',
  'agenda',
  'agendame',
  'programa',
  'marca',
  'tacha',
];

/// Distancia de edición (letras cambiadas, de más o de menos).
int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = [i, ...List.filled(b.length, 0)];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Corrige la primera palabra si es un verbo de orden mal escrito
/// ("reprode" → "reproduce", "recuerdamee" → "recuerdame"). Las palabras
/// cortas solo admiten un error; las largas, dos.
String fixVerbTypo(String message) {
  final m = RegExp(r'^(\s*(?:por favor,?\s*)?)(\S+)').firstMatch(message);
  if (m == null) return message;
  final word = fold(m.group(2)!);
  // Las palabras cortas se parecen demasiado ("abro" no es "abre").
  if (word.length < 5 || _verbs.contains(word)) return message;
  String? best;
  var bestD = 99;
  for (final v in _verbs) {
    final d = _distance(word, v);
    if (d < bestD) {
      bestD = d;
      best = v;
    }
  }
  final allowed = word.length >= 6 ? 2 : 1;
  if (best == null || bestD > allowed) return message;
  return '${m.group(1)}$best${message.substring(m.end)}';
}

/// Órdenes claras. `null` si no es una de ellas (lo decide la IA).
ParsedCommand? parseCommand(String message, DateTime now) {
  final original = fixVerbTypo(message.trim());
  final m = fold(original);
  String tail(Match match) => original.substring(match.end).trim();

  // Crear código: "haz un script de Python para sumar (en VS Code)",
  // también dentro de "abre VS Code y haz…".
  final code = _codeCommand(original);
  if (code != null) return code;

  // Poner o buscar algo en un sitio: "pon Despacito en YouTube",
  // "busca recetas en Google", "reproduce Bad Bunny en Spotify en Brave".
  final play = RegExp(
          r'^(?:por favor,?\s*)?(pon(?:me)?|reproduce(?:me)?|busca(?:me)?|toca(?:me)?)\s+')
      .firstMatch(m);
  if (play != null) {
    final verb = play.group(1)!;
    final playing = !verb.startsWith('busca');
    // "reproduce X" o "pon la canción X" sin sitio: en YouTube.
    final rest = fold(tail(play));
    final defaultYoutube = verb.startsWith('reproduce') ||
        verb.startsWith('toca') ||
        RegExp(r'^(?:(?:una?|la|el)\s+)?(?:cancion|video|musica|tema)\b')
            .hasMatch(rest);
    final c =
        _openCommand(tail(play), play: playing, defaultYoutube: defaultYoutube);
    if (c != null && c.searchIn != null) return c;
  }

  // Abrir: "abre Spotify", "ábreme una canción de X en YouTube en Brave".
  final open = RegExp(
          r'^(?:por favor,?\s*)?(?:abre(?:me)?|abrir|abra|lanza|ejecuta|inicia la app)\s+(?:la app(?:licacion)?\s+|la pagina\s+(?:de\s+)?|la web\s+(?:de\s+)?|el\s+|la\s+)?')
      .firstMatch(m);
  if (open != null) {
    final c = _openCommand(tail(open));
    if (c != null) return c;
  }

  // Recordatorio: "recuérdame en 20 min llamar a mamá".
  final remind = RegExp(
          r'^(?:por favor,?\s*)?(?:recuerdame|recordarme|acuerdame|avisame|pon(?:me)? un recordatorio(?: para| de)?)\b\s*(?:que\s+|de\s+|a\s+(?!las?\b))?')
      .firstMatch(m);
  if (remind != null) {
    final when = parseWhen(original, now);
    final what = cleanText(tail(remind));
    if (what.isNotEmpty) {
      return ParsedCommand(AssistantIntent.remind, text: what, when: when);
    }
  }

  // Nueva tarea: "apunta llamar al banco", "añade a mis tareas pagar la luz".
  final add = RegExp(
          r'^(?:por favor,?\s*)?(?:anade|agrega|apunta|anota)[\s:]+(?:(?:a|en)\s+(?:mis tareas|mi lista|la lista(?: de tareas)?|pendientes)\s*:?\s*|(?:la tarea|una tarea|tarea)\s*:?\s*(?:de\s+)?)?')
      .firstMatch(m);
  if (add != null &&
      !RegExp(r'^(?:anade|agrega|pon)\s+(?:una? )?(?:reunion|cita|evento)')
          .hasMatch(m)) {
    var what = tail(add);
    what = what.replaceFirst(
        RegExp(
            r'\s+(a|en)\s+(mis tareas|mi lista|la lista( de tareas)?|pendientes)\s*$',
            caseSensitive: false),
        '');
    what = cleanText(what);
    if (what.isNotEmpty)
      return ParsedCommand(AssistantIntent.addTask, text: what);
  }

  // Tareas pendientes.
  if (RegExp(
          r'(que (tengo|me queda|hay) pendiente|mis (tareas|pendientes)|lista de tareas|que tareas tengo|mis recordatorios)')
      .hasMatch(m)) {
    return const ParsedCommand(AssistantIntent.showPending);
  }

  // Tarea hecha: "marca la 2 como hecha", "ya terminé la segunda".
  final done = RegExp(
          r'(?:marca|tacha)\s+(?:como hecha\s+)?(?:la tarea\s+|la\s+)?(\d+|[a-z]+)|(?:ya\s+)?(?:termine|acabe|complete|hice)\s+(?:la tarea\s+|la\s+)?(\d+|primera|segunda|tercera|cuarta|quinta)\b')
      .firstMatch(m);
  if (done != null) {
    final token = done.group(1) ?? done.group(2)!;
    final n = int.tryParse(token) ?? _ordinals[token];
    if (n != null)
      return ParsedCommand(AssistantIntent.completeTask, number: n);
  }

  // Agenda: "¿qué tengo hoy?", "mi agenda de mañana", "qué hay en mi calendario".
  if (RegExp(
          r'(mi agenda|mi calendario|en el calendario|en mi calendario|que eventos|que tengo (hoy|manana)|que reuniones)')
      .hasMatch(m)) {
    final tomorrow =
        RegExp(r'\bmanana\b').hasMatch(m.replaceAll('de la manana', ''));
    return ParsedCommand(AssistantIntent.showAgenda,
        dayOffset: tomorrow ? 1 : 0);
  }

  // Evento: "crea una reunión con Ana mañana a las 10".
  final event = RegExp(
          r'^(?:por favor,?\s*)?(?:crea(?:me)?|agenda(?:me)?|programa|anade|agrega|pon)\s+(?:en (?:el|mi) calendario\s+)?(?:una?\s+)?(?=(?:reunion|cita|evento|llamada|videollamada|clase)\b)')
      .firstMatch(m);
  if (event != null) {
    final when = parseWhen(original, now);
    var what = cleanText(tail(event));
    what = what.replaceFirst(
        RegExp(r'^evento\s+(de\s+)?', caseSensitive: false), '');
    if (what.isNotEmpty) {
      return ParsedCommand(AssistantIntent.createEvent,
          text: what[0].toUpperCase() + what.substring(1), when: when);
    }
  }
  return null;
}

/// Si el mensaje tiene alguna palabra que justifique una acción de
/// asistente (para descartar acciones que la IA elija sin motivo).
bool mentionsAssistantAction(String message) => RegExp(
        r'(recuerd|acuerd|avisa|recordatorio|tarea|pendiente|anade|agrega|apunta|anota|termine|acabe|complete|hice|hecha|abre|abrir|lanza|ejecuta|agenda|calendario|evento|reunion|cita|tengo hoy|tengo manana|crea|programa)')
    .hasMatch(fold(message));

/// Orden a partir de lo que eligió la IA. La hora se saca primero de la
/// frase del usuario (es más fiable) y, si no, de los campos de la IA.
ParsedCommand commandFromAi({
  required AssistantIntent intent,
  required String userText,
  required String detail,
  required int minutes,
  required String time,
  required String day,
  required int number,
  required int hours,
  required DateTime now,
}) {
  DateTime? when = parseWhen(userText, now);
  if (when == null) {
    final tomorrow = fold(day) == 'manana';
    if (minutes > 0) {
      when = now.add(Duration(minutes: minutes));
    } else {
      final t = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time);
      final h = t != null ? int.parse(t.group(1)!) : (hours > 0 ? hours : null);
      final m = t != null ? int.parse(t.group(2)!) : 0;
      if (h != null && h < 24 && m < 60) {
        var d =
            DateTime(now.year, now.month, now.day + (tomorrow ? 1 : 0), h, m);
        if (!tomorrow && !d.isAfter(now)) {
          d = DateTime(now.year, now.month, now.day + 1, h, m);
        }
        when = d;
      }
    }
  }
  final raw = detail.trim().isNotEmpty ? detail : userText;
  if (intent == AssistantIntent.open) {
    // La frase del usuario manda (navegador, búsqueda); si no, lo de la IA.
    final fromUser = parseCommand(userText, now);
    if (fromUser != null && fromUser.intent == AssistantIntent.open) {
      return fromUser;
    }
    final c = _openCommand(raw);
    if (c != null) return c;
  }
  final text = cleanText(raw);
  final tomorrow = RegExp(r'\bmanana\b')
          .hasMatch(fold(userText).replaceAll('de la manana', '')) ||
      fold(day) == 'manana';
  return ParsedCommand(
    intent,
    text: intent == AssistantIntent.createEvent && text.isNotEmpty
        ? text[0].toUpperCase() + text.substring(1)
        : text,
    when: when,
    number: number > 0 ? number : null,
    dayOffset: tomorrow ? 1 : 0,
  );
}
