import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/activity/activity_mode.dart';
import '../../domain/activity/detectable_app.dart';
import '../../domain/session/workday_config.dart';
import '../workday/workday_controller.dart';
import 'detection_settings.dart';
import 'suggestion.dart';
import 'suggestion_engine.dart';

/// Escucha la app activa y muestra (como estado) la sugerencia actual.
///
/// - Espera [settle] con la misma app al frente antes de sugerir, para no
///   reaccionar al pasar de una app a otra con Cmd+Tab.
/// - Una sugerencia ignorada desaparece sola tras [autoHide] y cuenta como
///   "Ahora no".
/// - Nunca inicia una sesión sin que el usuario elija una opción.
class ActivityDetectionController extends StateNotifier<Suggestion?> {
  final SuggestionEngine _engine;
  final DetectionSettings _settings;
  final WorkdayController _workday;
  final DateTime Function() _now;
  final Duration settle;
  final Duration autoHide;

  StreamSubscription<ForegroundApp>? _sub;
  Timer? _settleTimer;
  Timer? _hideTimer;
  ForegroundApp? _current;

  ActivityDetectionController({
    required Stream<ForegroundApp> foregroundApps,
    required SuggestionEngine engine,
    required DetectionSettings settings,
    required WorkdayController workday,
    DateTime Function()? now,
    this.settle = const Duration(seconds: 4),
    this.autoHide = const Duration(seconds: 60),
  })  : _engine = engine,
        _settings = settings,
        _workday = workday,
        _now = now ?? DateTime.now,
        super(null) {
    _sub = foregroundApps.listen(_onForeground);
    _settings.addListener(_onSettingsChanged);
  }

  ForegroundApp? get currentApp => _current;

  /// Pregunta de bienvenida al abrir la app (si no hay nada más que decir).
  void askWelcome() {
    if (_workday.state.isActive || state != null) return;
    _show(Suggestion.welcome(_now().toLocal()));
  }

  Future<void> choose(SuggestionAction action) async {
    final suggestion = state;
    if (suggestion == null) return;
    _clear();

    switch (action) {
      case SuggestionAction.startWork:
        _start(const WorkdayConfig(), ActivityMode.work);
      case SuggestionAction.startStudy:
        _start(WorkdayConfig.study, ActivityMode.study);
      case SuggestionAction.startGaming:
        _start(WorkdayConfig.gaming, ActivityMode.gaming);
      case SuggestionAction.freeMode:
        break;
      case SuggestionAction.dismiss:
        _snooze(suggestion);
      case SuggestionAction.neverForApp:
        final app = suggestion.app;
        if (app != null) await _settings.exclude(app.key);
    }
  }

  void _start(WorkdayConfig config, ActivityMode mode) {
    if (_workday.state.isActive) return;
    _workday.start(config, mode: mode);
  }

  void _onForeground(ForegroundApp app) {
    _current = app;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, () {
      if (_current == app) _evaluate(app);
    });
  }

  void _evaluate(ForegroundApp app) {
    // Una sugerencia por app ya visible no se reemplaza; la de bienvenida sí,
    // porque una sugerencia concreta es más útil.
    if (state?.app != null) return;
    final suggestion = _engine.evaluate(
      app: app,
      now: _now(),
      detectionEnabled: _settings.enabled,
      excludedApps: _settings.excludedApps,
      sessionActive: _workday.state.isActive,
    );
    if (suggestion != null) _show(suggestion);
  }

  void _onSettingsChanged() {
    final app = state?.app;
    if (state != null &&
        app != null &&
        (!_settings.enabled || _settings.excludedApps.contains(app.key))) {
      _clear();
    }
  }

  void _show(Suggestion s) {
    _hideTimer?.cancel();
    state = s;
    _hideTimer = Timer(autoHide, () {
      if (state == s) {
        _snooze(s);
        _clear();
      }
    });
  }

  void _snooze(Suggestion s) {
    final category = s.category;
    if (category != null) _engine.dismissed(category, _now());
  }

  void _clear() {
    _hideTimer?.cancel();
    state = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _settleTimer?.cancel();
    _hideTimer?.cancel();
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
