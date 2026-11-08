import 'package:flutter/services.dart';

import '../../application/assistant/assistant_context.dart';
import '../../application/assistant/chat_assistant.dart';

/// Estado del modelo de Apple en este Mac.
enum AppleAiAvailability {
  available,
  appleIntelligenceNotEnabled,
  deviceNotEligible,
  modelNotReady,
  unsupported;

  static AppleAiAvailability parse(Object? wire) =>
      values.where((v) => v.name == wire).firstOrNull ?? unsupported;

  /// Explicación para el usuario si no se puede usar.
  String? get problem => switch (this) {
        available => null,
        appleIntelligenceNotEnabled =>
          'Para charlar gratis conmigo, activa Apple Intelligence en '
              'Configuración del Sistema → Apple Intelligence y Siri.',
        modelNotReady =>
          'Apple Intelligence aún está descargando su modelo. '
              'Vuelve a intentarlo en un rato ⏳',
        deviceNotEligible =>
          'Este Mac no es compatible con Apple Intelligence.',
        unsupported =>
          'La IA de Apple necesita macOS 26 o posterior.',
      };
}

/// IA de Apple en el dispositivo (ver `AppleAssistant.swift`): gratis, sin
/// conexión y privada. No ve imágenes.
class AppleAssistant implements ChatAssistant {
  static const _channel = MethodChannel('com.pixelmate/apple_ai');

  static Future<AppleAiAvailability> availability() async {
    try {
      return AppleAiAvailability.parse(
          await _channel.invokeMethod<String>('availability'));
    } catch (_) {
      return AppleAiAvailability.unsupported;
    }
  }

  @override
  String get label => 'IA de Apple · en tu Mac';

  @override
  bool get supportsImages => false;

  @override
  bool get supportsActions => true;

  @override
  bool get onDevice => true;

  @override
  Future<AssistantReply> reply(
    String message, {
    required String context,
    String? imageBase64,
  }) async {
    final Map<Object?, Object?>? result;
    try {
      result = await _channel.invokeMethod<Map<Object?, Object?>>('respond', {
        'instructions': assistantInstructions,
        'prompt': 'Estado actual de la app: $context\n\nUsuario: $message',
      });
    } on PlatformException catch (e) {
      throw AssistantException(errorMessage(e.code));
    }
    final text = (result?['reply'] as String?)?.trim() ?? '';
    return AssistantReply(
      text.isEmpty ? '🐾' : text,
      action: AssistantAction.parse(result?['action']),
      hours: (result?['hours'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> prewarm() async {
    try {
      await _channel.invokeMethod<void>('prewarm', assistantInstructions);
    } catch (_) {}
  }

  @override
  Future<void> reset() async {
    try {
      await _channel.invokeMethod<void>('reset');
    } catch (_) {}
  }

  /// Mensaje para cada código de error del lado nativo.
  static String errorMessage(String code) => switch (code) {
        'guardrail' =>
          'Prefiero no responder a eso 🙈. ¿Hablamos de otra cosa?',
        'language' => 'Ese idioma aún no lo entiendo bien 😅.',
        'busy' => 'Estoy pensando demasiado rápido 🐢. Prueba en un momento.',
        'unavailable' =>
          'La IA de Apple no está lista ahora mismo. Inténtalo en un rato ⏳',
        'context' =>
          'Se me llenó la memoria 🧠. Empecemos una conversación nueva.',
        _ => 'Algo falló al pensar 😵. Inténtalo de nuevo.',
      };
}
