import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/assistant/chat_controller.dart';
import '../../application/assistant/voice.dart';
import '../../application/mascot/mascot_settings.dart';

class ChatBubble extends ConsumerStatefulWidget {
  const ChatBubble({super.key});

  @override
  ConsumerState<ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends ConsumerState<ChatBubble> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    ref.read(chatProvider.notifier).prewarm();
    _voice = ref.read(voiceProvider.notifier);
  }

  @override
  void dispose() {
    // Al cerrar el chat: deja de escuchar (la respuesta hablada sigue).
    final voice = _voice;
    Future.microtask(voice.cancel);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  late final VoiceController _voice;

  void _send({bool withScreenshot = false}) {
    final text = _controller.text.trim();
    if (text.isEmpty && !withScreenshot) return;
    _controller.clear();
    ref.read(chatProvider.notifier).send(text, withScreenshot: withScreenshot);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);
    final assistant = ref.watch(assistantChoiceProvider).valueOrNull?.assistant;
    final voice = ref.watch(voiceProvider);

    // Auto-scroll al llegar nuevo mensaje
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C3AED), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF7C3AED),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                const Text('🐾', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  ref.watch(petNameProvider),
                  key: const ValueKey('pet-name'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                // Qué IA responde (la de Apple funciona sin conexión).
                Text(
                  assistant?.label ?? 'Sin IA',
                  key: const ValueKey('assistant-label'),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),

          // Mensajes
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final msg = messages[i];
                return Align(
                  alignment:
                      msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    constraints: const BoxConstraints(maxWidth: 210),
                    decoration: BoxDecoration(
                      color: msg.isUser
                          ? const Color(0xFF7C3AED)
                          : msg.isNote
                              ? const Color(0xFF1F3A2E) // acción realizada
                              : const Color(0xFF2d2d44),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.hasImage)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.screenshot,
                                    color: Colors.white70, size: 12),
                                SizedBox(width: 4),
                                Text('Pantalla capturada',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 10)),
                              ],
                            ),
                          ),
                        Text(
                          msg.text,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Por qué no se pudo escuchar.
          if (voice.problem != null && voice.status == VoiceStatus.idle)
            Padding(
              key: const ValueKey('voice-problem'),
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
              child: Text(voice.problem!,
                  style: const TextStyle(color: Colors.amber, fontSize: 10)),
            ),

          // Loading
          if (notifier.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                  SizedBox(width: 6),
                  Text('Pensando...',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),

          // Input
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Botón captura de pantalla (solo si la IA ve imágenes)
                if (assistant?.supportsImages ?? false) ...[
                  GestureDetector(
                    onTap: () => _send(withScreenshot: true),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2d2d44),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                const Color(0xFF7C3AED).withValues(alpha: 0.5)),
                      ),
                      child: const Icon(Icons.screenshot,
                          color: Colors.white70, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Input texto (o lo que va entendiendo mientras hablas)
                Expanded(
                  child: voice.listening
                      ? _Listening(heard: voice.heard)
                      : TextField(
                          controller: _controller,
                          autofocus:
                              true, // listo para escribir (también con ⌃⌥P)
                          onSubmitted: (_) => _send(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Pregúntame algo...',
                            hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 12),
                            filled: true,
                            fillColor: const Color(0xFF2d2d44),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 6),

                // Micrófono: hablarle (otra vez para terminar la frase).
                Tooltip(
                  message: voice.listening
                      ? 'Terminar'
                      : 'Hablarle (también con ⌃⌥V)',
                  child: GestureDetector(
                    key: const ValueKey('voice-button'),
                    onTap: _voice.toggle,
                    child: _MicButton(listening: voice.listening),
                  ),
                ),
                const SizedBox(width: 6),

                // Botón enviar
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.send, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que va entendiendo mientras hablas.
class _Listening extends StatelessWidget {
  final String heard;
  const _Listening({required this.heard});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('voice-listening'),
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: const Color(0xFF2d2d44),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF4F7B), width: 1),
      ),
      child: Text(
        heard.isEmpty ? 'Te escucho… habla 🎙️' : heard,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: heard.isEmpty ? Colors.white54 : Colors.white,
          fontSize: 12,
          fontStyle: heard.isEmpty ? FontStyle.italic : FontStyle.normal,
        ),
      ),
    );
  }
}

/// Botón del micrófono: late en rojo mientras escucha.
class _MicButton extends StatefulWidget {
  final bool listening;
  const _MicButton({required this.listening});

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.listening && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!widget.listening && _pulse.isAnimating) {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: widget.listening
              ? Color.lerp(const Color(0xFFE0245E), const Color(0xFFFF6B8F),
                  _pulse.value)
              : const Color(0xFF2d2d44),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: widget.listening
                  ? Colors.white70
                  : const Color(0xFF7C3AED).withValues(alpha: 0.5)),
        ),
        child: Icon(widget.listening ? Icons.stop_rounded : Icons.mic,
            color: Colors.white, size: 16),
      ),
    );
  }
}
