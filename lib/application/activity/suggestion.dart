import '../../core/i18n/language.dart';
import '../../domain/activity/detectable_app.dart';
import '../../domain/time/day_part.dart';

enum SuggestionAction {
  startWork,
  startStudy,
  startGaming,

  /// Modo libre: la mascota acompaña sin temporizador.
  freeMode,

  /// "Ahora no": silencia esta categoría un buen rato.
  dismiss,

  /// No volver a sugerir nada para esta app.
  neverForApp,
}

class SuggestionOption {
  final String label;
  final SuggestionAction action;
  const SuggestionOption(this.label, this.action);
}

/// Pregunta de la mascota con opciones. Nunca inicia nada sola.
class Suggestion {
  final String message;
  final List<SuggestionOption> options;

  /// App que la provocó (`null` en la pregunta de bienvenida).
  final ForegroundApp? app;
  final AppCategory? category;

  const Suggestion({
    required this.message,
    required this.options,
    this.app,
    this.category,
  });

  /// `null` para las apps que no sugieren un modo (distracciones).
  static Suggestion? forApp(ForegroundApp app, DetectableApp rule) =>
      switch (rule.category) {
        AppCategory.development => Suggestion(
            message: tr('Abriste ${rule.name}. ¿Iniciamos una jornada?', 'You opened ${rule.name}. Shall we start a workday?'),
            options: [
              SuggestionOption(
                  tr('💼 Jornada laboral', '💼 Workday'), SuggestionAction.startWork),
              SuggestionOption(
                  tr('📚 Sesión de estudio', '📚 Study session'), SuggestionAction.startStudy),
              SuggestionOption(tr('Ahora no', 'Not now'), SuggestionAction.dismiss),
              SuggestionOption(
                  tr('Nunca con ${rule.name}', 'Never with ${rule.name}'), SuggestionAction.neverForApp),
            ],
            app: app,
            category: rule.category,
          ),
        AppCategory.gaming => Suggestion(
            message: tr('Abriste ${rule.name}. ¿Activamos el modo gamer?', 'You opened ${rule.name}. Shall we turn on gamer mode?'),
            options: [
              SuggestionOption(
                  tr('🎮 Sí, vamos a jugar', "🎮 Yes, let's play"), SuggestionAction.startGaming),
              SuggestionOption(tr('Ahora no', 'Not now'), SuggestionAction.dismiss),
              SuggestionOption(
                  tr('Nunca con ${rule.name}', 'Never with ${rule.name}'), SuggestionAction.neverForApp),
            ],
            app: app,
            category: rule.category,
          ),
        AppCategory.distraction => null,
      };

  /// Pregunta al abrir PixelMate.
  static Suggestion welcome(DateTime localNow) {
    final message = switch (DayPart.of(localNow)) {
      DayPart.morning => tr('Buenos días. ¿Qué toca hoy?', "Good morning. What's on today?"),
      DayPart.afternoon => tr('Buenas tardes. ¿Qué hacemos?', 'Good afternoon. What shall we do?'),
      DayPart.evening => tr('Buenas noches. ¿Un rato más o algo tranquilo?', 'Good evening. A bit more, or something calm?'),
      DayPart.night => tr('Es muy tarde 🌙 ¿Algo rápido, o mejor descansamos?', "It's very late 🌙 Something quick, or should we rest?"),
    };
    return Suggestion(
      message: message,
      options: [
        SuggestionOption(tr('💼 Trabajar', '💼 Work'), SuggestionAction.startWork),
        SuggestionOption(tr('📚 Estudiar', '📚 Study'), SuggestionAction.startStudy),
        SuggestionOption(tr('🎮 Jugar', '🎮 Play'), SuggestionAction.startGaming),
        SuggestionOption(tr('🌿 Solo acompáñame', '🌿 Just keep me company'), SuggestionAction.freeMode),
      ],
    );
  }
}
