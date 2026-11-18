import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

/// Guarda un archivo de texto donde el usuario elija (diálogo "Guardar").
///
/// Canal "com.pixelmate/files":
///   saveText({name, content, type?, title?}) → ruta guardada, o nil si se
///           canceló.
///   openText({title?}) → texto del JSON elegido, o nil si se canceló.
///
/// Con sandbox, la app solo puede escribir en el sitio que el usuario
/// eligió en el diálogo (permiso files.user-selected.read-write).
enum FileExport {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.pixelmate/files", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveText":
        saveText(call, result)
      case "openText":
        openText(call, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// saveText({name, content, type?: "json", title?}) → ruta o nil.
  private static func saveText(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
      let name = args["name"] as? String, let content = args["content"] as? String
    else {
      result(FlutterError(code: "args", message: nil, details: nil))
      return
    }
    let json = (args["type"] as? String) == "json"
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [json ? .json : .commaSeparatedText]
    panel.canCreateDirectories = true
    panel.title = (args["title"] as? String) ?? "Exportar estadísticas"
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

  /// openText({title?}) → el texto del archivo JSON elegido, o nil.
  private static func openText(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.title = (args?["title"] as? String) ?? "Abrir"
    panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        result(try String(contentsOf: url, encoding: .utf8))
      } catch {
        result(FlutterError(code: "read", message: error.localizedDescription, details: nil))
      }
    }
  }
}
