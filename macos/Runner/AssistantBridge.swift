import Cocoa
import EventKit
import FlutterMacOS

/// Lo que la mascota hace como asistente en el Mac.
///
/// Canal "com.pixelmate/assistant":
///   openApp(name) → nombre de la app abierta, o nil si no la encontró
///   openUrl(url)  → Bool (solo http/https)
///   events(dayOffset) → [{title, start, end, allDay}] (ms desde 1970)
///                       o FlutterError "denied" si no hay permiso
///   createEvent({title, start, minutes}) → Bool, o FlutterError "denied"
enum AssistantBridge {
  private static let store = EKEventStore()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/assistant", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openApp":
        result(openApp(named: (call.arguments as? String) ?? ""))
      case "openUrl":
        let args = call.arguments as? [String: Any]
        guard let text = args?["url"] as? String, let url = URL(string: text),
          ["https", "http", "spotify"].contains(url.scheme ?? "")
        else {
          result(false)
          return
        }
        guard let browser = args?["browser"] as? String else {
          result(NSWorkspace.shared.open(url))
          return
        }
        // En el navegador pedido; false si no está instalado.
        guard let id = browsers[browser],
          let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else {
          result(false)
          return
        }
        NSWorkspace.shared.open(
          [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
          DispatchQueue.main.async { result(error == nil) }
        }
      case "saveCode":
        guard let args = call.arguments as? [String: Any],
          let name = args["name"] as? String, let content = args["content"] as? String
        else {
          result(FlutterError(code: "args", message: nil, details: nil))
          return
        }
        saveCode(name: name, content: content, editor: args["editor"] as? String, result: result)
      case "events":
        let offset = (call.arguments as? Int) ?? 0
        withCalendarAccess(result) { result(events(dayOffset: offset)) }
      case "createEvent":
        guard let args = call.arguments as? [String: Any],
          let title = args["title"] as? String,
          let startMs = args["start"] as? Double ?? (args["start"] as? Int).map(Double.init)
        else {
          result(FlutterError(code: "args", message: nil, details: nil))
          return
        }
        let minutes = (args["minutes"] as? Int) ?? 60
        withCalendarAccess(result) {
          let event = EKEvent(eventStore: store)
          event.title = title
          event.startDate = Date(timeIntervalSince1970: startMs / 1000)
          event.endDate = event.startDate.addingTimeInterval(Double(minutes) * 60)
          event.calendar = store.defaultCalendarForNewEvents
          do {
            try store.save(event, span: .thisEvent)
            result(true)
          } catch {
            result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: Abrir apps

  /// Navegadores que se pueden pedir ("en Brave").
  private static let browsers: [String: String] = [
    "Brave": "com.brave.Browser", "Safari": "com.apple.Safari",
    "Chrome": "com.google.Chrome", "Firefox": "org.mozilla.firefox",
    "Arc": "company.thebrowser.Browser", "Edge": "com.microsoft.edgemac",
    "Opera": "com.operasoftware.Opera",
  ]

  /// Apps comunes por nombre (también en español) → bundle id. Sirve aunque
  /// el sandbox no deje listar /Applications.
  private static let known: [String: String] = [
    "spotify": "com.spotify.client", "calculadora": "com.apple.calculator",
    "calculator": "com.apple.calculator", "notas": "com.apple.Notes",
    "notes": "com.apple.Notes", "safari": "com.apple.Safari", "musica": "com.apple.Music",
    "music": "com.apple.Music", "mensajes": "com.apple.MobileSMS",
    "messages": "com.apple.MobileSMS", "mail": "com.apple.mail", "correo": "com.apple.mail",
    "calendario": "com.apple.iCal", "calendar": "com.apple.iCal", "finder": "com.apple.finder",
    "fotos": "com.apple.Photos", "photos": "com.apple.Photos",
    "recordatorios": "com.apple.reminders", "reminders": "com.apple.reminders",
    "terminal": "com.apple.Terminal", "ajustes": "com.apple.systempreferences",
    "configuracion": "com.apple.systempreferences", "whatsapp": "net.whatsapp.WhatsApp",
    "xcode": "com.apple.dt.Xcode", "brave": "com.brave.Browser",
    "chrome": "com.google.Chrome", "visual studio code": "com.microsoft.VSCode",
    "vscode": "com.microsoft.VSCode", "code": "com.microsoft.VSCode",
    "vs code": "com.microsoft.VSCode", "vs": "com.microsoft.VSCode",
    "word": "com.microsoft.Word", "mapas": "com.apple.Maps", "maps": "com.apple.Maps",
    "app store": "com.apple.AppStore", "facetime": "com.apple.FaceTime",
    "vista previa": "com.apple.Preview", "preview": "com.apple.Preview",
  ]

  private static func fold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func openApp(named raw: String) -> String? {
    let name = fold(raw)
    guard !name.isEmpty else { return nil }
    var url: URL?
    if let id = known[name] {
      url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    if url == nil { url = findApp(named: name) }
    guard let app = url else { return nil }
    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    return FileManager.default.displayName(atPath: app.path)
      .replacingOccurrences(of: ".app", with: "")
  }

  /// Busca en las carpetas de apps: primero el nombre exacto, luego el que
  /// lo contenga.
  private static func findApp(named name: String) -> URL? {
    let dirs = [
      "/Applications", "/System/Applications", "/System/Applications/Utilities",
      NSHomeDirectory() + "/Applications",
    ]
    var partial: URL?
    for dir in dirs {
      guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
        continue
      }
      for item in items where item.hasSuffix(".app") {
        let app = fold(String(item.dropLast(4)))
        let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
        if app == name { return url }
        if partial == nil && app.contains(name) { partial = url }
      }
    }
    return partial
  }

  // MARK: Código

  private static let editors: [String: String] = [
    "Visual Studio Code": "com.microsoft.VSCode", "Xcode": "com.apple.dt.Xcode",
    "Sublime Text": "com.sublimetext.4", "Cursor": "com.todesktop.230313mzl4w4u92",
    "Zed": "dev.zed.Zed", "PyCharm": "com.jetbrains.pycharm",
    "IntelliJ IDEA": "com.jetbrains.intellij", "Android Studio": "com.google.android.studio",
    "TextEdit": "com.apple.TextEdit",
  ]

  /// Pregunta dónde guardar (el sandbox solo deja escribir donde elige el
  /// usuario), escribe el archivo y lo abre en el editor pedido; si no se
  /// pidió ninguno, en VS Code si está, o en la app de ese tipo de archivo.
  /// Devuelve {path, editor} o nil si se canceló.
  private static func saveCode(
    name: String, content: String, editor: String?, result: @escaping FlutterResult
  ) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    panel.title = "Guardar el código"
    panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        try content.write(to: url, atomically: true, encoding: .utf8)
      } catch {
        result(FlutterError(code: "write", message: error.localizedDescription, details: nil))
        return
      }
      let wanted = editor ?? "Visual Studio Code"
      if let id = editors[wanted],
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
      {
        NSWorkspace.shared.open(
          [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()
        ) { _, _ in }
        result(["path": url.path, "editor": wanted])
      } else {
        NSWorkspace.shared.open(url)
        result(["path": url.path, "editor": ""])
      }
    }
  }

  // MARK: Calendario

  private static func withCalendarAccess(
    _ result: @escaping FlutterResult, _ action: @escaping () -> Void
  ) {
    let done: (Bool, Error?) -> Void = { granted, _ in
      DispatchQueue.main.async {
        if granted {
          action()
        } else {
          result(FlutterError(code: "denied", message: nil, details: nil))
        }
      }
    }
    if #available(macOS 14.0, *) {
      store.requestFullAccessToEvents(completion: done)
    } else {
      store.requestAccess(to: .event, completion: done)
    }
  }

  private static func events(dayOffset: Int) -> [[String: Any]] {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    guard let start = cal.date(byAdding: .day, value: dayOffset, to: today),
      let end = cal.date(byAdding: .day, value: 1, to: start)
    else { return [] }
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    return store.events(matching: predicate)
      .sorted { $0.startDate < $1.startDate }
      .map {
        [
          "title": $0.title ?? "",
          "start": $0.startDate.timeIntervalSince1970 * 1000,
          "end": $0.endDate.timeIntervalSince1970 * 1000,
          "allDay": $0.isAllDay,
        ]
      }
  }
}
