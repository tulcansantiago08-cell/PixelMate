import '../../domain/activity/detectable_app.dart';
import 'suggestion.dart';

/// Decide si una app en primer plano merece una sugerencia.
///
/// Reglas para no ser pesada:
/// - nunca con la detección desactivada, una app excluida o una sesión activa;
/// - como mucho una sugerencia por categoría cada [cooldown];
/// - tras "Ahora no", silencio durante [snoozeAfterDismiss].
class SuggestionEngine {
  final AppCatalog catalog;
  final Duration cooldown;
  final Duration snoozeAfterDismiss;

  final Map<AppCategory, DateTime> _quietUntil = {};

  SuggestionEngine({
    required this.catalog,
    this.cooldown = const Duration(minutes: 60),
    this.snoozeAfterDismiss = const Duration(hours: 3),
  });

  Suggestion? evaluate({
    required ForegroundApp app,
    required DateTime now,
    required bool detectionEnabled,
    required Set<String> excludedApps,
    required bool sessionActive,
  }) {
    if (!detectionEnabled || sessionActive) return null;
    if (excludedApps.contains(app.key)) return null;
    final rule = catalog.identify(app);
    if (rule == null) return null;

    final quiet = _quietUntil[rule.category];
    if (quiet != null && now.isBefore(quiet)) return null;

    _quietUntil[rule.category] = now.add(cooldown);
    return Suggestion.forApp(app, rule);
  }

  /// El usuario respondió "Ahora no" (o ignoró la sugerencia).
  void dismissed(AppCategory category, DateTime now) {
    _quietUntil[category] = now.add(snoozeAfterDismiss);
  }
}
