part of '../command_parser.dart';

// Controlar el Mac: «oye James», música, volumen y baile.

/// «Activa el oye James», «escúchame siempre», «que me escuches cuando te
/// llame» / «desactiva el oye James», «deja de escucharme» ([m] sin tildes).
ParsedCommand? _wakeCommand(String m) {
  final t = m
      .replaceAll(RegExp(r'[¡!¿?.,«»"]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const what =
      r'(?:(?:el\s+|la\s+|modo\s+)?(?:oye|hola|hey)\b|palabra de activacion|escucha(?:r)? (?:siempre|todo el tiempo)|que te (?:llame|hable)|cuando te (?:llame|hable)|llamarte por (?:tu )?nombre|despertarte)';
  if (RegExp('^(?:desactiva|apaga|quita|deja de usar|no uses)\\b.*$what')
          .hasMatch(t) ||
      RegExp(r'^(?:deja de escucharme|ya no me escuches|no me escuches)\b')
          .hasMatch(t)) {
    return const ParsedCommand(AssistantIntent.wakeWord, text: 'off');
  }
  if (RegExp('^(?:activa|enciende|prende|pon|ponme|habilita|usa)\\b.*$what')
          .hasMatch(t) ||
      RegExp(r'^(?:escuchame|escuchame siempre|quiero que me escuches|escucha cuando te llame)\b.*(?:siempre|llame|hable|nombre)')
          .hasMatch(t)) {
    return const ParsedCommand(AssistantIntent.wakeWord, text: 'on');
  }
  return null;
}

/// «Pausa la música», «dale play», «siguiente canción», «la anterior»,
/// «¿qué canción suena?», «pausa Spotify» ([m] ya sin tildes).
ParsedCommand? _mediaCommand(String m) {
  final t = m
      .replaceAll(RegExp(r'[¡!¿?.,]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const what =
      r'(?:la\s+|el\s+|esta\s+)?(?:musica|cancion|canciones|tema|rola|pista|reproduccion|spotify|apple music|cancion de spotify)';
  String? player;
  if (RegExp(r'\bspotify\b').hasMatch(t)) player = 'Spotify';
  if (RegExp(
          r'\b(?:apple music|musica de apple|itunes|app de musica|en musica)\b')
      .hasMatch(t)) {
    player = 'Música';
  }
  ParsedCommand c(String action) =>
      ParsedCommand(AssistantIntent.media, text: action, app: player);

  if (RegExp('^(?:pausa|pausar|pausala|para|deten|detener|pon en pausa|pon pausa a|quita)\\s+$what\\b')
          .hasMatch(t) ||
      RegExp(r'^(?:pon pausa|pausa la musica)$').hasMatch(t)) {
    return c('pause');
  }
  if (RegExp(r'^(?:dale play|play|pon play|dale a play|dale reproducir)$')
          .hasMatch(t) ||
      RegExp('^(?:reanuda|continua|sigue con|vuelve a poner|quita la pausa a|quitale la pausa a|reproduce|pon|ponme|dale play a)\\s+$what\$')
          .hasMatch(t)) {
    return c('play');
  }
  if (RegExp('^(?:(?:pon|ponme|pasa a|cambia a|salta a)\\s+)?(?:la\\s+)?siguiente(?:\\s+(?:cancion|tema|rola|pista))?(?:\\s+(?:en|de)\\s+\\S+.*)?\$')
          .hasMatch(t) ||
      RegExp('^(?:pasa|salta|cambia|adelanta|skip|next)(?:\\s+(?:de\\s+)?$what)?(?:\\s+(?:en|de)\\s+\\S+.*)?\$')
          .hasMatch(t) ||
      t == 'next') {
    return c('next');
  }
  if (RegExp('^(?:(?:pon|ponme|vuelve a|regresa a|devuelvete a)\\s+)?(?:la\\s+|el\\s+)?(?:(?:cancion|tema|pista)\\s+)?anterior(?:\\s+(?:cancion|tema|pista))?(?:\\s+(?:en|de)\\s+\\S+.*)?\$')
          .hasMatch(t) ||
      RegExp(r'^(?:regresa|devuelve|retrocede)\s+(?:la\s+)?(?:cancion|tema|pista)$')
          .hasMatch(t)) {
    return c('previous');
  }
  if (RegExp(r'\b(?:que|cual)\s+(?:cancion|tema|rola)\s+(?:es\s+esta|es|suena|esta\s+sonando|estoy\s+escuchando|se\s+esta\s+escuchando)\b')
          .hasMatch(t) ||
      RegExp(r'\bcomo\s+se\s+llama\s+(?:esta|la)\s+(?:cancion|tema)\b')
          .hasMatch(t)) {
    return c('now');
  }
  return null;
}

/// «Sube el volumen», «súbele un poco», «bájalo», «más alto», «volumen al
/// 50», «ponlo a tope», «silencia», «activa el sonido», «¿a cuánto está el
/// volumen?» ([m] ya sin tildes).
ParsedCommand? _volumeCommand(String m) {
  final t = m
      .replaceAll(RegExp(r'[¡!¿?.,%]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  ParsedCommand v(String action, [int? n]) =>
      ParsedCommand(AssistantIntent.volume, text: action, number: n);
  const what = r'(?:volumen|sonido|audio|musica)';
  final hasWhat = RegExp('\\b$what\\b').hasMatch(t);

  if (RegExp(
          r'^(?:silencia(?:lo|la)?|silencio|mutea(?:lo)?|mute|pon(?:lo|la)? en silencio|sin sonido|(?:quita|quitale|apaga)\s+(?:el\s+|la\s+)?(?:sonido|audio|volumen))\b')
      .hasMatch(t)) {
    return v('mute');
  }
  if (RegExp(
          r'^(?:desmutea(?:lo)?|unmute|quita(?:le)?\s+(?:el\s+)?silencio|(?:activa|pon|devuelve|vuelve a poner)\s+(?:el\s+)?(?:sonido|audio))\b')
      .hasMatch(t)) {
    return v('unmute');
  }

  int? level() {
    if (RegExp(r'\b(?:a tope|al maximo|al 100|maximo)\b').hasMatch(t)) {
      return 100;
    }
    if (RegExp(r'\b(?:al minimo|minimo)\b').hasMatch(t)) return 0;
    final n = RegExp(r'\b(?:a|al|en)\s+(\d{1,3})\b').firstMatch(t);
    return n == null ? null : int.parse(n.group(1)!).clamp(0, 100);
  }

  int step() {
    final n = RegExp(r'\b(\d{1,3})\b').firstMatch(t);
    if (n != null) return int.parse(n.group(1)!).clamp(1, 100);
    if (RegExp(r'\b(?:un poco|poquito|poquitico|un poquito)\b').hasMatch(t)) {
      return 8;
    }
    if (RegExp(r'\b(?:mucho|bastante|harto)\b').hasMatch(t)) return 30;
    return 15;
  }

  final up = RegExp(
          r'^(?:sube|subir|subele|subelo|subela|aumenta|aumentale|incrementa|dale mas|pon(?:le)? mas)\b')
      .firstMatch(t);
  final down = RegExp(
          r'^(?:baja|bajar|bajale|bajalo|bajala|disminuye|reduce|reducele|pon(?:le)? menos)\b')
      .firstMatch(t);
  final pronoun = RegExp(r'^\S+(?:le|lo|la)\b').hasMatch(t);
  final amount =
      RegExp(r'\b(?:poco|poquito|mucho|bastante|tope|maximo|minimo|\d+)\b')
          .hasMatch(t);
  if (up != null && (hasWhat || pronoun || amount || t == up.group(0))) {
    final l = level();
    return l != null ? v('set', l) : v('up', step());
  }
  if (down != null && (hasWhat || pronoun || amount || t == down.group(0))) {
    final l = level();
    return l != null ? v('set', l) : v('down', step());
  }
  if (RegExp(r'^(?:mas|un poco mas)\s+(?:volumen|alto|fuerte|duro)$')
          .hasMatch(t) ||
      RegExp(r'^(?:volumen|sonido)\s+(?:mas alto|arriba)$').hasMatch(t)) {
    return v('up', step());
  }
  if (RegExp(
          r'^(?:menos volumen|mas bajo|mas suave|mas despacio|volumen mas bajo|volumen abajo)$')
      .hasMatch(t)) {
    return v('down', step());
  }
  // "Volumen al 50", "pon el volumen en 30", "ponlo a tope".
  if (RegExp(r'^(?:(?:pon|ponme|ponlo|deja|dejalo|ajusta|cambia|fija)\s+)?(?:(?:el|la)\s+)?(?:volumen|sonido|musica)?\s*(?:a|al|en)\s+(?:\d{1,3}|tope|maximo|minimo)\b')
          .hasMatch(t) &&
      (hasWhat || RegExp(r'^ponlo|^dejalo').hasMatch(t))) {
    final l = level();
    if (l != null) return v('set', l);
  }
  if (RegExp(r'^volumen\s+(\d{1,3})$').hasMatch(t)) {
    return v('set', int.parse(t.split(' ').last).clamp(0, 100));
  }
  if (RegExp(r'\b(?:a cuanto|cuanto|que nivel|como)\b.*\bvolumen\b')
      .hasMatch(t)) {
    return v('get');
  }
  return null;
}

/// Órdenes claras. `null` si no es una de ellas (lo decide la IA).
/// «Modo discoteca», «baila», «a bailar», «haz un baile», «fiesta» o
/// «para de bailar», «quita la discoteca» ([m] ya sin tildes).
ParsedCommand? _danceCommand(String m) {
  final text = m.replaceAll(RegExp(r'[¡!¿?.,]'), ' ').trim();
  const party =
      r'(?:bailar|baile|bailes|bailando|discoteca|disco|fiesta|rumba)';
  if (RegExp(r'^(?:por favor\s+)?(?:ya\s+)?(?:para|parale|deja|dejate|detente|quita|apaga|termina|desactiva|stop|basta)\b.*\b' +
              party +
              r'\b')
          .hasMatch(text) ||
      RegExp(r'^(?:ya\s+)?no\s+(?:bailes|mas\s+baile|mas\s+fiesta)\b')
          .hasMatch(text)) {
    return const ParsedCommand(AssistantIntent.danceStop);
  }
  final start = RegExp(
      r'^(?:por favor\s+)?(?:(?:ponte|ponme|pon|activa|activar|entra)\s+(?:en\s+|el\s+|la\s+)?(?:modo\s+)?(?:discoteca|disco|fiesta|rumba)|modo\s+(?:discoteca|disco|fiesta|rumba)|(?:ponte a |ponme a |vamos a |a |quiero que )?(?:baila|bailes|bailar|bailemos|bailate)\b|(?:haz|hazme|echate)(?: un)? baile(?:cito)?|(?:una\s+)?(?:fiesta|discoteca|rumba)$)');
  if (start.hasMatch(text)) {
    return const ParsedCommand(AssistantIntent.danceStart);
  }
  return null;
}
