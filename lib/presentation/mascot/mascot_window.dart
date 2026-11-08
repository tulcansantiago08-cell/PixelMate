import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/desktop/mascot_window_port.dart';
import '../../application/workday/workday_controller.dart';
import '../../application/workday/workday_dialogue.dart';
import '../../application/workday/workday_providers.dart';
import '../../domain/mascot/mascot_state.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../chat/chat_bubble.dart';
import '../workday/workday_badge.dart';
import '../workday/workday_menu.dart';
import 'mascot_painter.dart';

class MascotWindow extends ConsumerStatefulWidget {
  const MascotWindow({super.key});

  @override
  ConsumerState<MascotWindow> createState() => _MascotWindowState();
}

class _MascotWindowState extends ConsumerState<MascotWindow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _showChat = false;
  bool _greeting = true;

  // Reacción temporal a un suceso de la jornada.
  String? _speech;
  MascotState? _reactionMood;
  Timer? _reactionTimer;
  StreamSubscription<dynamic>? _eventsSub;

  static const _reactionDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _greeting = false);
    });

    _eventsSub =
        ref.read(workdayControllerProvider.notifier).events.listen((event) {
      final reaction = reactionFor(event);
      if (reaction == null || !mounted) return;
      _reactionTimer?.cancel();
      setState(() {
        _speech = reaction.message;
        _reactionMood = reaction.mood;
      });
      _reactionTimer = Timer(_reactionDuration, () {
        if (mounted) {
          setState(() {
            _speech = null;
            _reactionMood = null;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _reactionTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleChat() async {
    final open = !_showChat;
    final window = ref.read(mascotWindowProvider);
    // Al abrir, primero se agranda la ventana; al cerrar, primero se oculta
    // el chat. Así nunca se dibuja el chat en una ventana pequeña.
    if (open) await window.setExpanded(true);
    if (!mounted) return;
    setState(() => _showChat = open);
    if (!open) await window.setExpanded(false);
  }

  MascotState _mascotState(WorkdayView view) {
    if (_showChat) return MascotState.chatting;
    if (_reactionMood != null) return _reactionMood!;
    if (_greeting) return MascotState.greeting;
    final status = view.status;
    if (status == null || status.state == WorkdayRunState.paused) {
      return MascotState.idle;
    }
    return switch (status.phase?.kind) {
      SessionPhase.focus => MascotState.working,
      SessionPhase.shortBreak || SessionPhase.longBreak => MascotState.resting,
      _ => MascotState.idle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(workdayControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        // Ancho completo para que la mascota quede pegada a la derecha.
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            // La mascota vive en la esquina inferior derecha de la ventana.
            crossAxisAlignment: CrossAxisAlignment.end,
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

              if (!_showChat)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: WorkdayBadge(view: view, speech: _speech),
                ),

              // Mascota fija abajo
              GestureDetector(
                onPanStart: (_) async => await windowManager.startDragging(),
                onTap: _toggleChat,
                onSecondaryTapDown: (details) => showWorkdayMenu(
                  context: context,
                  globalPosition: details.globalPosition,
                  controller: ref.read(workdayControllerProvider.notifier),
                  view: ref.read(workdayControllerProvider),
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: MascotPainter(
                      state: _mascotState(view),
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
      ),
    );
  }
}
