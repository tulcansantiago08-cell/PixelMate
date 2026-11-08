import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/activity/activity_mode.dart';
import '../../domain/session/workday_timer.dart';
import '../activity/focus_guard.dart';

import '../desktop/mascot_panel.dart';
import '../mascot/accessory_providers.dart';
import '../mascot/mascot_settings.dart';
import '../desktop/mascot_window_port.dart';
import '../goals/daily_goal.dart';
import '../progress/progress_providers.dart';
import '../workday/workday_providers.dart';
import 'assistant_actions.dart';
import 'assistant_context.dart';
import 'chat_assistant.dart';
import 'workday_summary.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool hasImage;

  /// Nota de la app (por ejemplo, la confirmación de una acción).
  final bool isNote;
  final DateTime time;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.hasImage = false,
    this.isNote = false,
  }) : time = DateTime.now();
}

/// Qué IA usa el chat. Se sobrescribe en `main()` (Apple si está
/// disponible; si no, Claude con API key; si no, ninguna con su motivo).
final assistantChoiceProvider = FutureProvider<AssistantChoice>(
  (_) async => const AssistantChoice(null, 'No hay IA configurada.'),
);

/// Captura de pantalla en base64 (solo la usa una IA que ve imágenes).
/// `null` si no hay captura disponible.
final screenCaptureProvider = Provider<Future<String> Function()?>((_) => null);

class ChatController extends StateNotifier<List<ChatMessage>> {
  final Ref _ref;
  bool isLoading = false;

  ChatController(this._ref)
      : super([
          ChatMessage(
            text: '¡Hola! Soy ${_ref.read(petNameProvider)} 🐾\n'
                '¿En qué te ayudo hoy?\n\n'
                'Puedo decirte cuánto te falta, empezar o pausar tu jornada '
                'y cambiar tu meta. Pídemelo con tus palabras.',
            isUser: false,
          ),
        ]);

  void _add(ChatMessage m) => state = [...state, m];

  /// Un mensaje que la mascota dijo por su cuenta (por ejemplo, el resumen
  /// de la jornada), para poder releerlo en el chat.
  void addFromMascot(String text) =>
      _add(ChatMessage(text: text, isUser: false));

  /// Resumen de la jornada recién terminada (con la IA del Mac).
  Future<String?> summarizeFinishedWorkday(WorkdayStatus status,
      {ActivityMode? mode, DistractionTally? distractions}) async {
    final choice = await _ref.read(assistantChoiceProvider.future);
    final text = await summarizeWorkday(
      choice.assistant,
      prompt: workdaySummaryPrompt(
          status: status, mode: mode, distractions: distractions),
      context: _context(),
    );
    if (text != null) addFromMascot('📝 $text');
    return text;
  }

  /// Al abrir el chat: carga el modelo para que responda antes.
  Future<void> prewarm() async {
    final choice = await _ref.read(assistantChoiceProvider.future);
    await choice.assistant?.prewarm();
  }

  Future<void> send(String message, {bool withScreenshot = false}) async {
    final text = message.trim();
    if ((text.isEmpty && !withScreenshot) || isLoading) return;

    final choice = await _ref.read(assistantChoiceProvider.future);
    final assistant = choice.assistant;
    if (assistant == null) {
      if (text.isNotEmpty) _add(ChatMessage(text: text, isUser: true));
      _add(ChatMessage(
          text: choice.problem ?? 'No hay IA disponible.', isUser: false));
      return;
    }

    String? image;
    if (withScreenshot) {
      final capture = _ref.read(screenCaptureProvider);
      if (!assistant.supportsImages || capture == null) {
        _add(ChatMessage(
          text: '📷 Con ${assistant.label} no puedo ver tu pantalla. '
              'Eso solo funciona con Claude (necesita API key con créditos).',
          isUser: false,
          isNote: true,
        ));
        return;
      }
      try {
        image = await capture();
      } catch (e) {
        debugPrint('Captura de pantalla: $e');
        _add(ChatMessage(
          text: '⚠️ No pude capturar la pantalla. Revisa el permiso en '
              'Configuración del Sistema → Privacidad → Grabación de pantalla.',
          isUser: false,
        ));
        return;
      }
    }

    _add(ChatMessage(
      text: text.isEmpty ? '📷 ¿Qué ves en mi pantalla?' : text,
      isUser: true,
      hasImage: image != null,
    ));
    isLoading = true;
    state = [...state];

    try {
      final reply = await assistant.reply(
        text.isEmpty
            ? 'Describe brevemente qué estoy haciendo en esta pantalla y '
                'ofréceme ayuda.'
            : text,
        context: _context(),
        imageBase64: image,
      );
      _add(ChatMessage(text: reply.text, isUser: false));
      if (assistant.supportsActions) {
        final note = runAssistantAction(
          reply,
          workday: _ref.read(workdayControllerProvider.notifier),
          view: _ref.read(workdayControllerProvider),
          goal: _ref.read(dailyGoalSettingsProvider),
          openStats: () => setMascotPanel(
            window: _ref.read(mascotWindowProvider),
            panel: _ref.read(mascotPanelProvider.notifier),
            next: MascotPanel.stats,
          ),
        );
        if (note != null) {
          _add(ChatMessage(text: note, isUser: false, isNote: true));
        }
      }
    } on AssistantException catch (e) {
      _add(ChatMessage(text: e.message, isUser: false));
    } catch (e) {
      debugPrint('Chat: $e');
      _add(ChatMessage(text: '¡Ups! Algo falló 😵. $e', isUser: false));
    } finally {
      isLoading = false;
      state = [...state];
    }
  }

  String _context() => describeContext(
        petName: _ref.read(petNameProvider),
        species: _ref.read(activeSpeciesProvider),
        now: DateTime.now(),
        workday: _ref.read(workdayControllerProvider),
        goal: _ref.read(dailyGoalProvider),
        progress: _ref.read(progressProvider),
      );
}

final chatProvider = StateNotifierProvider<ChatController, List<ChatMessage>>(
    (ref) => ChatController(ref));
