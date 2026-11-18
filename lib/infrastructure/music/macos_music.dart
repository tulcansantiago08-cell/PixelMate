import 'package:flutter/services.dart';

import '../../application/mascot/music.dart';

/// Canciones de Spotify y Música, desde `MusicMonitor` (Swift).
class MacosMusic {
  static const _channel = EventChannel('com.pixelmate/music');

  Stream<NowPlaying> get events => _channel
      .receiveBroadcastStream()
      .map((e) => NowPlaying.fromMap(e as Map<Object?, Object?>));
}
