import '../../application/assistant/chat_assistant.dart';
import '../claude/claude_service.dart';
import 'apple_assistant.dart';
import 'claude_assistant.dart';

/// Elige la IA: la de Apple (gratis, sin conexión) si está disponible; si
/// no, Claude cuando hay API key; si no, ninguna, con el motivo.
AssistantChoice chooseAssistant({
  required AppleAiAvailability apple,
  required ChatAssistant appleAssistant,
  ChatAssistant? claude,
}) {
  if (apple == AppleAiAvailability.available) {
    return AssistantChoice(appleAssistant);
  }
  if (claude != null) return AssistantChoice(claude);
  return AssistantChoice(null, apple.problem);
}

Future<AssistantChoice> detectAssistant({required String claudeApiKey}) async =>
    chooseAssistant(
      apple: await AppleAssistant.availability(),
      appleAssistant: AppleAssistant(),
      claude: claudeApiKey.isEmpty
          ? null
          : ClaudeAssistant(ClaudeService(apiKey: claudeApiKey)),
    );
