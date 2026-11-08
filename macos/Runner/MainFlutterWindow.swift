import Cocoa
import FlutterMacOS
import ScreenCaptureKit

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // Fondo transparente: solo se ve la mascota, no un recuadro negro.
    flutterViewController.backgroundColor = .clear
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Registrar channel de captura de pantalla
    let channel = FlutterMethodChannel(
      name: "com.pixelmate/screen_capture",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "hasPermission":
        result(CGPreflightScreenCaptureAccess())
      case "requestPermission":
        // Solo muestra el diálogo de macOS la primera vez; después el usuario
        // debe activarlo en Ajustes → Privacidad → Grabación de pantalla.
        result(CGRequestScreenCaptureAccess())
      case "captureScreen":
        self.captureScreen(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  /// Ancho máximo de la imagen enviada a Claude (la API reduce todo lo que
  /// pase de ~1568 px, y el límite por imagen es 5 MB).
  private static let maxCaptureWidth = 1280

  private func captureScreen(result: @escaping FlutterResult) {
    // Sin permiso, macOS no falla: devuelve solo el fondo de escritorio.
    guard CGPreflightScreenCaptureAccess() else {
      result(FlutterError(code: "PERMISSION_DENIED", message: "Sin permiso de grabación de pantalla", details: nil))
      return
    }

    if #available(macOS 14.0, *) {
      captureWithScreenCaptureKit(result: result)
    } else {
      captureWithCoreGraphics(result: result)
    }
  }

  /// macOS 14+: API moderna (CGWindowListCreateImage está obsoleta desde macOS 15).
  @available(macOS 14.0, *)
  private func captureWithScreenCaptureKit(result: @escaping FlutterResult) {
    Task {
      do {
        let content = try await SCShareableContent.excludingDesktopWindows(
          false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first else {
          DispatchQueue.main.async {
            result(FlutterError(code: "NO_SCREEN", message: "No se encontró pantalla", details: nil))
          }
          return
        }

        let config = SCStreamConfiguration()
        let scale = min(1.0, CGFloat(Self.maxCaptureWidth) / CGFloat(display.width))
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(
          contentFilter: SCContentFilter(display: display, excludingWindows: []),
          configuration: config)

        let encoded = Self.encodeJPEG(image)
        DispatchQueue.main.async {
          result(encoded ?? FlutterError(code: "ENCODE_FAILED", message: "No se pudo codificar JPEG", details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "CAPTURE_FAILED", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  /// macOS 12–13: método clásico.
  private func captureWithCoreGraphics(result: @escaping FlutterResult) {
    guard let screen = NSScreen.main,
          let image = CGWindowListCreateImage(
            screen.frame, .optionOnScreenOnly, kCGNullWindowID, [.boundsIgnoreFraming])
    else {
      result(FlutterError(code: "CAPTURE_FAILED", message: "No se pudo capturar la pantalla", details: nil))
      return
    }
    result(Self.encodeJPEG(image)
           ?? FlutterError(code: "ENCODE_FAILED", message: "No se pudo codificar JPEG", details: nil))
  }

  /// Reduce a maxCaptureWidth (si hace falta) y devuelve JPEG en base64.
  private static func encodeJPEG(_ image: CGImage) -> String? {
    let scale = min(1.0, CGFloat(maxCaptureWidth) / CGFloat(image.width))
    let width = Int(CGFloat(image.width) * scale)
    let height = Int(CGFloat(image.height) * scale)

    guard let context = CGContext(
      data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    guard let resized = context.makeImage(),
          let jpeg = NSBitmapImageRep(cgImage: resized)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    else { return nil }
    return jpeg.base64EncodedString()
  }
}
