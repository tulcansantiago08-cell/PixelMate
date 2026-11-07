import 'dart:convert';
import 'package:http/http.dart' as http;

/// Servicio que se comunica con Claude API (Anthropic).
class ClaudeService {
  final String apiKey;
  final String model;
  final List<Map<String, String>> _history = [];

  ClaudeService({
    required this.apiKey,
    this.model = 'claude-haiku-4-5',
  });

  static const _systemPrompt = '''
Eres PixelMate, una mascota virtual pixel art que vive en el escritorio del usuario.
Tu personalidad es alegre, motivadora y concisa. Usas emojis ocasionalmente.
Ayudas al usuario con productividad, respondes preguntas sobre lo que ve en pantalla,
y lo animas durante su jornada de trabajo o estudio.
Responde siempre en español, de forma breve (máximo 3 oraciones).
''';

  Future<String> sendMessage(String userMessage, {String? screenContext}) async {
    final content = screenContext != null
        ? '$userMessage\n\n[Contexto de pantalla: $screenContext]'
        : userMessage;

    _history.add({'role': 'user', 'content': content});

    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 256,
        'system': _systemPrompt,
        'messages': _history,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Claude API error: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(response.body);
    final reply = data['content'][0]['text'] as String;
    _history.add({'role': 'assistant', 'content': reply});

    // Mantener historial corto (últimos 10 mensajes)
    if (_history.length > 10) {
      _history.removeRange(0, _history.length - 10);
    }

    return reply;
  }

  void clearHistory() => _history.clear();
}
