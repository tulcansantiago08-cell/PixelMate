import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/activity/activity_mode.dart';
import '../../domain/activity/detectable_app.dart';

/// Aviso amable: hay una app que distrae al frente durante el enfoque.
class FocusNudge {
  final String appName;
  final ForegroundApp app;
  const FocusNudge(this.appName, this.app);
}

/// Distracciones de hoy durante el enfoque.
class DistractionTally {
  final int episodes;
  final Duration time;
  const DistractionTally({this.episodes = 0, this.time = Duration.zero});

  static const zero = DistractionTally();
}

/// Guardián del enfoque, sin relojes ni temporizadores propios.
///
/// - Solo vigila durante un bloque de **enfoque** en marcha de una jornada
///   de trabajo o estudio (en modo juego, jugar es el plan).
/// - Una mirada rápida no cuenta: avisa si la app sigue al frente tras
///   [grace].
/// - Como mucho un aviso por app cada [cooldown].
/// - Cuenta las distracciones y el tiempo que se les dedica.
class FocusGuard {
  final AppCatalog catalog;
  final Duration grace;
  final Duration cooldown;

  ForegroundApp? _app;
  DetectableApp? _rule;
  DateTime? _since; // desde cuándo está al frente (durante el enfoque)
  DateTime? _lastCheck;
  bool _counted = false;
  final Map<String, DateTime> _quietUntil = {};

  FocusGuard({
    required this.catalog,
    this.grace = const Duration(seconds: 45),
    this.cooldown = const Duration(minutes: 10),
  });

  /// Si la regla cuenta como distracción en este modo.
  static bool distracts(DetectableApp rule, ActivityMode? mode) {
    if (mode != ActivityMode.work && mode != ActivityMode.study) return false;
    return rule.category == AppCategory.distraction ||
        rule.category == AppCategory.gaming;
  }

  /// Cambió la app al frente.
  void onForeground(ForegroundApp app, DateTime now) {
    _app = app;
    _rule = catalog.identify(app);
    _since = null;
    _counted = false;
    _lastCheck = now;
  }

  /// Se llama con cada tic de la jornada. Devuelve el tiempo distraído
  /// desde el último tic (para sumarlo), si cuenta como nueva distracción y,
  /// si toca, un aviso.
  ({Duration spent, bool newEpisode, FocusNudge? nudge}) check({
    required DateTime now,
    required bool focusing,
    required ActivityMode? mode,
    required bool enabled,
  }) {
    final last = _lastCheck ?? now;
    _lastCheck = now;
    final app = _app;
    final rule = _rule;
    if (!enabled ||
        !focusing ||
        app == null ||
        rule == null ||
        !distracts(rule, mode)) {
      _since = null;
      return (spent: Duration.zero, newEpisode: false, nudge: null);
    }

    final since = _since ??= now;
    if (now.difference(since) < grace) {
      return (spent: Duration.zero, newEpisode: false, nudge: null);
    }

    // Pasó la gracia: cuenta desde que la abrió (la primera vez) y luego
    // tic a tic.
    final spent = _counted ? now.difference(last) : now.difference(since);
    final newEpisode = !_counted;
    _counted = true;

    FocusNudge? nudge;
    final quiet = _quietUntil[app.key];
    if (newEpisode && (quiet == null || !now.isBefore(quiet))) {
      _quietUntil[app.key] = now.add(cooldown);
      nudge = FocusNudge(rule.name, app);
    }
    return (
      spent: spent.isNegative ? Duration.zero : spent,
      newEpisode: newEpisode,
      nudge: nudge,
    );
  }
}

/// Preferencia del guardián y la cuenta de hoy (solo en este Mac).
class FocusGuardSettings extends ChangeNotifier {
  static const _enabledKey = 'guard.enabled';
  static const _dayKey = 'guard.day';
  static const _episodesKey = 'guard.episodes';
  static const _millisKey = 'guard.millis';

  final SharedPreferences? _prefs;
  final DateTime Function() _now;
  bool _enabled;
  String _day;
  int _episodes;
  int _millis;

  FocusGuardSettings([this._prefs, DateTime Function()? now])
      : _now = now ?? DateTime.now,
        _enabled = _prefs?.getBool(_enabledKey) ?? true,
        _day = _prefs?.getString(_dayKey) ?? '',
        _episodes = _prefs?.getInt(_episodesKey) ?? 0,
        _millis = _prefs?.getInt(_millisKey) ?? 0;

  bool get enabled => _enabled;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs?.setBool(_enabledKey, value);
    notifyListeners();
  }

  static String _dayOf(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month}-${l.day}';
  }

  /// Distracciones de hoy (se reinicia sola al cambiar de día).
  DistractionTally get today => _day == _dayOf(_now())
      ? DistractionTally(
          episodes: _episodes, time: Duration(milliseconds: _millis))
      : DistractionTally.zero;

  Future<void> record(
      {Duration spent = Duration.zero, bool episode = false}) async {
    if (spent == Duration.zero && !episode) return;
    final day = _dayOf(_now());
    if (day != _day) {
      _day = day;
      _episodes = 0;
      _millis = 0;
    }
    _episodes += episode ? 1 : 0;
    _millis += spent.inMilliseconds;
    final p = _prefs;
    if (p != null) {
      await p.setString(_dayKey, _day);
      await p.setInt(_episodesKey, _episodes);
      await p.setInt(_millisKey, _millis);
    }
    notifyListeners();
  }
}
