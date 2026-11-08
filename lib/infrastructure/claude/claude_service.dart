import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Servicio que se comunica con Claude API (Anthropic).
/// Soporta texto e imágenes (vision).
class ClaudeService {
  final String apiKey;
  final String model;
  final List<Map<String, dynamic>> _history = [];

  ClaudeService({
    required this.apiKey,
    this.model = 'claude-haiku-4-5',
  });

  static const _systemPrompt = '''
Eres la mascota virtual pixel art de PixelMate, que vive en el escritorio del usuario
(tu nombre viene en el estado de cada mensaje).
Tu personalidad es alegre, motivadora y concisa. Usas emojis ocasionalmente.
Ayudas al usuario con productividad, respondes preguntas sobre lo que ve en pantalla,
y lo animas durante su jornada de trabajo o estudio.
Responde siempre en español, de forma breve (máximo 3 oraciones).
''';

  /// Envía un mensaje de texto, opcionalmente con una imagen base64.
  Future<String> sendMessage(
    String userMessage, {
    String? imageBase64,
  }) async {
    if (apiKey.isEmpty) {
      throw ClaudeApiException(
        'Falta la API key 🔑. Ejecuta la app con '
        '--dart-define=ANTHROPIC_API_KEY=tu_clave',
      );
    }

    final List<Map<String, dynamic>> content = [];

    // Adjuntar imagen si se proporcionó
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      content.add({
        'type': 'image',
        'source': {
          'type': 'base64',
          'media_type': 'image/jpeg',
          'data': imageBase64,
        },
      });
    }

    content.add({'type': 'text', 'text': userMessage});

    _history.add({'role': 'user', 'content': content});

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'Content-Type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 512,
              'system': _systemPrompt,
              'messages': _history,
            }),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      _history.removeLast(); // no dejar el mensaje fallido en el historial
      if (e is TimeoutException) {
        throw ClaudeApiException('Claude tardó demasiado en responder ⏱️');
      }
      throw ClaudeApiException('Sin conexión con Claude 🔌');
    }

    if (response.statusCode != 200) {
      _history.removeLast();
      debugPrint('Claude API error ${response.statusCode}: ${response.body}');
      String apiMessage = '';
      String errorType = '';
      try {
        final error = jsonDecode(response.body)['error'];
        apiMessage = (error['message'] ?? '') as String;
        errorType = (error['type'] ?? '') as String;
      } catch (_) {}
      throw ClaudeApiException(
        _friendlyError(response.statusCode, errorType, apiMessage),
      );
    }

    final data = jsonDecode(response.body);
    // La respuesta puede traer varios bloques (por ejemplo, de
    // razonamiento): se unen solo los de texto.
    final reply = [
      for (final block in (data['content'] as List? ?? const []))
        if (block is Map && block['type'] == 'text') block['text'] as String
    ].join().trim();

    // Guardar solo texto en historial para no reenviar imágenes
    _history.last = {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': userMessage}
      ],
    };
    _history.add({'role': 'assistant', 'content': reply});

    if (_history.length > 10) {
      _history.removeRange(0, _history.length - 10);
    }

    return reply;
  }

  void clearHistory() => _history.clear();

  /// Traduce los errores de la API a mensajes claros en español.
  static String _friendlyError(int status, String type, String message) {
    final lower = message.toLowerCase();
    if (lower.contains('credit balance')) {
      return 'Tu cuenta de la API de Claude se quedó sin créditos 💳. '
          'Recarga en console.anthropic.com → Plans & Billing.';
    }
    if (status == 401 || type == 'authentication_error') {
      return 'La API key de Claude no es válida 🔑. Revisa ANTHROPIC_API_KEY.';
    }
    if (status == 403 || type == 'permission_error') {
      return 'Tu API key no tiene permiso para usar este modelo 🚫.';
    }
    if (status == 429 || type == 'rate_limit_error') {
      return 'Demasiadas peticiones seguidas 🐢. Espera un momento e inténtalo de nuevo.';
    }
    if (status == 529 || type == 'overloaded_error') {
      return 'Claude está saturado ahora mismo 😵. Inténtalo en unos segundos.';
    }
    if (status >= 500) {
      return 'Claude tuvo un problema interno (error $status). Inténtalo de nuevo.';
    }
    if (status == 413 || lower.contains('too large')) {
      return 'La captura de pantalla es demasiado grande 🖼️.';
    }
    return message.isNotEmpty ? message : 'Error $status al hablar con Claude.';
  }
}

class ClaudeApiException implements Exception {
  final String message;
  ClaudeApiException(this.message);

  @override
  String toString() => message;
}
