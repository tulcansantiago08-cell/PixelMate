import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command_parser.dart';

class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// Id del evento en el Calendario del Mac.
  final String id;
  const CalendarEvent(this.title, this.start, this.end,
      {this.allDay = false, this.id = ''});
}

/// No hay permiso para el calendario.
class CalendarDenied implements Exception {
  const CalendarDenied();
}

/// Lo que el asistente hace en el Mac (ver `AssistantBridge.swift`).
abstract class MacActions {
  /// Nombre de la app abierta, o `null` si no la encontró.
  Future<String?> openApp(String name);

  /// [browser] ("Brave", "Safari"…) o `null` para el predeterminado.
  /// Devuelve `false` si no se pudo (o si ese navegador no está).
  Future<bool> openUrl(Uri url, {String? browser});

  /// Pregunta dónde guardar [content] como [fileName] y lo abre en
  /// [editor] (o el predeterminado). `null` si el usuario canceló.
  Future<SavedCode?> saveCode(String fileName, String content,
      {String? editor});

  /// Cierra una app abierta. Nombre de la app cerrada, o `null` si no
  /// estaba abierta.
  Future<String?> closeApp(String name);

  /// Oculta una app abierta. Su nombre, o `null` si no estaba abierta.
  Future<String?> hideApp(String name);

  /// Nombres de las apps abiertas.
  Future<List<String>> runningApps();

  /// Controla Spotify o Música: [action] play, pause, toggle, next,
  /// previous o now; [player] "Spotify", "Música" o `null` (la que suene).
  Future<MediaResult> media(String action, {String? player});

  /// Cambia el volumen: [action] up, down, set, mute, unmute o get, y
  /// [value] el paso o el nivel (0–100). `null` si la salida de sonido no
  /// deja cambiarlo.
  Future<VolumeLevel?> volume(String action, [int value = 0]);

  /// Lanza [CalendarDenied] sin permiso.
  Future<List<CalendarEvent>> events(int dayOffset);

  /// Crea el evento y devuelve su id. [allDay]: todo el día de [start].
  /// [alert]: aviso del Calendario, en minutos antes (o, si es de todo el
  /// día, a esa hora del día contada desde la medianoche). [repeat]:
  /// "weekly", "yearly" o `null`.
  Future<String?> createEvent(String title, DateTime start,
      {int minutes = 60, bool allDay = false, int? alert, String? repeat});

  /// Borra el evento. `false` si ya no estaba.
  Future<bool> deleteEvent(String id);

  /// Recordatorios de Apple (llegan al iPhone por iCloud). Lanzan
  /// [CalendarDenied] sin permiso.
  Future<String?> addAppleReminder(String title, {DateTime? due});
  Future<bool> setAppleReminderDone(String id, bool done);
  Future<bool> removeAppleReminder(String id);

  /// Si están hechos, de los que siguen existiendo.
  Future<Map<String, bool>> appleRemindersDone(List<String> ids);

  /// Si algo está sonando ahora en la salida de sonido del Mac.
  Future<bool> audioPlaying();

  /// Ejecuta un atajo de la app Atajos: "ok", "missing" (no existe),
  /// "denied" (sin permiso) o "failed".
  Future<String> runShortcut(String name);
}

/// Lo que pasó al controlar la música: el reproductor, la canción (para
/// "now") o el error: "none" (no hay reproductor abierto), "denied" (sin
/// permiso) o "failed".
typedef MediaResult = ({String? player, String? track, String? error});

/// Volumen del Mac (0–100) y si está silenciado.
typedef VolumeLevel = ({int level, bool muted});

class SavedCode {
  final String path;

  /// Editor donde se abrió ("" si con la app predeterminada).
  final String editor;
  const SavedCode(this.path, this.editor);

  String get fileName => path.split('/').last;
}

/// Para pruebas.
class FakeMacActions implements MacActions {
  final Set<String> apps;
  final List<String> opened = [];
  final List<CalendarEvent> calendar;
  bool calendarAllowed;

  /// La repetición del último evento creado.
  String? lastRepeat;

  /// Atajos ejecutados, y los que existen (`null`: todos).
  final List<String> shortcutsRun = [];
  Set<String>? shortcuts;

  /// Recordatorios de Apple: id → (texto, hecho).
  final Map<String, (String, bool)> appleReminders = {};

  FakeMacActions(
      {this.apps = const {},
      List<CalendarEvent>? calendar,
      this.calendarAllowed = true})
      : calendar = calendar ?? [];

  @override
  Future<String?> openApp(String name) async {
    final match = apps.where((a) => fold(a) == fold(name)).firstOrNull;
    if (match != null) opened.add(match);
    return match;
  }

  /// Apps abiertas (para pruebas).
  Set<String> running = {};
  final List<String> closed = [];

  @override
  Future<String?> closeApp(String name) async {
    final match = running.where((a) => fold(a) == fold(name)).firstOrNull;
    if (match == null) return null;
    running.remove(match);
    closed.add(match);
    return match;
  }

  @override
  Future<String?> hideApp(String name) async =>
      running.where((a) => fold(a) == fold(name)).firstOrNull;

  @override
  Future<List<String>> runningApps() async => running.toList();

  /// Reproductores abiertos y lo que se les pidió (para pruebas).
  Set<String> players = {};
  final List<String> mediaActions = [];
  bool mediaDenied = false;

  @override
  Future<MediaResult> media(String action, {String? player}) async {
    final open = player == null
        ? players.toList()
        : players.where((p) => p == player).toList();
    if (open.isEmpty) return (player: null, track: null, error: 'none');
    if (mediaDenied) return (player: open.first, track: null, error: 'denied');
    mediaActions.add('$action ${open.first}');
    return (
      player: open.first,
      track: action == 'now' ? 'Despacito — Luis Fonsi' : null,
      error: null,
    );
  }

  /// Volumen simulado; `fixedVolume` simula una salida que no se puede
  /// cambiar.
  int level = 50;
  bool muted = false;
  bool fixedVolume = false;

  @override
  Future<VolumeLevel?> volume(String action, [int value = 0]) async {
    if (fixedVolume) return null;
    switch (action) {
      case 'up':
        muted = false;
        level = (level + value).clamp(0, 100);
      case 'down':
        level = (level - value).clamp(0, 100);
      case 'set':
        if (value > 0) muted = false;
        level = value.clamp(0, 100);
      case 'mute':
        muted = true;
      case 'unmute':
        muted = false;
    }
    return (level: level, muted: muted);
  }

  /// Navegadores instalados (para pruebas).
  Set<String> browsers = {'Brave', 'Safari'};

  @override
  Future<bool> openUrl(Uri url, {String? browser}) async {
    if (browser != null && !browsers.contains(browser)) return false;
    opened.add(browser == null ? url.toString() : '$url @$browser');
    return true;
  }

  /// Archivos "guardados" (nombre → contenido); `cancelSave` simula
  /// cancelar el diálogo.
  final Map<String, String> saved = {};
  bool cancelSave = false;

  @override
  Future<SavedCode?> saveCode(String fileName, String content,
      {String? editor}) async {
    if (cancelSave) return null;
    saved[fileName] = content;
    return SavedCode(
        '/Users/yo/Documents/$fileName',
        editor ??
            (apps.contains('Visual Studio Code') ? 'Visual Studio Code' : ''));
  }

  @override
  Future<List<CalendarEvent>> events(int dayOffset) async {
    if (!calendarAllowed) throw const CalendarDenied();
    final day = DateTime.now();
    final start = DateTime(day.year, day.month, day.day + dayOffset);
    final end = DateTime(start.year, start.month, start.day + 1);
    return [
      for (final e in calendar)
        if (!e.start.isBefore(start) && e.start.isBefore(end)) e
    ];
  }

  @override
  Future<String?> createEvent(String title, DateTime start,
      {int minutes = 60,
      bool allDay = false,
      int? alert,
      String? repeat}) async {
    lastRepeat = repeat;
    if (!calendarAllowed) throw const CalendarDenied();
    final id = 'ev${calendar.length + 1}';
    calendar.add(CalendarEvent(
        title,
        start,
        allDay
            ? start.add(const Duration(days: 1))
            : start.add(Duration(minutes: minutes)),
        allDay: allDay,
        id: id));
    return id;
  }

  @override
  Future<bool> deleteEvent(String id) async {
    if (!calendarAllowed) throw const CalendarDenied();
    final before = calendar.length;
    calendar.removeWhere((e) => e.id == id);
    return calendar.length < before;
  }

  /// Lo que responde [audioPlaying].
  bool soundPlaying = false;

  @override
  Future<bool> audioPlaying() async => soundPlaying;

  @override
  Future<String> runShortcut(String name) async {
    if (shortcuts != null && !shortcuts!.contains(name)) return 'missing';
    shortcutsRun.add(name);
    return 'ok';
  }

  @override
  Future<String?> addAppleReminder(String title, {DateTime? due}) async {
    if (!calendarAllowed) throw const CalendarDenied();
    final id = 'rem${appleReminders.length + 1}';
    appleReminders[id] = (title, false);
    return id;
  }

  @override
  Future<bool> setAppleReminderDone(String id, bool done) async {
    final r = appleReminders[id];
    if (r == null) return false;
    appleReminders[id] = (r.$1, done);
    return true;
  }

  @override
  Future<bool> removeAppleReminder(String id) async =>
      appleReminders.remove(id) != null;

  @override
  Future<Map<String, bool>> appleRemindersDone(List<String> ids) async => {
        for (final id in ids)
          if (appleReminders[id] case final r?) id: r.$2
      };
}

/// Webs conocidas por nombre (para "abre YouTube" sin app instalada).
const knownSites = {
  'youtube': 'https://www.youtube.com',
  'google': 'https://www.google.com',
  'gmail': 'https://mail.google.com',
  'correo de google': 'https://mail.google.com',
  'github': 'https://github.com',
  'netflix': 'https://www.netflix.com',
  'instagram': 'https://www.instagram.com',
  'facebook': 'https://www.facebook.com',
  'twitter': 'https://x.com',
  'x': 'https://x.com',
  'linkedin': 'https://www.linkedin.com',
  'twitch': 'https://www.twitch.tv',
  'wikipedia': 'https://es.wikipedia.org',
  'chatgpt': 'https://chatgpt.com',
  'claude': 'https://claude.ai',
  'amazon': 'https://www.amazon.com',
  'google maps': 'https://maps.google.com',
  'drive': 'https://drive.google.com',
  'google drive': 'https://drive.google.com',
  'whatsapp web': 'https://web.whatsapp.com',
  'outlook': 'https://outlook.live.com',
  'spotify web': 'https://open.spotify.com',
};

/// Web para [name]: una conocida, o un dominio escrito tal cual
/// ("ejemplo.com"). `null` si no lo parece.
Uri? siteFor(String name) {
  final key = fold(name).trim();
  final known = knownSites[key];
  if (known != null) return Uri.parse(known);
  if (RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+(/\S*)?$').hasMatch(key)) {
    return Uri.parse('https://$key');
  }
  return null;
}

/// Se sobrescribe en `main()` con la versión de macOS.
final macActionsProvider = Provider<MacActions>((_) => FakeMacActions());

/// Búsqueda de [query] dentro de [site] ("youtube", "spotify", "google").
Uri searchUrl(String site, String query, {bool spotifyApp = false}) {
  final q = Uri.encodeQueryComponent(query);
  return switch (site) {
    'youtube' => Uri.parse('https://www.youtube.com/results?search_query=$q'),
    'spotify' => spotifyApp
        ? Uri.parse('spotify:search:${Uri.encodeComponent(query)}')
        : Uri.parse(
            'https://open.spotify.com/search/${Uri.encodeComponent(query)}'),
    _ => Uri.parse('https://www.google.com/search?q=$q'),
  };
}
