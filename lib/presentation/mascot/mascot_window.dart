import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../domain/mascot/mascot_state.dart';
import '../chat/chat_bubble.dart';
import 'mascot_painter.dart';

class MascotWindow extends ConsumerStatefulWidget {
  const MascotWindow({super.key});

  @override
  ConsumerState<MascotWindow> createState() => _MascotWindowState();
}

class _MascotWindowState extends ConsumerState<MascotWindow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  MascotState _state = MascotState.greeting;
  bool _showChat = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _state = MascotState.idle);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleChat() {
    setState(() {
      _showChat = !_showChat;
      _state = _showChat ? MascotState.chatting : MascotState.idle;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Chat ocupa el espacio disponible arriba
            if (_showChat)
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: ChatBubble(),
                ),
              )
            else
              const Spacer(),

            // Mascota fija abajo
            GestureDetector(
              onPanStart: (_) async => await windowManager.startDragging(),
              onTap: _toggleChat,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => CustomPaint(
                  painter: MascotPainter(
                    state: _state,
                    animValue: _controller.value,
                  ),
                  size: const Size(160, 160),
                ),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
