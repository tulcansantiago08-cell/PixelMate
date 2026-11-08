import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// Guarda un archivo de texto donde el usuario elija (diálogo "Guardar").
///
/// Canal "com.pixelmate/files":
///   saveText({name, content}) → ruta guardada, o nil si se canceló.
///
/// Con sandbox, la app solo puede escribir en el sitio que el usuario
/// eligió en el diálogo (permiso files.user-selected.read-write).
enum FileExport {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/files", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "saveText", let args = call.arguments as? [String: Any],
        let name = args["name"] as? String, let content = args["content"] as? String
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let panel = NSSavePanel()
      panel.nameFieldStringValue = name
      panel.allowedContentTypes = [.commaSeparatedText]
      panel.canCreateDirectories = true
      panel.title = "Exportar estadísticas"
      panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      // PixelMate vive en la barra de menú: se trae al frente para que el
      // diálogo no quede detrás de otras ventanas.
      NSApp.activate(ignoringOtherApps: true)
      panel.begin { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        do {
          try content.write(to: url, atomically: true, encoding: .utf8)
          result(url.path)
        } catch {
          result(
            FlutterError(code: "write", message: error.localizedDescription, details: nil))
        }
      }
    }
  }
}
