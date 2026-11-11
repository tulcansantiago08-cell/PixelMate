import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_info.dart';

/// Repositorio donde se publican las versiones.
const releasesPage =
    'https://github.com/tulcansantiago08-cell/PixelMate/releases';

/// "1.10.0" > "1.9.2". Ignora la "v" inicial y el número de compilación
/// ("1.0.0 (2)", "1.0.0+2"). Devuelve <0, 0 o >0 como compareTo.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[\s+(-]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

class ReleaseInfo {
  final String version; // "1.1.0"
  final Uri page;
  const ReleaseInfo(this.version, this.page);
}

/// Lee el último release publicado (solo pide eso; no envía datos).
abstract class UpdateChecker {
  /// `null` si no se pudo consultar.
  Future<ReleaseInfo?> latest();
}

class FakeUpdateChecker implements UpdateChecker {
  ReleaseInfo? release;
  int calls = 0;
  FakeUpdateChecker([this.release]);

  @override
  Future<ReleaseInfo?> latest() async {
    calls++;
    return release;
  }
}

/// Solo se aceptan páginas de este repositorio (nunca un enlace ajeno).
Uri safeReleasePage(String? url, String version) {
  final u = Uri.tryParse(url ?? '');
  if (u != null && u.toString().startsWith('$releasesPage/')) return u;
  return Uri.parse('$releasesPage/tag/v$version');
}

/// Preferencias: si se busca solo, y qué versión ya se avisó.
class UpdateSettings extends ChangeNotifier {
  static const _enabledKey = 'updates.enabled';
  static const _notifiedKey = 'updates.notified';
  final SharedPreferences? _prefs;
  bool _enabled;
  String? _notified;

  UpdateSettings([this._prefs])
      : _enabled = _prefs?.getBool(_enabledKey) ?? true,
        _notified = _prefs?.getString(_notifiedKey);

  bool get enabled => _enabled;
  String? get notified => _notified;

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs?.setBool(_enabledKey, value);
    notifyListeners();
  }

  Future<void> markNotified(String version) async {
    _notified = version;
    await _prefs?.setString(_notifiedKey, version);
  }
}

enum UpdateStatus { unknown, checking, upToDate, available, failed }

class UpdateState {
  final UpdateStatus status;
  final ReleaseInfo? release;

  /// Cambia solo la primera vez que se encuentra una versión nueva (para
  /// avisar una vez, no en cada revisión).
  final int announce;

  const UpdateState(this.status, {this.release, this.announce = 0});
}

/// Revisa al rato de abrir la app y luego una vez al día.
class UpdateController extends StateNotifier<UpdateState> {
  final UpdateChecker _checker;
  final UpdateSettings _settings;
  final Future<String> Function() _installed;
  Timer? _first;
  Timer? _daily;

  UpdateController(this._checker, this._settings, this._installed,
      {Duration firstAfter = const Duration(minutes: 1),
      Duration every = const Duration(hours: 24),
      bool schedule = true})
      : super(const UpdateState(UpdateStatus.unknown)) {
    if (schedule) {
      _first = Timer(firstAfter, () => check());
      _daily = Timer.periodic(every, (_) => check());
    }
  }

  /// [manual]: el usuario pulsó "Buscar actualizaciones" (se hace aunque
  /// esté desactivada la revisión automática).
  Future<void> check({bool manual = false}) async {
    if (!manual && !_settings.enabled) return;
    state = UpdateState(UpdateStatus.checking,
        release: state.release, announce: state.announce);
    final latest = await _checker.latest();
    if (!mounted) return;
    if (latest == null) {
      state = UpdateState(UpdateStatus.failed, announce: state.announce);
      return;
    }
    final current = await _installed();
    if (compareVersions(latest.version, current) <= 0) {
      state = UpdateState(UpdateStatus.upToDate,
          release: latest, announce: state.announce);
      return;
    }
    final isNew = _settings.notified != latest.version;
    if (isNew) await _settings.markNotified(latest.version);
    state = UpdateState(UpdateStatus.available,
        release: latest, announce: state.announce + (isNew ? 1 : 0));
  }

  @override
  void dispose() {
    _first?.cancel();
    _daily?.cancel();
    super.dispose();
  }
}

/// Se sobrescriben en `main()`.
final updateCheckerProvider =
    Provider<UpdateChecker>((_) => FakeUpdateChecker());
final updateSettingsProvider =
    Provider<UpdateSettings>((_) => UpdateSettings());

/// Si se programan las revisiones (en la app sí; en pruebas, no).
final updateScheduleProvider = Provider<bool>((_) => false);

final updateProvider =
    StateNotifierProvider<UpdateController, UpdateState>((ref) {
  return UpdateController(
    ref.watch(updateCheckerProvider),
    ref.watch(updateSettingsProvider),
    () => ref.read(appVersionProvider.future),
    schedule: ref.watch(updateScheduleProvider),
  );
});

/// Mensaje de aviso.
String updateMessage(ReleaseInfo r) =>
    '🆕 Hay una versión nueva de PixelMate: la ${r.version}. Descárgala '
    'desde Ajustes → Acerca de.';
