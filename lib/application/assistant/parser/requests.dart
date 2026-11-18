part of '../command_parser.dart';

// Cómo se dicen las cosas: faltas en el verbo, «¿puedes…?», «abre Safari y busca…».

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
  'cierra',
  'cierrame',
  'silencia',
  'subele',
  'bajale',
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

/// Órdenes compuestas de abrir y buscar, en una sola orden clara:
/// "abre Safari y busca gatos" → "busca gatos en Google en Safari",
/// "abre YouTube y pon Despacito" → "reproduce Despacito en YouTube",
/// "busca en Google gatos" → "busca gatos en Google". Si no dice qué buscar
/// ("abre Safari y busca"), solo abre.
String _splitOpenAndSearch(String s) {
  final f = fold(s);
  final inSite = RegExp(
          r'^(busca(?:me)?|buscar)\s+en\s+(google|youtube|spotify)\s+(?!y\b)(.+)$')
      .firstMatch(f);
  const sites = {
    'youtube': 'YouTube',
    'spotify': 'Spotify',
    'google': 'Google'
  };
  if (inSite != null) {
    final query = s.substring(s.length - inSite.group(3)!.length);
    return 'busca $query en ${sites[inSite.group(2)]}';
  }
  final m = RegExp(
          r'^((?:abre(?:me)?|abrir|abra)\s+(?:el\s+|la\s+)?)(.+?)\s*(?:,\s*|\s+y\s+(?:luego\s+|despues\s+|ahi\s+)?|\s+para\s+)(?:me\s+)?(busca(?:me)?|buscar|pon(?:me)?|poner|reproduce(?:me)?|reproducir|toca(?:me)?)\b\s*(.*)$')
      .firstMatch(f);
  if (m == null) return s;
  final prefix = m.group(1)!.length;
  final target = s.substring(prefix, prefix + m.group(2)!.length).trim();
  final targetKey = fold(target);
  final query = s.substring(s.length - m.group(4)!.length).trim();
  final searching = m.group(3)!.startsWith('busca');
  final browser = browserNames[targetKey];
  final site = sites[targetKey];
  if (browser == null && site == null) return s;
  if (query.isEmpty) return 'abre $target';
  if (browser != null) {
    return searching
        ? 'busca $query en Google en $browser'
        : 'reproduce $query en $browser';
  }
  if (site == 'Google' || (searching && site != 'Spotify')) {
    return 'busca $query en $site';
  }
  return site == 'Spotify'
      ? '${searching ? 'busca' : 'pon'} $query en Spotify'
      : 'reproduce $query en $site';
}

/// Infinitivo → orden ("¿puedes abrir…?" → "abre…").
const _imperatives = {
  'abrir': 'abre',
  'abrirme': 'ábreme',
  'reproducir': 'reproduce',
  'reproducirme': 'reprodúceme',
  'poner': 'pon',
  'ponerme': 'ponme',
  'tocar': 'toca',
  'buscar': 'busca',
  'buscarme': 'búscame',
  'recordar': 'recuérdame',
  'recordarme': 'recuérdame',
  'avisar': 'avísame',
  'avisarme': 'avísame',
  'apuntar': 'apunta',
  'anotar': 'anota',
  'agregar': 'agrega',
  'añadir': 'añade',
  'crear': 'crea',
  'crearme': 'créame',
  'agendar': 'agenda',
  'agendarme': 'agéndame',
  'programar': 'programa',
  'marcar': 'marca',
  'tachar': 'tacha',
  'bailar': 'baila',
  'hacer': 'haz',
  'hacerme': 'hazme',
  'cerrar': 'cierra',
  'subir': 'sube',
  'subirle': 'súbele',
  'bajar': 'baja',
  'bajarle': 'bájale',
  'silenciar': 'silencia',
  'quitar': 'quita',
  'apagar': 'apaga',
  'activar': 'activa',
  'llamar': 'llama',
  'llamarme': 'llámame',
  'ocultar': 'oculta',
  'pausar': 'pausa',
  'pasar': 'pasa',
  'cambiar': 'cambia',
};

/// Deja una petición hablada o escrita con cortesía como una orden clara:
/// quita el saludo y el nombre de la mascota ("Oye Pixel, abre Spotify"),
/// "por favor" al final, el punto final que pone el dictado, y convierte
/// "¿puedes abrir…?", "¿me puedes recordar…?" y "quiero escuchar X" en
/// "abre…", "recuérdame…" y "reproduce X".
String normalizeRequest(String message, {String? petName}) {
  var s = message.trim();
  // Puntuación final del dictado (las preguntas conservan su "?").
  s = s.replaceFirst(RegExp(r'[\s.!…,;:]+$'), '');
  s = s.replaceFirst(RegExp(r'^¡\s*'), '');

  // Saludo y nombre al principio.
  final names = {
    'pixel',
    if (petName != null && petName.trim().isNotEmpty) fold(petName.trim())
  };
  final namePattern = names.map(RegExp.escape).join('|');
  final greeting =
      RegExp(r'^(?:(?:oye|oiga|hey|ey|hola|mira|escucha|ok|okay|vale)\b[\s,]*)?'
          '(?:(?:$namePattern)\\b[\\s,]*)?');
  final g = greeting.firstMatch(fold(s));
  if (g != null && g.end > 0 && g.end < s.length) {
    final rest = s.substring(g.end).trim();
    // "Hola, ¿cómo estás?" no es una orden: solo se quita si queda algo.
    if (rest.isNotEmpty) s = rest;
  }

  // "…, por favor" al final.
  s = s.replaceFirst(
      RegExp(r'[\s,]*por\s+fa(?:vor|vorcito)?[\s.!?]*$', caseSensitive: false),
      '');

  // "¿(Me) puedes/podrías abrir…?" → "abre…".
  final polite = RegExp(
          r'^¿?\s*(me\s+)?(?:puedes|podrias|podrías|puede|podria|podría|podes|podés)\s+(?:por\s+favor\s+)?(me\s+)?(\S+)\s*',
          caseSensitive: false)
      .firstMatch(s);
  if (polite != null) {
    final verb = fold(polite.group(3)!);
    final withMe = polite.group(1) != null || polite.group(2) != null;
    final key =
        withMe && _imperatives.containsKey('${verb}me') ? '${verb}me' : verb;
    final imperative = _imperatives[key];
    if (imperative != null) {
      final rest = s.substring(polite.end).replaceFirst(RegExp(r'\s*\?$'), '');
      s = rest.isEmpty ? imperative : '$imperative $rest';
    }
  }

  s = _splitOpenAndSearch(s);

  // "Quiero escuchar/oír/ver X" → "reproduce X".
  final want = RegExp(r'^(?:quiero|quisiera)\s+(?:escuchar|oir|oír|ver)\s+',
          caseSensitive: false)
      .firstMatch(s);
  if (want != null) s = 'reproduce ${s.substring(want.end)}';

  return s.trim();
}
