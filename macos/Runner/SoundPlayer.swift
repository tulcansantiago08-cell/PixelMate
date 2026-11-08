import Cocoa
import FlutterMacOS

/// Reproduce los sonidos 8-bit de la app (los manda Dart desde sus assets).
///
/// Canal "com.pixelmate/sound":
///   play({name, data?}) → la primera vez llega el WAV; luego basta el nombre.
enum SoundPlayer {
  private static var sounds: [String: NSSound] = [:]

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/sound", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "play", let args = call.arguments as? [String: Any],
        let name = args["name"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let data = (args["data"] as? FlutterStandardTypedData)?.data,
        let sound = NSSound(data: data)
      {
        sounds[name] = sound
      }
      guard let sound = sounds[name] else {
        result(false)  // Dart reenvía el archivo
        return
      }
      sound.stop()
      result(sound.play())
    }
  }
}
