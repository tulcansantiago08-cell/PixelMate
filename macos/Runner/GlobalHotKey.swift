import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// Atajos de teclado globales (funcionan aunque PixelMate no esté al frente):
/// ⌃⌥P abre el chat y ⌃⌥V lo abre escuchando tu voz.
///
/// Usa RegisterEventHotKey de Carbon: no necesita permisos de
/// accesibilidad ni lee ninguna otra tecla.
///
/// Canal "com.pixelmate/hotkey":
///   setEnabled(Bool) → Bool (false si otra app ya usa la combinación)
///   ← pressed / voice (de Swift a Dart al pulsar ⌃⌥P / ⌃⌥V)
final class GlobalHotKey {
  private static var shared: GlobalHotKey?
  private let channel: FlutterMethodChannel
  private var hotKeyRef: EventHotKeyRef?
  private var voiceKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  private init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let hotKey = GlobalHotKey(
      channel: FlutterMethodChannel(name: "com.pixelmate/hotkey", binaryMessenger: messenger))
    shared = hotKey
    hotKey.channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setEnabled":
        result(hotKey.setEnabled((call.arguments as? Bool) ?? false))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setEnabled(_ enabled: Bool) -> Bool {
    if !enabled {
      if let ref = hotKeyRef {
        UnregisterEventHotKey(ref)
        hotKeyRef = nil
      }
      if let ref = voiceKeyRef {
        UnregisterEventHotKey(ref)
        voiceKeyRef = nil
      }
      return true
    }
    if hotKeyRef != nil { return true }
    installHandler()
    let id = EventHotKeyID(signature: OSType(0x504D_4154), id: 1)  // "PMAT"
    let status = RegisterEventHotKey(
      UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey), id,
      GetApplicationEventTarget(), 0, &hotKeyRef)
    if voiceKeyRef == nil {
      // Si otra app ya usa ⌃⌥V, solo queda el de abrir el chat.
      RegisterEventHotKey(
        UInt32(kVK_ANSI_V), UInt32(controlKey | optionKey),
        EventHotKeyID(signature: OSType(0x504D_4154), id: 2),
        GetApplicationEventTarget(), 0, &voiceKeyRef)
    }
    return status == noErr
  }

  private func installHandler() {
    guard handlerRef == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        var key = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
        let voice = key.id == 2
        DispatchQueue.main.async { GlobalHotKey.shared?.pressed(voice: voice) }
        return noErr
      }, 1, &spec, nil, &handlerRef)
  }

  private func pressed(voice: Bool) {
    // Al frente, para poder escribir en el chat enseguida.
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
    channel.invokeMethod(voice ? "voice" : "pressed", arguments: nil)
  }
}
