import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var activityMonitor: AppActivityMonitor?
  private var musicMonitor: MusicMonitor?
  /// Sin App Nap: macOS frena los temporizadores de las apps en segundo
  /// plano y las alarmas sonarían minutos tarde. No impide que el Mac duerma.
  private var punctual: NSObjectProtocol?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    punctual = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: "Alarmas y recordatorios a su hora")
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      activityMonitor = AppActivityMonitor.register(with: controller.engine.binaryMessenger)
      musicMonitor = MusicMonitor.register(with: controller.engine.binaryMessenger)
      LoginItem.register(with: controller.engine.binaryMessenger)
      AppleAssistant.register(with: controller.engine.binaryMessenger)
      GlobalHotKey.register(with: controller.engine.binaryMessenger)
      SoundPlayer.register(with: controller.engine.binaryMessenger)
      VoiceBridge.register(with: controller.engine.binaryMessenger)
      FileExport.register(with: controller.engine.binaryMessenger)
      AssistantBridge.register(with: controller.engine.binaryMessenger)
      registerAppInfo(with: controller.engine.binaryMessenger)
    }
    super.applicationDidFinishLaunching(notification)
    SoundPlayer.log("app: abierta")
  }

  override func applicationWillTerminate(_ notification: Notification) {
    SoundPlayer.log("app: se cierra")
    super.applicationWillTerminate(notification)
  }

  /// Canal "com.pixelmate/app": versión instalada y abrir el repositorio.
  private func registerAppInfo(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/app", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "version":
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        result("\(version) (\(build))")
      case "focus":
        // Toma el teclado: sin ícono en el Dock, un clic no siempre activa
        // la app y los campos de texto no recibirían lo que escribes.
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
          window.makeKeyAndOrderFront(nil)
          if let view = window.contentViewController?.view {
            window.makeFirstResponder(view)
          }
        }
        result(nil)
      case "relaunch":
        // Para cargar una copia restaurada: abre otra PixelMate y se cierra.
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) {
          _, _ in
          DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        result(nil)
      case "openRepository":
        // Solo esta dirección fija: nunca una que venga de fuera.
        if let url = URL(string: "https://github.com/tulcansantiago08-cell/PixelMate") {
          NSWorkspace.shared.open(url)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // Vive en la barra de menú: esconder (o cerrar) la ventana de la mascota
  // no debe cerrar la app, que sigue esperando «Oye <nombre>» y las alarmas.
  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool { return false }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool { return true }
}
