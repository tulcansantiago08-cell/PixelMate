import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/assistant/chat_controller.dart';
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
  }

  @override
  void dispose() {
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

    // Auto-scroll al llegar nuevo mensaje
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF7C3AED), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C3AED).withOpacity(0.25),
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
                            color: const Color(0xFF7C3AED).withOpacity(0.5)),
                      ),
                      child: const Icon(Icons.screenshot,
                          color: Colors.white70, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],

                // Input texto
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Pregúntame algo...',
                      hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.35), fontSize: 12),
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
