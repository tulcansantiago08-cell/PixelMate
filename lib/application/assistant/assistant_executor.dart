import 'code_writer.dart';
import 'command_parser.dart';
import 'mac_actions.dart';
import 'personal_store.dart';
import 'video_finder.dart';

const _weekdayNames = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo'
];
const _monthNames = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

/// "hoy a las 8:15", "mañana a las 9:00", "el viernes a las 11:00",
/// "el 20 nov a las 10:00".
String describeWhen(DateTime when, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final days = day.difference(today).inDays;
  final at = 'a las ${_hm(when)}';
  if (days == 0) return 'hoy $at';
  if (days == 1) return 'mañana $at';
  if (days > 1 && days < 7) return 'el ${_weekdayNames[when.weekday - 1]} $at';
  return 'el ${when.day} ${_monthNames[when.month - 1]} $at';
}

/// Hace lo que pidió el usuario y devuelve el texto para el chat: siempre
/// con datos reales (nunca lo que "cree" la IA).
class AssistantExecutor {
  final PersonalStore store;
  final MacActions mac;
  final VideoFinder? videos;
  final CodeWriter? coder;
  final DateTime Function() now;

  /// Avisa cuando pone a sonar un video (la mascota baila mientras dure).
  final void Function(FoundVideo video)? onPlaying;

  /// Empieza (`true`) o termina (`false`) el modo discoteca.
  final void Function(bool on)? onDance;

  /// Guarda cómo quiere el usuario que lo llamen.
  final Future<void> Function(String name)? onUserName;

  /// Activa o apaga el «oye <nombre>»; devuelve el nombre de la mascota.
  final Future<String> Function(bool on)? onWakeWord;

  /// Lo que dura el modo discoteca cuando se pide.
  static const discoLength = Duration(minutes: 1);

  AssistantExecutor(this.store, this.mac,
      {this.videos,
      this.coder,
      this.onPlaying,
      this.onDance,
      this.onUserName,
      this.onWakeWord,
      DateTime Function()? now})
      : now = now ?? DateTime.now;

  static const _askWhen =
      '¿Para cuándo? Dime, por ejemplo, «en 20 minutos», «a las 5» o '
      '«mañana a las 9».';

  Future<String> run(ParsedCommand c) async {
    final t = now();
    switch (c.intent) {
      case AssistantIntent.remind:
        final when = c.when;
        if (when == null) return '⏰ Te lo recuerdo. $_askWhen';
        if (!when.isAfter(t)) return '⏰ Esa hora ya pasó. $_askWhen';
        await store.addReminder(c.text, when);
        return '⏰ Listo: te recuerdo «${c.text}» ${describeWhen(when, t)}.';

      case AssistantIntent.addTask:
        await store.addTask(c.text);
        final n = store.pending.length;
        return '📝 Apunté «${c.text}». '
            '${n == 1 ? 'Tienes 1 tarea pendiente.' : 'Tienes $n tareas pendientes.'}';

      case AssistantIntent.completeTask:
        final number = c.number ?? _matchTask(c.text);
        if (number == null) {
          return '¿Cuál terminaste? Dime su número, por ejemplo «marca la 1 '
              'como hecha».\n${_pendingText()}';
        }
        final done = await store.completeTask(number);
        if (done == null) {
          return 'No encuentro la tarea $number. ${_pendingText()}';
        }
        final left = store.pending.length;
        return '✅ ¡Hecho! Taché «${done.text}». '
            '${left == 0 ? '¡No te queda nada pendiente! 🎉' : 'Te quedan $left.'}';

      case AssistantIntent.showPending:
        return _pendingText();

      case AssistantIntent.open:
        return _open(c);

      case AssistantIntent.createCode:
        return _code(c);

      case AssistantIntent.danceStart:
        if (onDance == null)
          return '💃 ¡Me encantaría bailar, pero ahora no puedo!';
        onDance!(true);
        return '🪩 ¡Modo discoteca! Bailo un minuto 💃🕺 '
            '(dime «para de bailar» si quieres que pare).';

      case AssistantIntent.volume:
        final r = await mac.volume(c.text, c.number ?? 0);
        if (r == null) {
          return '🔈 Esta salida de sonido no deja cambiar el volumen desde '
              'aquí. Prueba con las teclas de volumen del teclado.';
        }
        return describeVolume(c.text, r);

      case AssistantIntent.hideApp:
        final hidden = await mac.hideApp(c.text);
        return hidden == null
            ? '🤔 No veo «${c.text}» abierta.'
            : '🙈 Oculté $hidden.';

      case AssistantIntent.listApps:
        final apps = await mac.runningApps();
        if (apps.isEmpty) return '🖥️ No hay otras apps abiertas.';
        return '🖥️ Tienes abiertas: ${apps.join(', ')}. Dime «cierra …» u '
            '«oculta …» si quieres.';

      case AssistantIntent.media:
        return _media(c);

      case AssistantIntent.setUserName:
        final name = cleanUserName(c.text);
        if (name == null) return '🤔 ¿Cómo quieres que te llame?';
        await onUserName?.call(name);
        return '😊 ¡Encantado, $name! Desde ahora te llamo así.';

      case AssistantIntent.wakeWord:
        final on = c.text == 'on';
        final pet = await onWakeWord?.call(on);
        if (pet == null) return '🎙️ Eso no lo puedo hacer aquí.';
        return on
            ? '👂 ¡Listo! Di «Oye $pet» o «Hola $pet» y te escucho, aunque '
                'esté cerrado el chat (verás el punto naranja del micrófono).'
            : '🔕 Ya no espero a que me llames. Para hablarme, toca 🎙️ o '
                'pulsa ⌃⌥V.';

      case AssistantIntent.closeApp:
        final closed = await mac.closeApp(c.text);
        return closed == null
            ? '🤔 No veo «${c.text}» abierta.'
            : '👋 Cerré $closed.';

      case AssistantIntent.danceStop:
        onDance?.call(false);
        return '🛑 Listo, paro de bailar.';

      case AssistantIntent.showAgenda:
        try {
          final events = await mac.events(c.dayOffset);
          final label = c.dayOffset == 1 ? 'Mañana' : 'Hoy';
          if (events.isEmpty)
            return '📅 $label no tienes eventos en el calendario.';
          return '📅 $label:\n${[
            for (final e in events)
              '• ${e.allDay ? 'Todo el día' : '${_hm(e.start)}–${_hm(e.end)}'} ${e.title}'
          ].join('\n')}';
        } on CalendarDenied {
          return _calendarDenied;
        }

      case AssistantIntent.createEvent:
        final when = c.when;
        if (when == null) return '📅 ¿Para cuándo es «${c.text}»? $_askWhen';
        try {
          await mac.createEvent(c.text, when);
          final end = when.add(const Duration(hours: 1));
          return '📅 Creé «${c.text}» ${describeWhen(when, t).replaceFirst('a las ${_hm(when)}', 'de ${_hm(when)} a ${_hm(end)}')}.';
        } on CalendarDenied {
          return _calendarDenied;
        }
    }
  }

  Future<String> _code(ParsedCommand c) async {
    final language = c.language ?? 'python';
    final pretty = language[0].toUpperCase() + language.substring(1);
    final code = await coder?.write(language, c.text);
    if (code == null) {
      return '💻 Para escribir código necesito la IA de Apple (Apple '
          'Intelligence). Actívala en Configuración del Sistema.';
    }
    final saved = await mac.saveCode(codeFileName(c.text, language), code,
        editor: c.editor);
    if (saved == null) return '💻 No guardé el script (cancelaste).';
    final where = saved.editor.isEmpty ? '' : ' y lo abrí en ${saved.editor}';
    return '💻 Escribí «${saved.fileName}» ($pretty)$where. ¡Revísalo antes de '
        'ejecutarlo!';
  }

  Future<String> _media(ParsedCommand c) async {
    final r = await mac.media(c.text, player: c.app);
    final player = r.player ?? c.app ?? 'la música';
    switch (r.error) {
      case 'none':
        return c.app == null
            ? '🎵 No veo Spotify ni Música abiertos. Dime «abre Spotify» o '
                '«reproduce …».'
            : '🎵 ${c.app} no está abierto.';
      case 'denied':
        return '🔒 No tengo permiso para controlar $player: Ajustes del '
            'Sistema › Privacidad y seguridad › Automatización › PixelMate.';
      case 'failed':
        return '😵 No pude controlar $player.';
    }
    return switch (c.text) {
      'pause' => '⏸️ Pausé $player.',
      'play' => '▶️ Sigue sonando $player.',
      'next' => '⏭️ Siguiente canción en $player.',
      'previous' => '⏮️ Canción anterior en $player.',
      'now' => r.track == null || r.track!.trim() == '—'
          ? '🎵 No suena nada en $player ahora.'
          : '🎵 Suena «${r.track}» en $player.',
      _ => '⏯️ Listo ($player).',
    };
  }

  Future<String> _open(ParsedCommand c) async {
    final browser = c.browser;
    final inBrowser = browser == null ? '' : ' en $browser';
    String notInstalled() =>
        'No encontré $browser en tu Mac 🤔. Lo abro en tu navegador de siempre';

    // Buscar dentro de un sitio: "pon Despacito en YouTube".
    final site = c.searchIn;
    if (site != null) {
      final siteName = switch (site) {
        'youtube' => 'YouTube',
        'spotify' => 'Spotify',
        _ => 'Google',
      };
      // "Reproduce X": el primer video de YouTube, ya sonando.
      final finder = videos;
      if (c.play && site == 'youtube' && finder != null) {
        final video = await finder.first(c.text);
        if (video != null) {
          final name = video.title.isEmpty ? c.text : video.title;
          if (await mac.openUrl(video.watchUrl, browser: browser)) {
            onPlaying?.call(video);
            return '▶️ Reproduciendo «$name»$inBrowser.';
          }
          if (browser != null && await mac.openUrl(video.watchUrl)) {
            onPlaying?.call(video);
            return '${notInstalled()}: ▶️ «$name».';
          }
        }
      }
      // Spotify sin navegador pedido: en la app, si está.
      if (site == 'spotify' && browser == null) {
        final app = await mac.openApp('Spotify');
        if (app != null &&
            await mac.openUrl(searchUrl(site, c.text, spotifyApp: true))) {
          return c.play
              ? '🎵 Abrí Spotify buscando «${c.text}». Sin tu cuenta de '
                  'Spotify no puedo darle play: elige la canción ▶️.'
              : '🎵 Abrí Spotify buscando «${c.text}».';
        }
      }
      final url = searchUrl(site, c.text);
      final hint = site == 'youtube' ? ' Elige la que quieras y dale ▶️.' : '';
      if (await mac.openUrl(url, browser: browser)) {
        return '${site == 'google' ? '🔎' : '🎵'} Abrí $siteName$inBrowser '
            'buscando «${c.text}».$hint';
      }
      if (browser != null && await mac.openUrl(url)) {
        return '${notInstalled()}: busqué «${c.text}» en $siteName.$hint';
      }
      return 'No pude abrir $siteName 😿.';
    }

    // Una web conocida o un dominio: "abre YouTube en Brave".
    final web = siteFor(c.text);
    if (browser != null && web != null) {
      if (await mac.openUrl(web, browser: browser)) {
        return '🌐 Abrí ${web.host.replaceFirst('www.', '')}$inBrowser.';
      }
      if (await mac.openUrl(web)) {
        return '${notInstalled()}: ${web.host.replaceFirst('www.', '')}.';
      }
    }

    // Una app instalada.
    final app = await mac.openApp(c.text);
    if (app != null) return '🚀 Abrí $app.';
    if (web != null && await mac.openUrl(web)) {
      return '🌐 Abrí ${web.host.replaceFirst('www.', '')}.';
    }
    return 'No encontré «${c.text}» en tu Mac 🤔. ¿Cómo se llama la app?';
  }

  static const _calendarDenied =
      '📅 Para usar tu calendario, permite el acceso en Configuración del '
      'Sistema → Privacidad y seguridad → Calendarios → PixelMate.';

  String _pendingText() {
    final tasks = store.pending;
    final reminders = store.reminders;
    if (tasks.isEmpty && reminders.isEmpty) {
      return '🎉 No tienes nada pendiente.';
    }
    final t = now();
    return [
      if (tasks.isNotEmpty) ...[
        '📝 Pendientes:',
        for (var i = 0; i < tasks.length; i++) '${i + 1}. ${tasks[i].text}',
      ],
      if (reminders.isNotEmpty) ...[
        '⏰ Recordatorios:',
        for (final r in reminders) '• ${describeWhen(r.due, t)}: ${r.text}',
      ],
    ].join('\n');
  }

  /// La tarea pendiente que más se parece a [text] (por palabras).
  int? _matchTask(String text) {
    final words =
        fold(text).split(RegExp(r'\W+')).where((w) => w.length > 2).toSet();
    if (words.isEmpty) return null;
    final tasks = store.pending;
    var best = 0;
    int? index;
    for (var i = 0; i < tasks.length; i++) {
      final tw = fold(tasks[i].text).split(RegExp(r'\W+')).toSet();
      final score = words.intersection(tw).length;
      if (score > best) {
        best = score;
        index = i + 1;
      }
    }
    return index;
  }
}

/// Lo que dice la mascota tras cambiar el volumen.
String describeVolume(String action, VolumeLevel v) {
  final icon = v.muted || v.level == 0
      ? '🔇'
      : v.level < 34
          ? '🔈'
          : v.level < 67
              ? '🔉'
              : '🔊';
  return switch (action) {
    'mute' => '🔇 Silencié el sonido.',
    'unmute' => '$icon Sonido activado (${v.level} %).',
    'get' => v.muted
        ? '🔇 Está silenciado (el volumen quedó en ${v.level} %).'
        : '$icon El volumen está al ${v.level} %.',
    'up' when v.level >= 100 => '🔊 Ya está al máximo (100 %).',
    'down' when v.level <= 0 => '🔇 Ya está al mínimo.',
    _ => '$icon Volumen al ${v.level} %.',
  };
}

/// El nombre del usuario, con mayúscula y sin palabras de más; `null` si no
/// parece un nombre.
String? cleanUserName(String raw) {
  final words = raw
      .replaceAll(RegExp(r'[^\p{L}\s\-]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(3)
      .toList();
  if (words.isEmpty) return null;
  final name = words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  return name.length > 24 ? null : name;
}
