import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../application/assistant/video_finder.dart';

/// Pide la página de resultados de YouTube y toma el primer video. Solo se
/// envía la búsqueda, y solo cuando el usuario pide reproducir algo.
class YouTubeVideoFinder implements VideoFinder {
  final http.Client _client;
  YouTubeVideoFinder([http.Client? client]) : _client = client ?? http.Client();

  @override
  Future<FoundVideo?> first(String query) async {
    try {
      final url = Uri.https('www.youtube.com', '/results', {
        'search_query': query,
        'hl': 'es',
      });
      final res = await _client.get(url, headers: {
        'Accept-Language': 'es',
        // Sin un agente de navegador YouTube devuelve otra página.
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parseFirstVideo(res.body);
    } catch (e) {
      debugPrint('Buscar en YouTube: $e');
      return null;
    }
  }
}
