import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'claude_service.dart';

// ⚠️  Reemplaza con tu API key real (o cárgala desde variables de entorno)
const _apiKey = String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

final claudeServiceProvider = Provider<ClaudeService>((ref) {
  return ClaudeService(apiKey: _apiKey);
});

// Estado del chat
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  ChatMessage({required this.text, required this.isUser})
      : time = DateTime.now();
}

class ChatNotifier extends StateNotifier<List<ChatMessage>> {
  final ClaudeService _claude;
  bool isLoading = false;

  ChatNotifier(this._claude) : super([
    ChatMessage(
      text: '¡Hola! Soy PixelMate 🐾 ¿En qué te ayudo hoy?',
      isUser: false,
    ),
  ]);

  Future<void> send(String message) async {
    if (message.trim().isEmpty) return;
    state = [...state, ChatMessage(text: message, isUser: true)];
    isLoading = true;

    try {
      final reply = await _claude.sendMessage(message);
      state = [...state, ChatMessage(text: reply, isUser: false)];
    } catch (e) {
      state = [...state, ChatMessage(
        text: '¡Ups! No pude conectarme. Revisa tu API key 🔑',
        isUser: false,
      )];
    } finally {
      isLoading = false;
    }
  }
}

final chatProvider =
    StateNotifierProvider<ChatNotifier, List<ChatMessage>>((ref) {
  return ChatNotifier(ref.watch(claudeServiceProvider));
});
