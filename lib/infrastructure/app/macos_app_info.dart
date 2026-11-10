import 'package:flutter/services.dart';

import '../../application/desktop/app_info.dart';

/// Versión y enlace al repositorio (ver `AppDelegate.swift`).
class MacosAppInfo implements AppInfo {
  static const _channel = MethodChannel('com.pixelmate/app');

  @override
  Future<String> version() async {
    try {
      return await _channel.invokeMethod<String>('version') ?? '?';
    } catch (_) {
      return '?';
    }
  }

  @override
  Future<void> openRepository() async {
    try {
      await _channel.invokeMethod<void>('openRepository');
    } catch (_) {}
  }
}
