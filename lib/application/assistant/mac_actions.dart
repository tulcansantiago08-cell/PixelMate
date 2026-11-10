import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command_parser.dart';

class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  const CalendarEvent(this.title, this.start, this.end, {this.allDay = false});
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

  /// Lanza [CalendarDenied] sin permiso.
  Future<List<CalendarEvent>> events(int dayOffset);
  Future<void> createEvent(String title, DateTime start, {int minutes = 60});
}

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
  Future<void> createEvent(String title, DateTime start,
      {int minutes = 60}) async {
    if (!calendarAllowed) throw const CalendarDenied();
    calendar.add(
        CalendarEvent(title, start, start.add(Duration(minutes: minutes))));
  }
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
