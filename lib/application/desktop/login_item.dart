import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abrir la app al iniciar sesión en el Mac.
abstract class LoginItemPort {
  /// `false` en versiones de macOS sin soporte (antes de macOS 13).
  Future<bool> isSupported();

  Future<bool> isEnabled();

  /// Devuelve el estado final: puede quedar en `false` si macOS pide
  /// aprobarlo en Configuración del Sistema.
  Future<bool> setEnabled(bool enabled);
}

/// Sin soporte (pruebas, otras plataformas).
class NoopLoginItem implements LoginItemPort {
  bool supported;
  bool enabled;

  /// Si es `false`, [setEnabled] no logra activarlo (simula que macOS
  /// pide aprobación).
  bool grant;

  NoopLoginItem(
      {this.supported = false, this.enabled = false, this.grant = true});

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> setEnabled(bool value) async =>
      enabled = value && !grant ? false : value;
}

/// Estado de "abrir al iniciar sesión" compartido por la barra de menú y
/// los Ajustes (así nunca muestran cosas distintas).
class LaunchAtLogin extends ChangeNotifier {
  final LoginItemPort port;
  bool _supported = false;
  bool _enabled = false;

  LaunchAtLogin(this.port);

  /// `false` si este macOS no lo permite (se oculta la opción).
  bool get supported => _supported;
  bool get enabled => _enabled;

  Future<void> load() async {
    _supported = await port.isSupported();
    _enabled = _supported && await port.isEnabled();
    notifyListeners();
  }

  /// Devuelve `false` si se pidió activarlo y macOS pide aprobarlo antes.
  Future<bool> setEnabled(bool value) async {
    _enabled = await port.setEnabled(value);
    notifyListeners();
    return !value || _enabled;
  }
}

/// Se sobrescribe en `main()`; por defecto, sin soporte.
final launchAtLoginProvider =
    Provider<LaunchAtLogin>((_) => LaunchAtLogin(NoopLoginItem()));

/// Explicación cuando macOS pide aprobarlo.
const launchAtLoginApprovalHint =
    'Para abrir PixelMate al iniciar sesión, actívala en '
    'Configuración del Sistema → General → Ítems de inicio.';
