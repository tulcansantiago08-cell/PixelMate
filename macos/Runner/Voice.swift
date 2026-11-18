import AVFoundation
import Cocoa
import FlutterMacOS
import Speech

/// La voz de la mascota: entiende lo que le dices (reconocimiento de voz de
/// Apple, dentro del Mac cuando el idioma lo permite) y lee sus respuestas.
///
/// Canal "com.pixelmate/voice":
///   start → nil si ya escucha; si no, un código: "speech-denied" (sin permiso
///           de reconocimiento de voz), "mic-denied" (sin permiso del
///           micrófono), "mic" (no hay micrófono) o "unavailable".
///   stop → deja de escuchar; llega el texto final.
///   cancel → deja de escuchar sin texto.
///   speak(String) / stopSpeaking
///   startWake(nombre) → como start, pero espera a oír «oye/hola <nombre>»
///           (solo si el Mac reconoce la voz sin internet: "offline" si no).
///   stopWake
///
/// Eventos "com.pixelmate/voice/events": {type: partial | done | end | wake,
/// text}. "end" llega si terminó sin texto final (silencio o error). "wake"
/// llega al oír el nombre; desde ahí es como si se hubiera pulsado start, y
/// el texto es lo que dijo después del nombre.
final class VoiceBridge: NSObject, FlutterStreamHandler {
  private static var shared: VoiceBridge?
  private var sink: FlutterEventSink?
  private let engine = AVAudioEngine()
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var tapInstalled = false
  private var session = 0
  private let synth = AVSpeechSynthesizer()

  /// Nombre que despierta a la mascota (modo «oye <nombre>»), o nil.
  private var wakeName: String?
  /// Ya oyó el nombre en esta sesión.
  private var woke = false
  private var wakeTimer: Timer?

  static func register(with messenger: FlutterBinaryMessenger) {
    let bridge = VoiceBridge()
    shared = bridge
    bridge.watchScreen()
    FlutterEventChannel(name: "com.pixelmate/voice/events", binaryMessenger: messenger)
      .setStreamHandler(bridge)
    let channel = FlutterMethodChannel(name: "com.pixelmate/voice", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        bridge.wakeName = nil
        bridge.start(result)
      case "startWake":
        let name = (call.arguments as? String) ?? ""
        bridge.wakeName = name.isEmpty ? nil : name
        if bridge.paused {
          result(nil)
          return
        }
        bridge.start(result)
      case "stopWake":
        if bridge.wakeName != nil && !bridge.woke { bridge.cancel() }
        bridge.wakeName = nil
        bridge.paused = false
        result(nil)
      case "stop":
        bridge.stop()
        result(nil)
      case "cancel":
        bridge.cancel()
        result(nil)
      case "speak":
        bridge.speak((call.arguments as? String) ?? "")
        result(nil)
      case "stopSpeaking":
        bridge.synth.stopSpeaking(at: .immediate)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  // MARK: - Escuchar

  private func start(_ result: @escaping FlutterResult) {
    synth.stopSpeaking(at: .immediate)
    SFSpeechRecognizer.requestAuthorization { status in
      DispatchQueue.main.async {
        guard status == .authorized else {
          result("speech-denied")
          return
        }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          DispatchQueue.main.async {
            guard granted else {
              result("mic-denied")
              return
            }
            result(self.begin(wake: self.wakeName))
          }
        }
      }
    }
  }

  /// Español: el de tu región si el Mac está en español; si no, el primero
  /// que funcione (mejor si reconoce sin internet).
  private func makeRecognizer() -> SFSpeechRecognizer? {
    var ids = ["es-MX", "es-US", "es-ES", "es-CO"]
    let current = Locale.current.identifier
    if current.hasPrefix("es") { ids.insert(current, at: 0) }
    let recognizers = ids.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
      .filter { $0.isAvailable }
    return recognizers.first { $0.supportsOnDeviceRecognition } ?? recognizers.first
  }

  private func begin(wake: String?) -> String? {
    cancel()
    guard let recognizer = makeRecognizer() else { return "unavailable" }
    // Escuchar siempre solo si no sale nada del Mac.
    if wake != nil && !recognizer.supportsOnDeviceRecognition { return "offline" }
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard format.channelCount > 0, format.sampleRate > 0 else { return "mic" }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if let name = wake {
      request.contextualStrings = [name, "oye \(name)", "hola \(name)", "hey \(name)"]
    }
    if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
    if #available(macOS 13, *) { request.addsPunctuation = true }

    input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }
    tapInstalled = true
    engine.prepare()
    do {
      try engine.start()
    } catch {
      stopAudio()
      return "mic"
    }

    session += 1
    let current = session
    woke = wake == nil
    self.recognizer = recognizer
    self.request = request
    task = recognizer.recognitionTask(with: request) { [weak self] res, error in
      DispatchQueue.main.async {
        guard let self = self, self.session == current else { return }
        if !self.woke {
          self.waitForName(res, error)
          return
        }
        if let res = res {
          let text = self.afterName(res.bestTranscription.formattedString)
          self.send(res.isFinal ? "done" : "partial", text)
          if res.isFinal { self.finish() }
        } else if error != nil {
          self.send("end", "")
          self.finish()
        }
      }
    }
    if wake != nil {
      // Cada cierto tiempo se empieza de nuevo (el reconocimiento no está
      // pensado para sesiones eternas).
      wakeTimer?.invalidate()
      wakeTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
        guard let self = self, self.session == current, !self.woke else { return }
        self.restartWake()
      }
    }
    return nil
  }

  // MARK: - Pausa con la pantalla bloqueada o apagada

  /// Con la pantalla bloqueada o dormida no escucha (nadie la va a llamar).
  private var paused = false

  private func watchScreen() {
    let ws = NSWorkspace.shared.notificationCenter
    let dc = DistributedNotificationCenter.default()
    for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
      ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.pause() }
    }
    for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
      ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.resume() }
    }
    dc.addObserver(
      forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
    ) { [weak self] _ in self?.pause() }
    dc.addObserver(
      forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
    ) { [weak self] _ in self?.resume() }
  }

  private func pause() {
    guard wakeName != nil, !woke, !paused else { return }
    paused = true
    SoundPlayer.log("wake: pausa (pantalla)")
    let name = wakeName
    cancel()
    wakeName = name
  }

  private func resume() {
    guard paused else { return }
    paused = false
    guard wakeName != nil, task == nil else { return }
    SoundPlayer.log("wake: sigue")
    restartWake()
  }

  // MARK: - «Oye <nombre>»

  private func fold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
  }

  /// Dónde termina «oye/hola/hey <nombre>» en [text], o nil.
  private func wakeRange(_ text: String) -> Range<String.Index>? {
    guard let name = wakeName else { return nil }
    let words = fold(name).split(separator: " ").map(String.init)
    guard !words.isEmpty else { return nil }
    let folded = fold(text)
    let pattern =
      "\\b(?:oye|hola|hey)\\W+(?:"
      + words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "\\W+")
      + ")\\b"
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.matches(
        in: folded, range: NSRange(folded.startIndex..., in: folded)
      ).last,
      let range = Range(match.range, in: folded)
    else { return nil }
    // fold no cambia el largo en español: la posición vale para el original.
    let end = text.index(
      text.startIndex,
      offsetBy: min(folded.distance(from: folded.startIndex, to: range.upperBound), text.count))
    return text.startIndex..<end
  }

  /// Lo dicho después del nombre (o todo, si no se esperaba nombre).
  private func afterName(_ text: String) -> String {
    guard wakeName != nil, let range = wakeRange(text) else { return text }
    return String(text[range.upperBound...])
      .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!¡?¿").union(.whitespaces))
  }

  private func waitForName(_ res: SFSpeechRecognitionResult?, _ error: Error?) {
    // No se despierta con su propia voz.
    if let res = res, !synth.isSpeaking,
      wakeRange(res.bestTranscription.formattedString) != nil
    {
      woke = true
      wakeTimer?.invalidate()
      SoundPlayer.log("wake: \(res.bestTranscription.formattedString.suffix(80))")
      NSSound(named: "Tink")?.play()
      send("wake", afterName(res.bestTranscription.formattedString))
      return
    }
    if res?.isFinal == true || error != nil { restartWake() }
  }

  private func restartWake() {
    guard wakeName != nil else { return }
    let name = wakeName
    cancel()
    wakeName = name
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
      guard let self = self, self.wakeName != nil, self.task == nil, !self.paused else { return }
      if let problem = self.begin(wake: self.wakeName) {
        self.wakeName = nil
        self.send("wakeError", problem)
      }
    }
  }

  private func stop() {
    stopAudio()
    request?.endAudio()
  }

  private func cancel() {
    wakeTimer?.invalidate()
    session += 1
    task?.cancel()
    finish()
  }

  private func stopAudio() {
    if engine.isRunning { engine.stop() }
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
  }

  private func finish() {
    stopAudio()
    request?.endAudio()
    request = nil
    task = nil
  }

  private func send(_ type: String, _ text: String) {
    sink?(["type": type, "text": text])
  }

  // MARK: - Hablar

  private func speak(_ text: String) {
    SoundPlayer.log("speak: \(text.prefix(60))")
    guard !text.isEmpty else { return }
    synth.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = bestVoice()
    synth.speak(utterance)
  }

  /// La mejor voz en español instalada (la mejorada si la hay), mejor si es
  /// de tu región.
  private func bestVoice() -> AVSpeechSynthesisVoice? {
    let region = Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
    let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("es") }
    func score(_ v: AVSpeechSynthesisVoice) -> Int {
      var s = v.quality == .default ? 0 : 2
      if region.hasPrefix("es"), v.language == region { s += 1 }
      return s
    }
    return voices.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "es-MX")
  }
}
