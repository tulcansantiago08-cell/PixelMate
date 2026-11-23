import '../../core/i18n/language.dart';
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

  /// En el idioma de la app.
  static String get _systemPrompt => _basePrompt.replaceFirst(
      'Responde siempre en español',
      LanguageSettings.current == AppLanguage.en
          ? 'Responde siempre en inglés'
          : 'Responde siempre en español');

  static const _basePrompt = '''
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
        tr('Falta la API key 🔑. Ejecuta la app con --dart-define=ANTHROPIC_API_KEY=tu_clave', 'The API key is missing 🔑. Run the app with --dart-define=ANTHROPIC_API_KEY=your_key'),
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
        throw ClaudeApiException(tr('Claude tardó demasiado en responder ⏱️', 'Claude took too long to respond ⏱️'));
      }
      throw ClaudeApiException(tr('Sin conexión con Claude 🔌', 'No connection to Claude 🔌'));
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
      return tr('Tu cuenta de la API de Claude se quedó sin créditos 💳. Recarga en console.anthropic.com → Plans & Billing.', 'Your Claude API account ran out of credits 💳. Top up at console.anthropic.com → Plans & Billing.');
    }
    if (status == 401 || type == 'authentication_error') {
      return tr('La API key de Claude no es válida 🔑. Revisa ANTHROPIC_API_KEY.', "The Claude API key isn't valid 🔑. Check ANTHROPIC_API_KEY.");
    }
    if (status == 403 || type == 'permission_error') {
      return tr('Tu API key no tiene permiso para usar este modelo 🚫.', "Your API key isn't allowed to use this model 🚫.");
    }
    if (status == 429 || type == 'rate_limit_error') {
      return tr('Demasiadas peticiones seguidas 🐢. Espera un momento e inténtalo de nuevo.', 'Too many requests in a row 🐢. Wait a moment and try again.');
    }
    if (status == 529 || type == 'overloaded_error') {
      return tr('Claude está saturado ahora mismo 😵. Inténtalo en unos segundos.', 'Claude is overloaded right now 😵. Try again in a few seconds.');
    }
    if (status >= 500) {
      return tr('Claude tuvo un problema interno (error $status). Inténtalo de nuevo.', 'Claude had an internal problem (error $status). Try again.');
    }
    if (status == 413 || lower.contains('too large')) {
      return tr('La captura de pantalla es demasiado grande 🖼️.', 'The screenshot is too large 🖼️.');
    }
    return message.isNotEmpty ? message : tr('Error $status al hablar con Claude.', 'Error $status while talking to Claude.');
  }
}

class ClaudeApiException implements Exception {
  final String message;
  ClaudeApiException(this.message);

  @override
  String toString() => message;
}
