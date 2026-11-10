import FlutterMacOS
import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// IA de Apple en el dispositivo (Apple Intelligence): gratis, sin conexión
/// y privada — nada sale del Mac.
///
/// Canal "com.pixelmate/apple_ai":
///   availability → "available" | "appleIntelligenceNotEnabled" |
///                  "deviceNotEligible" | "modelNotReady" | "unsupported"
///   respond({instructions, prompt}) → {reply, action, hours}
///     o FlutterError con código: context | guardrail | language | busy |
///     unavailable | other
///   prewarm(instructions) → carga el modelo antes del primer mensaje
///   generateCode(pedido) → texto con el código
///   reset → olvida la conversación
enum AppleAssistant {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.pixelmate/apple_ai", binaryMessenger: messenger)
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        // Se registra desde AppDelegate, en el hilo principal.
        let bridge = MainActor.assumeIsolated { AppleAssistantBridge() }
        channel.setMethodCallHandler { call, result in
          MainActor.assumeIsolated { bridge.handle(call, result: result) }
        }
        return
      }
    #endif
    channel.setMethodCallHandler { call, result in
      if call.method == "availability" {
        result("unsupported")
      } else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
      }
    }
  }
}

#if canImport(FoundationModels)
  /// Lo que la mascota responde: un texto y, si el usuario lo pidió, una
  /// acción que la app ejecuta (la IA nunca toca nada por su cuenta).
  @available(macOS 26.0, *)
  @Generable
  struct MascotReply {
    @Guide(
      description:
        "Lo que le dices al usuario: en español, cálido y breve (1 a 3 oraciones).")
    var reply: String

    @Guide(
      description:
        "Acción de la app que el usuario pidió de forma explícita en su último mensaje. Si no pidió ninguna acción, \"ninguna\".",
      .anyOf([
        "ninguna", "iniciarTrabajo", "iniciarEstudio", "iniciarJuego", "pausar",
        "reanudar", "terminar", "cambiarMeta", "abrirEstadisticas",
        "recordar", "agregarTarea", "completarTarea", "verPendientes", "abrir",
        "verAgenda", "crearEvento",
      ]))
    var action: String

    @Guide(
      description:
        "Horas que el usuario indicó para la jornada o para la meta diaria; 0 si no dijo ninguna.",
      .range(0...12))
    var hours: Int

    @Guide(
      description:
        "Texto de la acción: lo que hay que recordar, la tarea, el nombre de la app o web a abrir, o el título del evento. Vacío si no aplica."
    )
    var detail: String

    @Guide(
      description:
        "Para 'recordar' dentro de un rato: minutos desde ahora (\"en 20 minutos\" = 20). 0 si dijo una hora concreta o no aplica.",
      .range(0...1440))
    var minutes: Int

    @Guide(
      description:
        "Hora concreta en formato 24 h HH:mm (\"a las 5 de la tarde\" = 17:00). Vacío si no dijo hora."
    )
    var time: String

    @Guide(description: "Día: \"hoy\", \"mañana\" o vacío.", .anyOf(["", "hoy", "mañana"]))
    var day: String

    @Guide(
      description:
        "Número de la tarea para 'completarTarea' (la 1 es la primera de la lista). 0 si no aplica.",
      .range(0...50))
    var number: Int
  }

  @available(macOS 26.0, *)
  @MainActor
  final class AppleAssistantBridge {
    private var session: LanguageModelSession?
    private var instructions = ""

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
      switch call.method {
      case "availability":
        result(Self.availability())
      case "generateCode":
        // Sesión aparte: escribir código no se mezcla con la charla.
        guard let request = call.arguments as? String else {
          result(FlutterError(code: "other", message: nil, details: nil))
          return
        }
        Task { @MainActor in
          let coder = LanguageModelSession(
            instructions:
              "Eres un programador experto. Escribes programas completos, cortos y que funcionan. Responde SOLO con el código del archivo, sin explicaciones antes ni después. Los comentarios y los textos para el usuario, en español."
          )
          do {
            let response = try await coder.respond(
              to: request, options: GenerationOptions(temperature: 0.2))
            result(response.content)
          } catch {
            result(
              FlutterError(
                code: Self.classify(error), message: error.localizedDescription, details: nil))
          }
        }
      case "reset":
        session = nil
        result(nil)
      case "prewarm":
        // Carga el modelo antes del primer mensaje (la primera respuesta
        // tarda mucho más si no).
        let instructions = (call.arguments as? String) ?? ""
        if session == nil || instructions != self.instructions {
          session = LanguageModelSession(instructions: instructions)
          self.instructions = instructions
        }
        session?.prewarm()
        result(nil)
      case "respond":
        guard let args = call.arguments as? [String: Any],
          let prompt = args["prompt"] as? String
        else {
          result(FlutterError(code: "other", message: "Faltan argumentos", details: nil))
          return
        }
        let instructions = (args["instructions"] as? String) ?? ""
        Task { @MainActor in
          result(await self.respond(prompt: prompt, instructions: instructions))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    private func respond(prompt: String, instructions: String) async -> Any {
      if session == nil || instructions != self.instructions {
        session = LanguageModelSession(instructions: instructions)
        self.instructions = instructions
      }
      for attempt in 0..<2 {
        do {
          let response = try await session!.respond(
            to: prompt, generating: MascotReply.self,
            options: GenerationOptions(temperature: 0.7))
          let content = response.content
          return [
            "reply": content.reply,
            "action": content.action,
            "hours": content.hours,
            "detail": content.detail,
            "minutes": content.minutes,
            "time": content.time,
            "day": content.day,
            "number": content.number,
          ]
        } catch {
          let code = Self.classify(error)
          // La memoria del modelo es corta: si se llena, empieza una
          // conversación nueva y lo intenta otra vez.
          if code == "context" && attempt == 0 {
            session = LanguageModelSession(instructions: instructions)
            continue
          }
          return FlutterError(
            code: code, message: error.localizedDescription, details: nil)
        }
      }
      return FlutterError(code: "other", message: nil, details: nil)
    }

    static func availability() -> String {
      switch SystemLanguageModel.default.availability {
      case .available:
        return "available"
      case .unavailable(.appleIntelligenceNotEnabled):
        return "appleIntelligenceNotEnabled"
      case .unavailable(.deviceNotEligible):
        return "deviceNotEligible"
      case .unavailable(.modelNotReady):
        return "modelNotReady"
      case .unavailable:
        return "unsupported"
      }
    }

    static func classify(_ error: Error) -> String {
      if #available(macOS 27.0, *) {
        if let e = error as? LanguageModelError {
          switch e {
          case .contextSizeExceeded: return "context"
          case .guardrailViolation, .refusal: return "guardrail"
          case .unsupportedLanguageOrLocale: return "language"
          case .rateLimited: return "busy"
          default: return "other"
          }
        }
      }
      if let e = error as? LanguageModelSession.GenerationError {
        switch e {
        case .exceededContextWindowSize: return "context"
        case .guardrailViolation: return "guardrail"
        case .unsupportedLanguageOrLocale: return "language"
        case .assetsUnavailable: return "unavailable"
        default: return "other"
        }
      }
      return "other"
    }
  }
#endif
