import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../application/desktop/global_shortcut.dart';
import '../../application/desktop/sounds.dart';

/// Atajo global ⌃⌥P (ver `GlobalHotKey.swift`).
class MacosGlobalShortcut implements GlobalShortcutPort {
  static const _channel = MethodChannel('com.pixelmate/hotkey');
  final _presses = StreamController<void>.broadcast();

  MacosGlobalShortcut() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pressed') _presses.add(null);
    });
  }

  @override
  Stream<void> get presses => _presses.stream;

  @override
  Future<bool> setEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setEnabled', enabled) ?? false;
    } catch (e) {
      debugPrint('Atajo global: $e');
      return false;
    }
  }
}

/// Reproduce los WAV de `assets/sounds/` con NSSound (ver
/// `SoundPlayer.swift`). Cada archivo se envía una sola vez.
class MacosSoundPlayer implements SoundPlayer {
  static const _channel = MethodChannel('com.pixelmate/sound');
  final AssetBundle _bundle;
  final _sent = <PetSound>{};

  MacosSoundPlayer([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;

  @override
  Future<void> play(PetSound sound) async {
    try {
      Uint8List? data;
      if (!_sent.contains(sound)) {
        data = (await _bundle.load('assets/sounds/${sound.name}.wav'))
            .buffer
            .asUint8List();
      }
      final ok = await _channel
          .invokeMethod<bool>('play', {'name': sound.name, 'data': data});
      if (data != null && ok != false) _sent.add(sound);
    } catch (e) {
      debugPrint('Sonido ${sound.name}: $e');
    }
  }
}
