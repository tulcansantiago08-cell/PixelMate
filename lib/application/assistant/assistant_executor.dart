import '../../core/i18n/language.dart';
import 'calendar_notes.dart';
import 'daily_briefing.dart';
import 'code_writer.dart';
import 'command_parser.dart';
import 'daily_tasks.dart';
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
const _weekdayNamesEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
];
const _monthNamesEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
  final at = tr('a las ${_hm(when)}', 'at ${_hm(when)}');
  if (days == 0) return tr('hoy $at', 'today $at');
  if (days == 1) return tr('mañana $at', 'tomorrow $at');
  if (days > 1 && days < 7) {
    return tr('el ${_weekdayNames[when.weekday - 1]} $at',
        'on ${_weekdayNamesEn[when.weekday - 1]} $at');
  }
  return tr('el ${when.day} ${_monthNames[when.month - 1]} $at',
      'on ${_monthNamesEn[when.month - 1]} ${when.day} $at');
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

  /// Apaga (`null`) o pospone (minutos) la alarma que suena; `false` si no
  /// sonaba ninguna.
  final Future<bool> Function(int? snoozeMinutes)? onAlarm;

  /// Tareas diarias: las alarmas que se repiten van aquí.
  final DailyTaskStore? daily;

  /// Las notas del calendario de PixelMate.
  final CalendarStore? calendar;

  /// Lo que dura el modo discoteca cuando se pide.
  static const discoLength = Duration(minutes: 1);

  AssistantExecutor(this.store, this.mac,
      {this.videos,
      this.coder,
      this.onPlaying,
      this.onDance,
      this.onUserName,
      this.onWakeWord,
      this.onAlarm,
      this.daily,
      this.calendar,
      int Function()? snoozeMinutes,
      DateTime Function()? now})
      : now = now ?? DateTime.now,
        snoozeMinutes = snoozeMinutes ?? (() => 5);

  /// Lo que se pospone una alarma si no dices cuánto.
  final int Function() snoozeMinutes;

  static String get _askWhen =>
      tr('¿Para cuándo? Dime, por ejemplo, «en 20 minutos», «a las 5» o «mañana a las 9».', 'For when? Tell me, for example, “in 20 minutes”, “at 5” or “tomorrow at 9”.');

  /// Lo que espera un «sí» antes de hacerse (cerrar una app, quitar una
  /// alarma), y desde cuándo.
  ParsedCommand? _pending;
  DateTime? _pendingAt;
  static const confirmWindow = Duration(minutes: 2);

  /// Hay algo esperando «sí» o «no».
  bool get awaitingConfirmation =>
      _pending != null && now().difference(_pendingAt!) <= confirmWindow;

  /// Pregunta antes de hacer [c].
  String _ask(ParsedCommand c, String question) {
    _pending = c;
    _pendingAt = now();
    return tr('$question Responde «sí» o «no».', '$question Answer “yes” or “no”.');
  }

  /// La respuesta a la pregunta pendiente.
  Future<String> confirm(bool yes) async {
    final c = awaitingConfirmation ? _pending : null;
    _pending = null;
    if (c == null) return tr('🤔 No tenía nada pendiente de confirmar.', '🤔 I had nothing waiting for confirmation.');
    if (!yes) return tr('👌 Vale, no lo hago.', "👌 OK, I won't do it.");
    return run(c, confirmed: true);
  }

  Future<String> run(ParsedCommand c, {bool confirmed = false}) async {
    final t = now();
    // Otra orden: lo que esperaba confirmación ya no se hace.
    _pending = null;
    switch (c.intent) {
      case AssistantIntent.remind:
        final when = c.when;
        if (when == null) return tr('⏰ Te lo recuerdo. $_askWhen', "⏰ I'll remind you. $_askWhen");
        if (!when.isAfter(t)) return tr('⏰ Esa hora ya pasó. $_askWhen', '⏰ That time has passed. $_askWhen');
        await store.addReminder(c.text, when);
        return tr('⏰ Recordatorio: «${c.text}», ${describeWhen(when, t)}.', '⏰ Reminder: “${c.text}”, ${describeWhen(when, t)}.');

      case AssistantIntent.whatsapp:
        return _whatsapp(c);

      case AssistantIntent.note:
        await store.addNote(c.text);
        return tr('📝 Nota guardada en Pendientes › Notas.', '📝 Note saved in To-do › Notes.');

      case AssistantIntent.addTask:
        await store.addTask(c.text);
        final n = store.pending.length;
        return tr('📝 Apuntado: «${c.text}». ${n == 1 ? '1 pendiente.' : '$n pendientes.'}',
            '📝 Noted: “${c.text}”. ${n == 1 ? '1 to do.' : '$n to do.'}');

      case AssistantIntent.completeTask:
        final number = c.number ?? _matchTask(c.text);
        if (number == null) {
          return tr('¿Cuál terminaste? Dime su número, por ejemplo «marca la 1 como hecha».\n${_pendingText()}', 'Which one did you finish? Tell me its number, for example “mark 1 as done”.\n${_pendingText()}');
        }
        final done = await store.completeTask(number);
        if (done == null) {
          return tr('No encuentro la tarea $number. ${_pendingText()}', "I can't find task $number. ${_pendingText()}");
        }
        final left = store.pending.length;
        return tr('✅ Tachada: «${done.text}». ${left == 0 ? 'No te queda nada pendiente.' : 'Te quedan $left.'}',
            '✅ Crossed off: “${done.text}”. ${left == 0 ? 'Nothing left to do.' : '$left left.'}');

      case AssistantIntent.showPending:
        return _pendingText();

      case AssistantIntent.open:
        return _open(c);

      case AssistantIntent.createCode:
        return _code(c);

      case AssistantIntent.danceStart:
        if (onDance == null) {
          return tr('💃 Ahora no puedo bailar.', "💃 I can't dance right now.");
        }
        onDance!(true);
        return tr('🪩 Modo discoteca: bailo un minuto. (dime «para de bailar» si quieres que pare).', "🪩 Disco mode: I'll dance for a minute. (tell me “stop dancing” if you want me to stop).");

      case AssistantIntent.alarm:
        final when = c.when;
        if (when == null) {
          return tr('⏰ ¿A qué hora pongo la alarma? Dime, por ejemplo, «pon una alarma a las 8 am reunión virtual».', '⏰ What time should I set the alarm for? Tell me, for example, “set an alarm at 8 am virtual meeting”.');
        }
        if (!when.isAfter(t)) return tr('⏰ Esa hora ya pasó. $_askWhen', '⏰ That time has passed. $_askWhen');
        final repeat = AlarmRepeat.byName(c.repeat);
        final dailyStore = daily;
        if (repeat != AlarmRepeat.none && dailyStore != null) {
          final task = await dailyStore.add(c.text, when.hour, when.minute,
              days: repeat == AlarmRepeat.weekdays ? weekdays : allDays,
              now: t);
          return tr('📅 Tarea diaria guardada: ${task!.daysLabel.toLowerCase()} a las ${task.time12}, «${task.text}». Sonará como alarma; la ves con el botón ⏰ junto a mí.', '📅 Daily task saved: ${task.daysLabel.toLowerCase()} at ${task.time12}, “${task.text}”. It will ring like an alarm; you can see it with the ⏰ button next to me.');
        }
        await store.addReminder(c.text, when, alarm: true, repeat: repeat);
        final then = repeat == AlarmRepeat.none
            ? ''
            : tr(' y luego ${repeat.label}', ' and then ${repeat.label}');
        return tr('⏰ Alarma puesta ${describeWhen(when, t)}$then: «${c.text}». Sonará hasta que la apagues.',
            '⏰ Alarm set ${describeWhen(when, t)}$then: “${c.text}”. It will ring until you turn it off.');

      case AssistantIntent.alarmStop:
        return await onAlarm?.call(null) == true
            ? tr('🔕 Alarma apagada.', '🔕 Alarm off.')
            : tr('🔕 No hay ninguna alarma sonando.', '🔕 No alarm is ringing.');

      case AssistantIntent.alarmSnooze:
        final minutes = (c.number ?? snoozeMinutes()).clamp(1, 120);
        return await onAlarm?.call(minutes) == true
            ? tr('😴 Te la vuelvo a sonar en $minutes minutos.', "😴 I'll ring it again in $minutes minutes.")
            : tr('🔕 No hay ninguna alarma sonando.', '🔕 No alarm is ringing.');

      case AssistantIntent.alarmDelete:
        return _deleteAlarm(c, confirmed: confirmed);

      case AssistantIntent.volume:
        // «Silencia» mientras suena una alarma: la apaga.
        if (c.text == 'mute' && await onAlarm?.call(null) == true) {
          return tr('🔕 Alarma apagada.', '🔕 Alarm off.');
        }
        final r = await mac.volume(c.text, c.number ?? 0);
        if (r == null) {
          return tr('🔈 Esta salida de sonido no deja cambiar el volumen desde aquí. Prueba con las teclas de volumen del teclado.', "🔈 This sound output doesn't let me change the volume from here. Try the volume keys on the keyboard.");
        }
        return describeVolume(c.text, r);

      case AssistantIntent.hideApp:
        final hidden = await mac.hideApp(c.text);
        return hidden == null
            ? tr('🤔 No veo «${c.text}» abierta.', "🤔 I don't see “${c.text}” open.")
            : tr('🙈 Oculté $hidden.', '🙈 I hid $hidden.');

      case AssistantIntent.listApps:
        final apps = await mac.runningApps();
        if (apps.isEmpty) return tr('🖥️ No hay otras apps abiertas.', '🖥️ No other apps are open.');
        return tr('🖥️ Tienes abiertas: ${apps.join(', ')}. Dime «cierra …» u «oculta …» si quieres.',
            '🖥️ You have open: ${apps.join(', ')}. Tell me “close …” or “hide …” if you want.');

      case AssistantIntent.media:
        return _media(c);

      case AssistantIntent.setUserName:
        final name = cleanUserName(c.text);
        if (name == null) return tr('🤔 ¿Cómo quieres que te llame?', '🤔 What do you want me to call you?');
        await onUserName?.call(name);
        return tr('😊 Hecho: te llamo $name.', "😊 Done: I'll call you $name.");

      case AssistantIntent.wakeWord:
        final on = c.text == 'on';
        final pet = await onWakeWord?.call(on);
        if (pet == null) return tr('🎙️ Eso no lo puedo hacer aquí.', "🎙️ I can't do that here.");
        return on
            ? tr('👂 Activado. Di «Oye $pet» y te escucho, aunque esté cerrado el chat (verás el punto naranja del micrófono).', "👂 On. Say “Hey $pet” and I'll listen, even with the chat closed (you'll see the orange microphone dot).")
            : tr('🔕 Ya no espero a que me llames. Para hablarme, toca 🎙️ o pulsa ⌃⌥V.', "🔕 I'm no longer waiting for you to call me. To talk to me, tap 🎙️ or press ⌃⌥V.");

      case AssistantIntent.closeApp:
        if (!confirmed) {
          return _ask(c,
              tr('⚠️ ¿Cierro ${c.text}? Si tiene algo sin guardar, podrías perderlo.', '⚠️ Should I close ${c.text}? If it has anything unsaved, you could lose it.'));
        }
        final closed = await mac.closeApp(c.text);
        return closed == null
            ? tr('🤔 No veo «${c.text}» abierta.', "🤔 I don't see “${c.text}” open.")
            : tr('👋 Cerré $closed.', '👋 I closed $closed.');

      case AssistantIntent.danceStop:
        onDance?.call(false);
        return tr('🛑 Listo, paro de bailar.', "🛑 Done, I'll stop dancing.");

      case AssistantIntent.showAgenda:
        return _agenda(c.dayOffset, t);

      case AssistantIntent.calendarNote:
        return _calendarNote(c, t);

      case AssistantIntent.createEvent:
        final when = c.when;
        if (when == null) return tr('📅 ¿Para cuándo es «${c.text}»? $_askWhen', '📅 When is “${c.text}”? $_askWhen');
        try {
          await mac.createEvent(c.text, when);
          final end = when.add(const Duration(hours: 1));
          return tr(
              '📅 Creé «${c.text}» ${describeWhen(when, t).replaceFirst('a las ${_hm(when)}', 'de ${_hm(when)} a ${_hm(end)}')}.',
              '📅 I created “${c.text}” ${describeWhen(when, t).replaceFirst('at ${_hm(when)}', 'from ${_hm(when)} to ${_hm(end)}')}.');
        } on CalendarDenied {
          return _calendarDenied;
        }
    }
  }

  /// Lo que tienes hoy o mañana: tu calendario, tareas diarias,
  /// recordatorios y el Calendario del Mac.
  Future<String> _agenda(int dayOffset, DateTime t) async {
    final day = DateTime(t.year, t.month, t.day + dayOffset);
    var mac = const <CalendarEvent>[];
    var denied = false;
    try {
      mac = await this.mac.events(dayOffset);
    } on CalendarDenied {
      denied = true;
    } catch (_) {}
    final items = agendaFor(day,
        notes: calendar,
        daily: daily,
        reminders: store.reminders,
        macEvents: mac);
    final label = dayOffset == 1 ? tr('Mañana', 'Tomorrow') : tr('Hoy', 'Today');
    if (items.isEmpty) {
      return denied
          ? tr('📅 $label no tienes nada anotado en PixelMate. $_calendarDenied', '📅 $label you have nothing noted in PixelMate. $_calendarDenied')
          : tr('📅 $label no tienes nada anotado.', '📅 $label you have nothing noted.');
    }
    return '📅 $label:\n${[
      for (final i in items) '• ${i.time} · ${i.text}'
    ].join('\n')}';
  }

  Future<String> _calendarNote(ParsedCommand c, DateTime t) async {
    final day = c.when;
    if (day == null) {
      return tr('📅 ¿Para qué día anoto «${c.text}»? Dime, por ejemplo, «el viernes», «mañana» o «el 20 de diciembre».', '📅 What day should I note “${c.text}” for? Tell me, for example, “Friday”, “tomorrow” or “December 20”.');
    }
    final notes = calendar;
    if (notes == null) return tr('📅 No tengo el calendario a mano ahora.', "📅 I don't have the calendar at hand right now.");
    if (!c.allDay && !day.isAfter(t)) return tr('📅 Esa hora ya pasó. $_askWhen', '📅 That time has passed. $_askWhen');
    if (DateTime(day.year, day.month, day.day)
        .isBefore(DateTime(t.year, t.month, t.day))) {
      return tr('📅 Ese día ya pasó. ¿Para qué día lo anoto?', '📅 That day has passed. What day should I note it for?');
    }
    final note = await notes.add(c.text, day,
        hour: c.allDay ? null : day.hour,
        minute: day.minute,
        alarm: c.play,
        color: 1,
        repeat: NoteRepeat.byName(c.repeat),
        now: t);
    if (note == null) return tr('📅 ¿Qué anoto?', '📅 What should I note?');
    final when = describeDay(day, t);
    final at = note.allDay
        ? tr('todo el día, aviso a las ${clock12(CalendarNote.noticeHour, 0)}', 'all day, reminder at ${clock12(CalendarNote.noticeHour, 0)}')
        : tr('a las ${note.timeLabel}${note.alarm ? ', con alarma' : ''}',
            'at ${note.timeLabel}${note.alarm ? ', with alarm' : ''}');
    final every =
        note.repeat == NoteRepeat.none ? '' : ', ${note.repeat.label}';
    var reply = tr('📅 Anotado: «${note.text}», $when ($at)$every.', '📅 Noted: “${note.text}”, $when ($at)$every.');
    if (notes.toMac) {
      final problem = await copyToMacCalendar(notes, mac, note);
      reply +=
          problem == null ? tr(' Copiado al Calendario del Mac.', 'Copied to the Mac Calendar.') : ' $problem';
    }
    return reply;
  }

  /// Abre WhatsApp en el chat del contacto con el mensaje escrito: tú lo
  /// revisas y pulsas Enter (no se envía solo).
  Future<String> _whatsapp(ParsedCommand c) async {
    final who = (c.app ?? '').trim();
    if (who.isEmpty) return tr('💬 ¿A quién le escribo?', '💬 Who should I write to?');
    final List<Contact> found;
    try {
      found = await mac.findContacts(who);
    } on ContactsDenied {
      return tr('🔒 Sin permiso para Contactos: Ajustes del Sistema › Privacidad y seguridad › Contactos › activa PixelMate.', '🔒 No permission for Contacts: System Settings › Privacy & Security › Contacts › turn on PixelMate.');
    }
    final withPhone = [
      for (final x in found)
        if (x.phones.any((p) => RegExp(r'\d').hasMatch(p))) x
    ];
    if (withPhone.isEmpty) {
      // Plan B: WhatsApp abierto y el mensaje copiado, para pegarlo.
      final why = found.isEmpty
          ? tr('No tengo a «$who» en los Contactos del Mac', "I don't have “$who” in the Mac Contacts")
          : tr('${found.first.name} no tiene número en Contactos', '${found.first.name} has no number in Contacts');
      final copied = c.text.isNotEmpty && await mac.copyText(c.text);
      final opened = await mac.openApp('WhatsApp') != null ||
          await mac.openUrl(Uri.parse('https://web.whatsapp.com'));
      if (!opened) {
        return tr('💬 $why, y no pude abrir WhatsApp.', "💬 $why, and I couldn't open WhatsApp.") +
            (copied
                ? tr(' Copié el mensaje para que lo pegues con ⌘V.',
                    ' I copied the message so you can paste it with ⌘V.')
                : '');
      }
      return copied
          ? tr('💬 $why. Abrí WhatsApp y copié el mensaje: busca su chat y pégalo con ⌘V.', '💬 $why. I opened WhatsApp and copied the message: find their chat and paste it with ⌘V.')
          : tr('💬 $why. Abrí WhatsApp: busca su chat.', '💬 $why. I opened WhatsApp: find their chat.');
    }
    // Igual que la búsqueda: sin tildes, mayúsculas ni emojis.
    String plain(String x) =>
        fold(x).replaceAll(RegExp(r'[^a-z0-9ñ ]'), '').trim();
    final q = plain(who);
    final exact = withPhone
        .where((x) => plain(x.name) == q || plain(x.nickname) == q)
        .toList();
    final names = {for (final x in withPhone) x.name};
    if (exact.isEmpty && names.length > 1) {
      return tr('💬 ¿A cuál? ${names.take(4).join(', ')}. Dímelo con el nombre completo.',
          '💬 Which one? ${names.take(4).join(', ')}. Tell me the full name.');
    }
    final person = exact.isNotEmpty ? exact.first : withPhone.first;
    final number = whatsappNumber(
        person.phones.firstWhere((p) => RegExp(r'\d').hasMatch(p)),
        await mac.regionCode());
    // Los espacios como %20 (con «+» WhatsApp los mostraría tal cual).
    final encoded = Uri.encodeComponent(c.text);
    final app = Uri.parse('whatsapp://send?phone=$number'
        '${c.text.isEmpty ? '' : '&text=$encoded'}');
    final web = Uri.parse('https://wa.me/$number'
        '${c.text.isEmpty ? '' : '?text=$encoded'}');
    if (!await mac.openUrl(app) && !await mac.openUrl(web)) {
      return tr('No pude abrir WhatsApp.', "I couldn't open WhatsApp.");
    }
    return c.text.isEmpty
        ? tr('💬 Abrí el chat de ${person.name} en WhatsApp.', "💬 I opened ${person.name}'s chat in WhatsApp.")
        : tr('💬 Mensaje para ${person.name} listo en WhatsApp. Revísalo y pulsa Enter para enviarlo.', '💬 Message for ${person.name} ready in WhatsApp. Check it and press Enter to send it.');
  }

  Future<String> _code(ParsedCommand c) async {
    final language = c.language ?? 'python';
    final pretty = language[0].toUpperCase() + language.substring(1);
    final code = await coder?.write(language, c.text);
    if (code == null) {
      return tr('💻 Para escribir código necesito la IA de Apple (Apple Intelligence). Actívala en Configuración del Sistema.', "💻 To write code I need Apple's AI (Apple Intelligence). Turn it on in System Settings.");
    }
    final saved = await mac.saveCode(codeFileName(c.text, language), code,
        editor: c.editor);
    if (saved == null) return tr('💻 No guardé el script (cancelaste).', "💻 I didn't save the script (you canceled).");
    final where = saved.editor.isEmpty ? '' : tr(' y lo abrí en ${saved.editor}', 'and opened it in ${saved.editor}');
    return tr('💻 Escribí «${saved.fileName}» ($pretty)$where. Revísalo antes de ejecutarlo.', '💻 I wrote “${saved.fileName}” ($pretty)$where. Check it before running it.');
  }

  Future<String> _media(ParsedCommand c) async {
    final r = await mac.media(c.text, player: c.app);
    final player = r.player ?? c.app ?? tr('la música', 'the music');
    switch (r.error) {
      case 'none':
        return c.app == null
            ? tr('🎵 No veo Spotify ni Música abiertos. Dime «abre Spotify» o «reproduce …».', "🎵 I don't see Spotify or Music open. Tell me “open Spotify” or “play …”.")
            : tr('🎵 ${c.app} no está abierto.', "🎵 ${c.app} isn't open.");
      case 'denied':
        return tr('🔒 No tengo permiso para controlar $player: Ajustes del Sistema › Privacidad y seguridad › Automatización › PixelMate.', "🔒 I don't have permission to control $player: System Settings › Privacy & Security › Automation › PixelMate.");
      case 'failed':
        return tr('😵 No pude controlar $player.', "😵 I couldn't control $player.");
    }
    return switch (c.text) {
      'pause' => tr('⏸️ Pausé $player.', '⏸️ I paused $player.'),
      'play' => tr('▶️ Sigue sonando $player.', '▶️ $player is playing again.'),
      'next' => tr('⏭️ Siguiente canción en $player.', '⏭️ Next song on $player.'),
      'previous' => tr('⏮️ Canción anterior en $player.', '⏮️ Previous song on $player.'),
      'now' => r.track == null || r.track!.trim() == '—'
          ? tr('🎵 No suena nada en $player ahora.', '🎵 Nothing is playing on $player right now.')
          : tr('🎵 Suena «${r.track}» en $player.', '🎵 “${r.track}” is playing on $player.'),
      _ => tr('⏯️ Listo ($player).', '⏯️ Done ($player).'),
    };
  }

  Future<String> _open(ParsedCommand c) async {
    final browser = c.browser;
    final inBrowser = browser == null ? '' : tr(' en $browser', 'in $browser');
    String notInstalled() =>
        tr('No encontré $browser en tu Mac 🤔. Lo abro en tu navegador de siempre', "I didn't find $browser on your Mac 🤔. I'll open it in your usual browser");

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
            return tr('▶️ Reproduciendo «$name»$inBrowser.', '▶️ Playing “$name”$inBrowser.');
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
              ? tr('🎵 Abrí Spotify buscando «${c.text}». Sin tu cuenta de Spotify no puedo darle play: elige la canción ▶️.', "🎵 I opened Spotify searching for “${c.text}”. Without your Spotify account I can't press play: choose the song ▶️.")
              : tr('🎵 Abrí Spotify buscando «${c.text}».', '🎵 I opened Spotify searching for “${c.text}”.');
        }
      }
      final url = searchUrl(site, c.text);
      final hint = site == 'youtube' ? tr(' Elige la que quieras y dale ▶️.', 'Choose the one you want and press ▶️.') : '';
      if (await mac.openUrl(url, browser: browser)) {
        return tr('${site == 'google' ? '🔎' : '🎵'} Abrí $siteName$inBrowser buscando «${c.text}».$hint',
            '${site == 'google' ? '🔎' : '🎵'} I opened $siteName$inBrowser searching for “${c.text}”.$hint');
      }
      if (browser != null && await mac.openUrl(url)) {
        return tr('${notInstalled()}: busqué «${c.text}» en $siteName.$hint', '${notInstalled()}: I searched for “${c.text}” on $siteName.$hint');
      }
      return tr('No pude abrir $siteName.', "I couldn't open $siteName.");
    }

    // Una web conocida o un dominio: "abre YouTube en Brave".
    final web = siteFor(c.text);
    if (browser != null && web != null) {
      if (await mac.openUrl(web, browser: browser)) {
        return tr('🌐 Abrí ${web.host.replaceFirst('www.', '')}$inBrowser.',
            '🌐 I opened ${web.host.replaceFirst('www.', '')}$inBrowser.');
      }
      if (await mac.openUrl(web)) {
        return '${notInstalled()}: ${web.host.replaceFirst('www.', '')}.';
      }
    }

    // Una app instalada.
    final app = await mac.openApp(c.text);
    if (app != null) return tr('🚀 Abrí $app.', '🚀 I opened $app.');
    if (web != null && await mac.openUrl(web)) {
      return tr('🌐 Abrí ${web.host.replaceFirst('www.', '')}.',
          '🌐 I opened ${web.host.replaceFirst('www.', '')}.');
    }
    return tr('No encontré «${c.text}» en tu Mac. ¿Cómo se llama la app?', "I didn't find “${c.text}” on your Mac. What's the app called?");
  }

  static String get _calendarDenied =>
      tr('📅 Para usar tu calendario, permite el acceso en Configuración del Sistema → Privacidad y seguridad → Calendarios → PixelMate.', '📅 To use your calendar, allow access in System Settings → Privacy & Security → Calendars → PixelMate.');

  String _pendingText() {
    final tasks = store.pending;
    final reminders = store.reminders;
    if (tasks.isEmpty && reminders.isEmpty) {
      return tr('✅ Nada pendiente.', '✅ Nothing pending.');
    }
    final t = now();
    return [
      if (tasks.isNotEmpty) ...[
        tr('📝 Pendientes:', '📝 To-do:'),
        for (var i = 0; i < tasks.length; i++) '${i + 1}. ${tasks[i].text}',
      ],
      if (reminders.isNotEmpty) ...[
        tr('⏰ Recordatorios y alarmas:', '⏰ Reminders and alarms:'),
        for (final r in reminders) '• ${_describeReminder(r, t)}',
      ],
    ].join('\n');
  }

  String _describeReminder(ReminderItem r, DateTime t) =>
      '${r.alarm ? '🔔 ' : ''}${describeWhen(r.due, t)}'
      '${r.repeat == AlarmRepeat.none ? '' : ' (${r.repeat.label})'}: ${r.text}';

  Future<String> _deleteAlarm(ParsedCommand c, {bool confirmed = false}) async {
    final alarms = store.alarms;
    if (alarms.isEmpty) return tr('🔕 No tienes alarmas puestas.', '🔕 You have no alarms set.');
    final t = now();
    final list = alarms.map((r) => '• ${_describeReminder(r, t)}').join('\n');
    final hhmm = c.number;
    final words = fold(c.text)
        .replaceFirst(RegExp(r'^(?:la|el|las|los|mi)\s+'), '')
        .trim();
    final matches = alarms.where((r) {
      if (hhmm != null) {
        final h = hhmm ~/ 100, m = hhmm % 100;
        return r.due.minute == m && (r.due.hour == h || r.due.hour == h + 12);
      }
      if (words.isNotEmpty) return fold(r.text).contains(words);
      return alarms.length == 1;
    }).toList();
    if (matches.isEmpty) {
      return tr('🤔 No sé cuál quitar. Tus alarmas:\n$list', "🤔 I don't know which one to remove. Your alarms:\n$list");
    }
    if (!confirmed) {
      return _ask(
          c,
          matches.length == 1
              ? tr('⚠️ ¿Quito la alarma ${_describeReminder(matches.single, t)}?', '⚠️ Should I remove the alarm ${_describeReminder(matches.single, t)}?')
              : '⚠️ ¿Quito estas ${matches.length} alarmas?\n${[
                  for (final r in matches) '• ${_describeReminder(r, t)}'
                ].join('\n')}\n');
    }
    for (final r in matches) {
      await store.removeReminder(r.id);
    }
    return matches.length == 1
        ? tr('🗑️ Quité la alarma ${_describeReminder(matches.single, t)}.', '🗑️ I removed the alarm ${_describeReminder(matches.single, t)}.')
        : tr('🗑️ Quité ${matches.length} alarmas.', '🗑️ I removed ${matches.length} alarms.');
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
    'mute' => tr('🔇 Silencié el sonido.', '🔇 I muted the sound.'),
    'unmute' => tr('$icon Sonido activado (${v.level} %).', '$icon Sound on (${v.level}%).'),
    'get' => v.muted
        ? tr('🔇 Está silenciado (el volumen quedó en ${v.level} %).', "🔇 It's muted (the volume stayed at ${v.level}%).")
        : tr('$icon El volumen está al ${v.level} %.', '$icon The volume is at ${v.level}%.'),
    'up' when v.level >= 100 => tr('🔊 Ya está al máximo (100 %).', "🔊 It's already at maximum (100%)."),
    'down' when v.level <= 0 => tr('🔇 Ya está al mínimo.', "🔇 It's already at minimum."),
    _ => tr('$icon Volumen al ${v.level} %.', '$icon Volume at ${v.level}%.'),
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

/// Prefijos de país, para números guardados sin él.
const _countryCodes = {
  'EC': '593',
  'CO': '57',
  'MX': '52',
  'PE': '51',
  'AR': '54',
  'CL': '56',
  'VE': '58',
  'BO': '591',
  'UY': '598',
  'PY': '595',
  'ES': '34',
  'US': '1',
  'GT': '502',
  'CR': '506',
  'PA': '507',
  'DO': '1',
  'SV': '503',
  'HN': '504',
  'NI': '505',
  'CU': '53',
  'PR': '1',
};

/// El número como lo quiere WhatsApp: solo dígitos y con el prefijo del
/// país ("+593 99 123 4567" → "593991234567"; "099 123 4567" en Ecuador →
/// "593991234567").
String whatsappNumber(String raw, String region) {
  final plus = raw.trim().startsWith('+');
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (plus) return digits;
  if (digits.startsWith('00')) return digits.substring(2);
  final code = _countryCodes[region.toUpperCase()];
  if (code == null || digits.startsWith(code) && digits.length > 10) {
    return digits;
  }
  if (digits.startsWith('0')) digits = digits.substring(1);
  return '$code$digits';
}
