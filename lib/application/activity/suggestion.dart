import '../../domain/activity/detectable_app.dart';

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
            message: '¡Veo que vamos a programar en ${rule.name}! '
                '¿Iniciamos una jornada?',
            options: [
              const SuggestionOption(
                  '💼 Jornada laboral', SuggestionAction.startWork),
              const SuggestionOption(
                  '📚 Sesión de estudio', SuggestionAction.startStudy),
              const SuggestionOption('Ahora no', SuggestionAction.dismiss),
              SuggestionOption(
                  'Nunca con ${rule.name}', SuggestionAction.neverForApp),
            ],
            app: app,
            category: rule.category,
          ),
        AppCategory.gaming => Suggestion(
            message: '¡Veo que vamos a jugar ${rule.name}! '
                '¿Activamos el modo gamer?',
            options: [
              const SuggestionOption(
                  '🎮 Sí, vamos a jugar', SuggestionAction.startGaming),
              const SuggestionOption('Ahora no', SuggestionAction.dismiss),
              SuggestionOption(
                  'Nunca con ${rule.name}', SuggestionAction.neverForApp),
            ],
            app: app,
            category: rule.category,
          ),
        AppCategory.distraction => null,
      };

  /// Pregunta al abrir PixelMate.
  static Suggestion welcome(DateTime localNow) {
    final h = localNow.hour;
    final greeting = h < 12
        ? '¡Buenos días!'
        : h < 19
            ? '¡Buenas tardes!'
            : '¡Buenas noches!';
    return Suggestion(
      message: '$greeting ¿Qué aventuras tenemos hoy?',
      options: const [
        SuggestionOption('💼 Trabajar', SuggestionAction.startWork),
        SuggestionOption('📚 Estudiar', SuggestionAction.startStudy),
        SuggestionOption('🎮 Jugar', SuggestionAction.startGaming),
        SuggestionOption('🌿 Solo acompáñame', SuggestionAction.freeMode),
      ],
    );
  }
}
