import Cocoa
import FlutterMacOS

/// Reproduce los sonidos 8-bit de la app (los manda Dart desde sus assets).
///
/// Canal "com.pixelmate/sound":
///   play({name, data?}) → la primera vez llega el WAV; luego basta el nombre.
enum SoundPlayer {
  private static var sounds: [String: NSSound] = [:]
  private static var datas: [String: Data] = [:]

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/sound", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "log" {
        log((call.arguments as? String) ?? "")
        result(nil)
        return
      }
      guard call.method == "play", let args = call.arguments as? [String: Any],
        let name = args["name"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let bytes = (args["data"] as? FlutterStandardTypedData)?.data
      if let data = bytes, let sound = NSSound(data: data) {
        sounds[name] = sound
        datas[name] = data
      }
      guard let sound = sounds[name] else {
        log("play \(name): sin sonido (datos: \(bytes?.count ?? -1))")
        result(false)  // Dart reenvía el archivo
        return
      }
      sound.stop()
      sound.volume = 1
      var ok = sound.play()
      // A veces un NSSound deja de sonar (por ejemplo, tras cambiar la
      // salida de audio o despertar el Mac): se rehace y se prueba otra vez.
      if !ok, let data = datas[name], let fresh = NSSound(data: data) {
        fresh.volume = 1
        sounds[name] = fresh
        ok = fresh.play()
      }
      if !ok { log("play \(name): no sonó") }
      result(ok)
    }
  }

  /// Registro breve para diagnosticar sonidos (Library/Logs/pixelmate.log
  /// del contenedor de la app; se recorta solo).
  static func log(_ line: String) {
    let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("pixelmate.log")
    let text = "\(Date()) \(line)\n"
    if let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
      size > 200_000
    {
      try? FileManager.default.removeItem(at: file)
    }
    if let handle = try? FileHandle(forWritingTo: file) {
      handle.seekToEndOfFile()
      handle.write(text.data(using: .utf8)!)
      try? handle.close()
    } else {
      try? text.data(using: .utf8)!.write(to: file)
    }
  }
}
