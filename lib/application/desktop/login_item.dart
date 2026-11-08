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
