import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var activityMonitor: AppActivityMonitor?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      activityMonitor = AppActivityMonitor.register(with: controller.engine.binaryMessenger)
      LoginItem.register(with: controller.engine.binaryMessenger)
      AppleAssistant.register(with: controller.engine.binaryMessenger)
      GlobalHotKey.register(with: controller.engine.binaryMessenger)
      SoundPlayer.register(with: controller.engine.binaryMessenger)
      FileExport.register(with: controller.engine.binaryMessenger)
      registerAppInfo(with: controller.engine.binaryMessenger)
    }
    super.applicationDidFinishLaunching(notification)
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

  override func applicationShouldTerminateAfterLastWindowClosed(
    _ sender: NSApplication
  ) -> Bool { return true }

  override func applicationSupportsSecureRestorableState(
    _ app: NSApplication
  ) -> Bool { return true }
}
