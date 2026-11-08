import FlutterMacOS
import ServiceManagement

/// Abre PixelMate al iniciar sesión, con el servicio oficial de macOS
/// (Configuración del Sistema → General → Ítems de inicio).
///
/// Canal "com.pixelmate/login_item":
///   isSupported → Bool (macOS 13 o posterior)
///   isEnabled   → Bool
///   setEnabled(Bool) → Bool (estado final)
enum LoginItem {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.pixelmate/login_item", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(call.method == "isSupported" ? false : nil)
        return
      }
      let service = SMAppService.mainApp
      switch call.method {
      case "isSupported":
        result(true)
      case "isEnabled":
        result(service.status == .enabled)
      case "setEnabled":
        let enable = (call.arguments as? Bool) ?? false
        do {
          if enable {
            try service.register()
          } else {
            try service.unregister()
          }
          result(service.status == .enabled)
        } catch {
          result(
            FlutterError(
              code: "login_item", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
