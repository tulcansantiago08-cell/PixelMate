import '../../application/assistant/chat_assistant.dart';
import '../claude/claude_service.dart';

/// Claude (requiere API key con créditos). Puede ver capturas de pantalla;
/// solo responde con texto.
class ClaudeAssistant implements ChatAssistant {
  final ClaudeService service;

  ClaudeAssistant(this.service);

  @override
  String get label => 'Claude';

  @override
  bool get supportsImages => true;

  @override
  bool get supportsActions => false;

  @override
  bool get onDevice => false;

  @override
  Future<AssistantReply> reply(
    String message, {
    required String context,
    String? imageBase64,
  }) async {
    try {
      final text = await service.sendMessage(
        'Estado actual de la app: $context\n\n$message',
        imageBase64: imageBase64,
      );
      return AssistantReply(text);
    } on ClaudeApiException catch (e) {
      throw AssistantException(e.message);
    }
  }

  @override
  Future<void> reset() async => service.clearHistory();

  @override
  Future<void> prewarm() async {}
}
