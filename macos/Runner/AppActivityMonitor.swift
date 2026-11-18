import Cocoa
import FlutterMacOS

/// Informa a Flutter de qué aplicación está en primer plano.
///
/// Privacidad: solo envía el identificador, el nombre y el ejecutable de la
/// app activa. No lee títulos de ventana, contenido ni teclado, y no
/// necesita permisos especiales. Se basa en notificaciones del sistema, sin
/// consultar en bucle.
final class AppActivityMonitor: NSObject, FlutterStreamHandler {
  private static let channelName = "com.pixelmate/app_activity"

  private var sink: FlutterEventSink?
  private var observer: NSObjectProtocol?

  static func register(with messenger: FlutterBinaryMessenger) -> AppActivityMonitor {
    let monitor = AppActivityMonitor()
    FlutterEventChannel(name: channelName, binaryMessenger: messenger)
      .setStreamHandler(monitor)
    return monitor
  }

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      self?.send(app)
    }
    // Estado inicial: la app que ya estaba activa al abrir PixelMate.
    send(NSWorkspace.shared.frontmostApplication)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    observer = nil
    sink = nil
    return nil
  }

  private func send(_ app: NSRunningApplication?) {
    guard let app, let sink else { return }
    // PixelMate no se sugiere a sí misma.
    if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
    sink([
      "bundleId": app.bundleIdentifier as Any,
      "name": app.localizedName as Any,
      "executable": app.executableURL?.lastPathComponent as Any,
    ])
  }
}

/// Avisa a Flutter cuando Spotify o Música empiezan o paran una canción.
///
/// Privacidad: solo escucha el aviso público que esas apps envían al cambiar
/// de canción (estado, título y artista). No controla las apps ni pide
/// permisos de automatización.
final class MusicMonitor: NSObject, FlutterStreamHandler {
  private static let channelName = "com.pixelmate/music"
  private static let sources = [
    "com.spotify.client.PlaybackStateChanged": "spotify",
    "com.apple.Music.playerInfo": "music",
  ]

  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []

  static func register(with messenger: FlutterBinaryMessenger) -> MusicMonitor {
    let monitor = MusicMonitor()
    FlutterEventChannel(name: channelName, binaryMessenger: messenger)
      .setStreamHandler(monitor)
    return monitor
  }

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    let center = DistributedNotificationCenter.default()
    for (name, source) in MusicMonitor.sources {
      observers.append(center.addObserver(
        forName: Notification.Name(name), object: nil, queue: .main
      ) { [weak self] note in
        let info = note.userInfo ?? [:]
        self?.sink?([
          "source": source,
          "state": info["Player State"] as? String ?? "",
          "title": info["Name"] as? String ?? "",
          "artist": info["Artist"] as? String ?? "",
        ])
      })
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    let center = DistributedNotificationCenter.default()
    observers.forEach(center.removeObserver)
    observers = []
    sink = nil
    return nil
  }
}
