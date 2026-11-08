import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/desktop/login_item.dart';

/// Usa `SMAppService` (macOS 13+) a través de `LoginItem.swift`.
class MacosLoginItem implements LoginItemPort {
  static const _channel = MethodChannel('com.pixelmate/login_item');

  @override
  Future<bool> isSupported() => _call('isSupported');

  @override
  Future<bool> isEnabled() => _call('isEnabled');

  @override
  Future<bool> setEnabled(bool enabled) => _call('setEnabled', enabled);

  Future<bool> _call(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (e) {
      debugPrint('Inicio de sesión ($method): $e');
      return false;
    }
  }
}
