import AudioToolbox
import Cocoa
import Contacts
import CoreAudio
import EventKit
import FlutterMacOS

/// Lo que la mascota hace como asistente en el Mac.
///
/// Canal "com.pixelmate/assistant":
///   openApp(name) → nombre de la app abierta, o nil si no la encontró
///   openUrl(url)  → Bool (http/https, spotify y whatsapp)
///   events(dayOffset) → [{title, start, end, allDay}] (ms desde 1970)
///                       o FlutterError "denied" si no hay permiso
///   createEvent({title, start, minutes}) → Bool, o FlutterError "denied"
///   closeApp(name) / hideApp(name) → nombre de la app, o nil si no estaba abierta
///   runningApps → [nombre] de las apps abiertas
///   media({action: play|pause|toggle|next|previous|now, player?}) →
///         {player, track?} o {error: none|denied}
///   volume({action: get|up|down|set|mute|unmute, value}) → {level, muted}
///          (level 0–100) o nil si la salida de sonido no deja cambiarlo
enum AssistantBridge {
  private static let store = EKEventStore()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/assistant", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openApp":
        result(openApp(named: (call.arguments as? String) ?? ""))
      case "closeApp":
        result(closeApp(named: (call.arguments as? String) ?? ""))
      case "hideApp":
        result(hideApp(named: (call.arguments as? String) ?? ""))
      case "runningApps":
        result(runningApps().compactMap { $0.localizedName })
      case "media":
        let args = call.arguments as? [String: Any]
        result(
          MediaControl.run(
            (args?["action"] as? String) ?? "toggle", player: args?["player"] as? String))
      case "volume":
        let args = call.arguments as? [String: Any]
        result(
          SystemVolume.change(
            action: (args?["action"] as? String) ?? "get", value: (args?["value"] as? Int) ?? 0))
      case "openUrl":
        let args = call.arguments as? [String: Any]
        guard let text = args?["url"] as? String, let url = URL(string: text),
          ["https", "http", "spotify", "whatsapp"].contains(url.scheme ?? "")
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
        let allDay = (args["allDay"] as? Bool) ?? false
        // Aviso del Calendario: minutos antes (o, todo el día, a esa hora
        // contada desde la medianoche).
        let alert = args["alert"] as? Int
        withCalendarAccess(result) {
          let event = EKEvent(eventStore: store)
          event.title = title
          event.startDate = Date(timeIntervalSince1970: startMs / 1000)
          event.isAllDay = allDay
          event.endDate =
            allDay
            ? event.startDate.addingTimeInterval(24 * 3600)
            : event.startDate.addingTimeInterval(Double(minutes) * 60)
          switch args["repeat"] as? String {
          case "weekly":
            event.addRecurrenceRule(
              EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
          case "yearly":
            event.addRecurrenceRule(
              EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil))
          default:
            break
          }
          if let alert = alert {
            event.addAlarm(EKAlarm(relativeOffset: Double(allDay ? alert : -alert) * 60))
          }
          event.calendar = store.defaultCalendarForNewEvents
          do {
            try store.save(event, span: .thisEvent)
            result(event.eventIdentifier ?? "")
          } catch {
            result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
          }
        }
      case "findContacts":
        // [{name, nickname, phones}] de los contactos que coinciden con el
        // texto en el nombre, apellido, apodo o empresa (sin tildes,
        // mayúsculas ni emojis).
        let query = (call.arguments as? String) ?? ""
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
          DispatchQueue.global(qos: .userInitiated).async {
            guard granted else {
              DispatchQueue.main.async {
                result(FlutterError(code: "denied", message: nil, details: nil))
              }
              return
            }
            func fold(_ s: String) -> String {
              let plain = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
              return String(plain.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0) || $0 == " "
              }.map(Character.init)).trimmingCharacters(in: .whitespaces)
            }
            let q = fold(query)
            let words = q.split(separator: " ").map(String.init)
            let keys: [CNKeyDescriptor] = [
              CNContactGivenNameKey as CNKeyDescriptor,
              CNContactFamilyNameKey as CNKeyDescriptor,
              CNContactNicknameKey as CNKeyDescriptor,
              CNContactOrganizationNameKey as CNKeyDescriptor,
              CNContactPhoneNumbersKey as CNKeyDescriptor,
            ]
            var total = 0
            var found: [[String: Any]] = []
            let request = CNContactFetchRequest(keysToFetch: keys)
            do {
              try store.enumerateContacts(with: request) { c, _ in
                total += 1
                let full = fold("\(c.givenName) \(c.familyName)")
                let fields = [full, fold(c.nickname), fold(c.organizationName)]
                let hit =
                  !words.isEmpty
                  && fields.contains { field in words.allSatisfy { field.contains($0) } }
                guard hit, found.count < 10 else { return }
                let name = [c.givenName, c.familyName].filter { !$0.isEmpty }
                  .joined(separator: " ")
                found.append([
                  "name": name.isEmpty ? (c.nickname.isEmpty ? c.organizationName : c.nickname) : name,
                  "nickname": c.nickname,
                  "phones": c.phoneNumbers.map { $0.value.stringValue },
                ])
              }
              DispatchQueue.main.async {
                SoundPlayer.log("contactos: \(total) en total, \(found.count) coinciden")
                result(found)
              }
            } catch {
              DispatchQueue.main.async {
                result(FlutterError(code: "failed", message: error.localizedDescription, details: nil))
              }
            }
          }
        }
      case "copyText":
        NSPasteboard.general.clearContents()
        result(NSPasteboard.general.setString((call.arguments as? String) ?? "", forType: .string))
      case "regionCode":
        result((Locale.current as NSLocale).countryCode ?? "")
      case "audioPlaying":
        result(SystemVolume.isPlaying())
      case "runShortcut":
        // Atajos de la app Atajos (para el modo Concentración).
        let name = ((call.arguments as? String) ?? "")
          .replacingOccurrences(of: "\\", with: "")
          .replacingOccurrences(of: "\"", with: "")
        var error: NSDictionary?
        NSAppleScript(
          source: "tell application id \"com.apple.shortcuts.events\" to run shortcut \"\(name)\""
        )?.executeAndReturnError(&error)
        if let error = error {
          let code = (error[NSAppleScript.errorNumber] as? Int) ?? -1
          result(code == -1743 ? "denied" : code == -1728 || code == -1700 ? "missing" : "failed")
        } else {
          result("ok")
        }
      case "addReminder":
        guard let args = call.arguments as? [String: Any], let title = args["title"] as? String
        else {
          result(FlutterError(code: "args", message: nil, details: nil))
          return
        }
        let dueMs = (args["due"] as? Double) ?? (args["due"] as? Int).map(Double.init)
        withRemindersAccess(result) {
          let reminder = EKReminder(eventStore: store)
          reminder.title = title
          reminder.calendar = store.defaultCalendarForNewReminders()
          if let ms = dueMs {
            let date = Date(timeIntervalSince1970: ms / 1000)
            reminder.dueDateComponents = Calendar.current.dateComponents(
              [.year, .month, .day, .hour, .minute], from: date)
          }
          do {
            try store.save(reminder, commit: true)
            result(reminder.calendarItemIdentifier)
          } catch {
            result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
          }
        }
      case "setReminderDone":
        guard let args = call.arguments as? [String: Any], let id = args["id"] as? String
        else {
          result(FlutterError(code: "args", message: nil, details: nil))
          return
        }
        let done = (args["done"] as? Bool) ?? true
        withRemindersAccess(result) {
          guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            result(false)
            return
          }
          reminder.isCompleted = done
          do {
            try store.save(reminder, commit: true)
            result(true)
          } catch {
            result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
          }
        }
      case "removeReminder":
        let id = (call.arguments as? String) ?? ""
        withRemindersAccess(result) {
          guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            result(false)
            return
          }
          do {
            try store.remove(reminder, commit: true)
            result(true)
          } catch {
            result(FlutterError(code: "save", message: error.localizedDescription, details: nil))
          }
        }
      case "remindersDone":
        // {id: hecho} de los que siguen existiendo.
        let ids = (call.arguments as? [String]) ?? []
        withRemindersAccess(result) {
          var states: [String: Bool] = [:]
          for id in ids {
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder {
              states[id] = reminder.isCompleted
            }
          }
          result(states)
        }
      case "deleteEvent":
        let id = (call.arguments as? String) ?? ""
        withCalendarAccess(result) {
          guard let event = store.event(withIdentifier: id) else {
            result(false)
            return
          }
          do {
            try store.remove(event, span: .futureEvents)
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
    "spotify": "com.spotify.client", "apple music": "com.apple.Music",
    "itunes": "com.apple.Music", "musica de apple": "com.apple.Music", "calculadora": "com.apple.calculator",
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
    "contactos": "com.apple.AddressBook", "contacts": "com.apple.AddressBook",
    "podcasts": "com.apple.podcasts", "libros": "com.apple.iBooksX", "books": "com.apple.iBooksX",
    "reloj": "com.apple.clock", "clock": "com.apple.clock", "clima": "com.apple.weather",
    "tiempo": "com.apple.weather", "weather": "com.apple.weather",
    "notas de voz": "com.apple.VoiceMemos", "grabadora": "com.apple.VoiceMemos",
    "tv": "com.apple.TV", "apple tv": "com.apple.TV", "home": "com.apple.Home",
    "casa": "com.apple.Home", "buscar": "com.apple.findmy", "encontrar": "com.apple.findmy",
    "ajustes del sistema": "com.apple.systempreferences",
    "configuracion del sistema": "com.apple.systempreferences",
    "preferencias del sistema": "com.apple.systempreferences",
    "monitor de actividad": "com.apple.ActivityMonitor",
    "captura de pantalla": "com.apple.screenshot.launcher",
    "textedit": "com.apple.TextEdit", "editor de texto": "com.apple.TextEdit",
    "pages": "com.apple.iWork.Pages", "numbers": "com.apple.iWork.Numbers",
    "keynote": "com.apple.iWork.Keynote", "freeform": "com.apple.freeform",
    "pizarra": "com.apple.freeform", "atajos": "com.apple.shortcuts",
    "shortcuts": "com.apple.shortcuts", "launchpad": "com.apple.launchpad.launcher",
    "apps": "com.apple.apps.launcher",
    "discord": "com.hnc.Discord", "slack": "com.tinyspeck.slackmacgap",
    "telegram": "ru.keepcoder.Telegram", "zoom": "us.zoom.xos",
    "teams": "com.microsoft.teams2", "excel": "com.microsoft.Excel",
    "powerpoint": "com.microsoft.Powerpoint", "outlook": "com.microsoft.Outlook",
    "notion": "notion.id", "obsidian": "md.obsidian", "steam": "com.valvesoftware.steam",
    "firefox": "org.mozilla.firefox", "arc": "company.thebrowser.Browser",
  ]

  private static func fold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func openApp(named raw: String) -> String? {
    let name = cleanName(raw)
    guard !name.isEmpty else { return nil }
    var url: URL?
    if let id = known[name] {
      url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    if url == nil { url = bestMatch(name, in: installedApps()) }
    guard let app = url else { return nil }
    NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    return FileManager.default.displayName(atPath: app.path)
      .replacingOccurrences(of: ".app", with: "")
  }

  /// "la app de Notas", "aplicación Música" → "notas", "musica".
  private static func cleanName(_ raw: String) -> String {
    var name = fold(raw)
    for prefix in ["la aplicacion de ", "la app de ", "aplicacion de ", "app de ", "la aplicacion ",
      "la app ", "aplicacion ", "app ", "el ", "la ", "los ", "las ",
    ] where name.hasPrefix(prefix) {
      name = String(name.dropFirst(prefix.count))
    }
    return name.trimmingCharacters(in: .whitespaces)
  }

  /// Apps abiertas con ventana (no PixelMate).
  static func runningApps() -> [NSRunningApplication] {
    let me = Bundle.main.bundleIdentifier
    return NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && $0.bundleIdentifier != me
    }
  }

  /// Una app abierta por su nombre (en español o inglés, aunque esté mal
  /// dicho).
  static func runningApp(named raw: String) -> NSRunningApplication? {
    let name = cleanName(raw)
    guard !name.isEmpty else { return nil }
    let running = runningApps()
    if let id = known[name], let app = running.first(where: { $0.bundleIdentifier == id }) {
      return app
    }
    let candidates: [(NSRunningApplication, [String])] = running.map { app in
      var names = [fold(app.localizedName ?? "")]
      if let url = app.bundleURL {
        names.append(fold(url.deletingPathExtension().lastPathComponent))
      }
      return (app, names)
    }
    return bestMatch(name, in: candidates)
  }

  /// Cierra una app abierta por su nombre.
  private static func closeApp(named raw: String) -> String? {
    guard let target = runningApp(named: raw), target.terminate() else { return nil }
    return target.localizedName
  }

  /// Oculta una app abierta.
  private static func hideApp(named raw: String) -> String? {
    guard let target = runningApp(named: raw), target.hide() else { return nil }
    return target.localizedName
  }

  private static var appCache: (time: Date, apps: [(URL, [String])])?

  /// Las apps instaladas con su nombre de archivo y el que ves en el Finder
  /// (en tu idioma: "Notas", "Música"…).
  private static func installedApps() -> [(URL, [String])] {
    if let cache = appCache, Date().timeIntervalSince(cache.time) < 60 { return cache.apps }
    let dirs = [
      "/Applications", "/Applications/Utilities", "/System/Applications",
      "/System/Applications/Utilities",
      FileManager.default.homeDirectoryForCurrentUser.path + "/Applications",
      "/Users/\(NSUserName())/Applications",
    ]
    var apps: [(URL, [String])] = []
    for dir in dirs {
      guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
        continue
      }
      for item in items where item.hasSuffix(".app") {
        let url = URL(fileURLWithPath: dir).appendingPathComponent(item)
        let shown = FileManager.default.displayName(atPath: url.path)
          .replacingOccurrences(of: ".app", with: "")
        apps.append((url, [fold(String(item.dropLast(4))), fold(shown)]))
      }
    }
    appCache = (Date(), apps)
    return apps
  }

  /// El mejor candidato para [name]: el nombre exacto, luego uno que lo
  /// contenga (o que esté contenido), luego uno con una o dos letras
  /// distintas (lo que entendió mal el dictado).
  private static func bestMatch<T>(_ name: String, in candidates: [(T, [String])]) -> T? {
    if let exact = candidates.first(where: { $0.1.contains(name) }) { return exact.0 }
    if let part = candidates.first(where: { $0.1.contains { $0.contains(name) } }) {
      return part.0
    }
    if name.count >= 4,
      let part = candidates.first(where: { $0.1.contains { $0.count >= 4 && name.contains($0) } })
    {
      return part.0
    }
    let allowed = name.count >= 7 ? 2 : name.count >= 4 ? 1 : 0
    guard allowed > 0 else { return nil }
    var best: (T, Int)?
    for (item, names) in candidates {
      for n in names {
        let d = distance(name, n)
        if d <= allowed, d < (best?.1 ?? Int.max) { best = (item, d) }
      }
    }
    return best?.0
  }

  private static func distance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    for i in 1...a.count {
      var cur = [i] + Array(repeating: 0, count: b.count)
      for j in 1...b.count {
        cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
      }
      prev = cur
    }
    return prev[b.count]
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

  private static func withRemindersAccess(
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
      store.requestFullAccessToReminders(completion: done)
    } else {
      store.requestAccess(to: .reminder, completion: done)
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
          "id": $0.eventIdentifier ?? "",
          "title": $0.title ?? "",
          "start": $0.startDate.timeIntervalSince1970 * 1000,
          "end": $0.endDate.timeIntervalSince1970 * 1000,
          "allDay": $0.isAllDay,
        ]
      }
  }
}

/// Volumen de la salida de sonido actual (CoreAudio).
enum SystemVolume {
  private static func device() -> AudioDeviceID? {
    var id = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultOutputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return status == noErr && id != 0 ? id : nil
  }

  /// Si alguna app está sacando sonido por la salida actual.
  static func isPlaying() -> Bool {
    guard let id = device() else { return false }
    var running = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &running)
    return status == noErr && running != 0
  }

  private static var volumeAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain)

  private static var muteAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyMute,
    mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain)

  private static func level(_ id: AudioDeviceID) -> Float? {
    var value = Float32(0)
    var size = UInt32(MemoryLayout<Float32>.size)
    guard AudioObjectHasProperty(id, &volumeAddress),
      AudioObjectGetPropertyData(id, &volumeAddress, 0, nil, &size, &value) == noErr
    else { return nil }
    return value
  }

  private static func setLevel(_ id: AudioDeviceID, _ value: Float) -> Bool {
    var v = Float32(min(max(value, 0), 1))
    var settable: DarwinBoolean = false
    guard AudioObjectIsPropertySettable(id, &volumeAddress, &settable) == noErr,
      settable.boolValue
    else { return false }
    return AudioObjectSetPropertyData(
      id, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
  }

  private static func muted(_ id: AudioDeviceID) -> Bool {
    var value = UInt32(0)
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectHasProperty(id, &muteAddress),
      AudioObjectGetPropertyData(id, &muteAddress, 0, nil, &size, &value) == noErr
    else { return false }
    return value != 0
  }

  @discardableResult
  private static func setMuted(_ id: AudioDeviceID, _ on: Bool) -> Bool {
    var value = UInt32(on ? 1 : 0)
    guard AudioObjectHasProperty(id, &muteAddress) else { return false }
    return AudioObjectSetPropertyData(
      id, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
  }

  /// [value]: el paso (up/down) o el nivel (set), de 0 a 100.
  static func change(action: String, value: Int) -> [String: Any]? {
    guard let id = device(), let current = level(id) else { return nil }
    let step = Float(value) / 100
    switch action {
    case "up":
      if muted(id) { setMuted(id, false) }
      guard setLevel(id, current + step) else { return nil }
    case "down":
      guard setLevel(id, current - step) else { return nil }
    case "set":
      if value > 0, muted(id) { setMuted(id, false) }
      guard setLevel(id, step) else { return nil }
    case "mute":
      guard setMuted(id, true) else { return nil }
    case "unmute":
      setMuted(id, false)
      if current < 0.05 { _ = setLevel(id, 0.3) }
    default:
      break
    }
    let now = level(id) ?? current
    return ["level": Int((now * 100).rounded()), "muted": muted(id)]
  }
}

/// Controla la música de Spotify o Música (Apple Music) con AppleScript.
/// macOS pide permiso la primera vez ("PixelMate quiere controlar Spotify").
enum MediaControl {
  private static let players = [
    ("Spotify", "com.spotify.client"), ("Música", "com.apple.Music"),
  ]

  private static func script(_ id: String, _ body: String) -> (String?, Int?) {
    var error: NSDictionary?
    let out = NSAppleScript(source: "tell application id \"\(id)\"\n\(body)\nend tell")?
      .executeAndReturnError(&error)
    if let error = error {
      return (nil, (error[NSAppleScript.errorNumber] as? Int) ?? -1)
    }
    return (out?.stringValue, nil)
  }

  static func run(_ action: String, player: String?) -> [String: Any] {
    let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
    var open = players.filter { running.contains($0.1) }
    if let wanted = player?.lowercased() {
      open = open.filter { $0.0.lowercased().hasPrefix(wanted.prefix(4)) || $0.1.lowercased().contains(wanted) }
    }
    guard !open.isEmpty else { return ["error": "none"] }
    // El que esté sonando; si no, el primero abierto.
    var chosen = open[0]
    for p in open where script(p.1, "player state as string").0 == "playing" {
      chosen = p
      break
    }
    let body: String
    switch action {
    case "play": body = "play"
    case "pause": body = "pause"
    case "next": body = "next track"
    case "previous": body = "previous track"
    case "now": body = "return (name of current track) & \" — \" & (artist of current track)"
    default: body = "playpause"
    }
    let (out, error) = script(chosen.1, body)
    if let error = error {
      return ["error": error == -1743 ? "denied" : "failed", "player": chosen.0]
    }
    var reply: [String: Any] = ["player": chosen.0]
    if let out = out, action == "now" { reply["track"] = out }
    return reply
  }
}
