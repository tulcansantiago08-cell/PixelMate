import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class FoundVideo {
  final String id;
  final String title;
  const FoundVideo(this.id, this.title);

  /// Página del video (empieza a sonar sola al abrirla).
  Uri get watchUrl => Uri.parse('https://www.youtube.com/watch?v=$id');
}

/// Encuentra el primer video de una búsqueda en YouTube (solo cuando el
/// usuario pide reproducir algo).
abstract class VideoFinder {
  Future<FoundVideo?> first(String query);
}

/// El primer video (no anuncio) de la página de resultados de YouTube.
FoundVideo? parseFirstVideo(String html) {
  final m = RegExp(r'"videoRenderer":\{"videoId":"([A-Za-z0-9_-]{11})"')
      .firstMatch(html);
  if (m == null) return null;
  final rest = html.substring(m.end, (m.end + 4000).clamp(0, html.length));
  final t = RegExp(r'"title":\{"runs":\[\{"text":"((?:[^"\\]|\\.)*)"')
      .firstMatch(rest);
  var title = '';
  if (t != null) {
    try {
      title = jsonDecode('"${t.group(1)!}"') as String; // &, \" …
    } catch (_) {
      title = t.group(1)!;
    }
  }
  return FoundVideo(m.group(1)!, title);
}

/// Para pruebas.
class FakeVideoFinder implements VideoFinder {
  final Map<String, FoundVideo> videos;
  final List<String> asked = [];
  FakeVideoFinder([this.videos = const {}]);

  @override
  Future<FoundVideo?> first(String query) async {
    asked.add(query);
    return videos[query];
  }
}

/// Se sobrescribe en `main()` con la búsqueda real.
final videoFinderProvider = Provider<VideoFinder>((_) => FakeVideoFinder());
