import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/mascot/mascot_state.dart';
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Después de saludar, pasar a idle
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _state = MascotState.idle);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => setState(() => _state = MascotState.chatting),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: MascotPainter(
                state: _state,
                animValue: _controller.value,
              ),
              size: const Size(160, 200),
            );
          },
        ),
      ),
    );
  }
}
