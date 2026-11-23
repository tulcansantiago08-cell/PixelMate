import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/desktop/app_info.dart';
import '../../application/desktop/global_shortcut.dart';
import '../../application/desktop/login_item.dart';
import '../../application/desktop/sounds.dart';

/// Versión de la app y enlace al proyecto (Windows y Linux).
class PortableAppInfo implements AppInfo {
  static final repository = Uri.parse('https://github.com/tulcansantiago08-cell/PixelMate');

  @override
  Future<String> version() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '?';
    }
  }

  @override
  Future<void> openRepository() async {
    await launchUrl(repository, mode: LaunchMode.externalApplication);
  }
}

/// Sonidos 8-bit con el reproductor multiplataforma.
class PortableSoundPlayer implements SoundPlayer {
  final _player = AudioPlayer();

  @override
  Future<void> play(PetSound sound) async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/${sound.name}.wav'));
    } catch (e) {
      debugPrint('Sonido ${sound.name}: $e');
    }
  }
}

/// Fuera del Mac no hay atajos globales: la opción no se muestra.
class NoGlobalShortcut implements GlobalShortcutPort {
  @override
  Future<bool> setEnabled(bool enabled) async => false;

  @override
  Stream<void> get presses => const Stream.empty();

  @override
  Stream<void> get voicePresses => const Stream.empty();
}

/// Fuera del Mac, abrir al iniciar sesión no está disponible.
class NoLoginItem implements LoginItemPort {
  @override
  Future<bool> isSupported() async => false;

  @override
  Future<bool> isEnabled() async => false;

  @override
  Future<bool> setEnabled(bool enabled) async => false;
}
