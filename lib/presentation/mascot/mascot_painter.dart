import 'package:flutter/material.dart';
import '../../domain/mascot/mascot_state.dart';

/// Mascota estilo pixel art — cada "píxel" es un cuadrado de [px] puntos.
class MascotPainter extends CustomPainter {
  final MascotState state;
  final double animValue;

  const MascotPainter({required this.state, required this.animValue});

  static const double px = 7.0; // tamaño de cada píxel

  @override
  void paint(Canvas canvas, Size size) {
    // Bob vertical suave
    final dy = (animValue * 4 - 2);
    canvas.save();
    canvas.translate(0, dy);
    _drawSprite(canvas, state);
    canvas.restore();
  }

  void _drawSprite(Canvas canvas, MascotState state) {
    // Sprite grid 18×22 — origen en (1*px, 1*px) para margen
    // Colores
    const C = Color(0xFF000000); // contorno
    const W = Color(0xFFFFFFFF); // blanco
    const T = Color(0x00000000); // transparente

    // Colores del cuerpo según estado
    final Color B; // cuerpo principal
    final Color S; // sombreado
    final Color E; // ojos
    switch (state) {
      case MascotState.sleeping:
      case MascotState.tired:
        B = const Color(0xFF6a9fd8);
        S = const Color(0xFF4a7fb8);
        E = const Color(0xFF2a4a70);
        break;
      case MascotState.celebrating:
        B = const Color(0xFFb87ae8);
        S = const Color(0xFF8a50c0);
        E = const Color(0xFF4a1a80);
        break;
      case MascotState.alert:
        B = const Color(0xFFe8907a);
        S = const Color(0xFFc06050);
        E = const Color(0xFF803020);
        break;
      case MascotState.gaming:
        B = const Color(0xFF5ac87a);
        S = const Color(0xFF30a050);
        E = const Color(0xFF105030);
        break;
      case MascotState.working:
      case MascotState.studying:
        B = const Color(0xFFe8c060);
        S = const Color(0xFFc09030);
        E = const Color(0xFF604010);
        break;
      default:
        B = const Color(0xFFf0d090);
        S = const Color(0xFFc8a060);
        E = const Color(0xFF604020);
    }

    const P = Color(0xFFff9ab0); // mejillas / nariz rosa
    const H = Color(0xFF1a1a1a); // audífonos / accesorios

    // Sprite 18 columnas × 22 filas (0-indexed)
    // Cada fila es una lista de colores
    final grid = _buildGrid(B, S, C, W, T, P, E, H, state);
    _drawGrid(canvas, grid);
  }

  List<List<Color>> _buildGrid(
    Color B, Color S, Color C, Color W, Color T,
    Color P, Color E, Color H, MascotState state,
  ) {
    // Ojos según estado
    final eyeL = _eyeLeft(state, C, W, E, B);
    final eyeR = _eyeRight(state, C, W, E, B);

    // Boca según estado
    final mouthRow = _mouthRow(state, C, B, P);

    return [
      // fila 0 — orejas
      [T,T,T,C,C,T,T,T,T,T,T,T,T,C,C,T,T,T],
      // fila 1 — orejas interior
      [T,T,C,B,B,C,T,T,T,T,T,T,C,B,B,C,T,T],
      // fila 2 — orejas interior
      [T,T,C,S,B,C,T,T,T,T,T,T,C,B,S,C,T,T],
      // fila 3 — tope cabeza
      [T,T,C,C,C,C,C,C,C,C,C,C,C,C,C,C,T,T],
      // fila 4 — cabeza
      [T,C,B,B,B,B,B,B,B,B,B,B,B,B,B,B,C,T],
      // fila 5 — cabeza con audífonos
      [C,H,B,B,B,B,B,B,B,B,B,B,B,B,B,B,H,C],
      // fila 6 — ojos
      eyeL,
      // fila 7 — ojos brillo
      eyeR,
      // fila 8 — nariz
      [C,H,B,B,B,B,B,B,P,B,B,B,B,B,B,B,H,C],
      // fila 9 — mejillas + boca
      mouthRow,
      // fila 10 — mejillas
      [C,H,B,P,B,B,B,B,B,B,B,B,B,B,P,B,H,C],
      // fila 11 — barbilla
      [T,C,B,B,B,B,B,B,B,B,B,B,B,B,B,B,C,T],
      // fila 12 — cuello / inicio cuerpo
      [T,T,C,C,B,B,B,B,B,B,B,B,B,B,C,C,T,T],
      // fila 13 — cuerpo
      [T,C,B,B,B,B,B,B,B,B,B,B,B,B,B,B,C,T],
      // fila 14 — cuerpo
      [C,B,B,B,S,B,B,B,B,B,B,B,B,S,B,B,B,C],
      // fila 15 — cuerpo
      [C,B,B,S,S,B,B,B,B,B,B,B,B,S,S,B,B,C],
      // fila 16 — cuerpo
      [C,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,B,C],
      // fila 17 — inicio pies
      [T,C,B,B,B,B,B,B,B,B,B,B,B,B,B,B,C,T],
      // fila 18 — pies
      [T,T,C,B,B,C,T,T,T,T,T,T,T,C,B,B,C,T],
      // fila 19 — pies
      [T,T,C,B,S,C,T,T,T,T,T,T,T,C,S,B,C,T],
      // fila 20 — suela
      [T,T,C,C,C,C,T,T,T,T,T,T,T,C,C,C,C,T],
      // fila 21 — sombra
      [T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T,T],
    ];
  }

  List<Color> _eyeLeft(MascotState state, Color C, Color W, Color E, Color B) {
    const H = Color(0xFF1a1a1a);
    switch (state) {
      case MascotState.sleeping:
      case MascotState.tired:
        return [C,H,B,B,B,B,B,B,B,B,B,B,B,B,B,B,H,C];
      case MascotState.celebrating:
        return [C,H,B,W,C,B,B,B,B,B,B,B,B,C,W,B,H,C];
      case MascotState.alert:
        return [C,H,B,W,W,C,B,B,B,B,B,C,W,W,B,B,H,C];
      default:
        return [C,H,B,W,W,C,B,B,B,B,B,C,W,W,B,B,H,C];
    }
  }

  List<Color> _eyeRight(MascotState state, Color C, Color W, Color E, Color B) {
    const H = Color(0xFF1a1a1a);
    final T = const Color(0x00000000);
    switch (state) {
      case MascotState.sleeping:
      case MascotState.tired:
        // línea de ojos cerrados
        return [C,H,B,C,C,B,B,B,B,B,B,B,B,C,C,B,H,C];
      case MascotState.celebrating:
        // ojos estrella (★)
        return [C,H,B,C,E,C,B,B,B,B,B,C,E,C,B,B,H,C];
      case MascotState.alert:
        // ojos muy abiertos
        return [C,H,B,W,E,W,B,B,B,B,B,W,E,W,B,B,H,C];
      default:
        // ojos normales con brillo
        return [C,H,B,E,E,W,B,B,B,B,B,W,E,E,B,B,H,C];
    }
  }

  List<Color> _mouthRow(MascotState state, Color C, Color B, Color P) {
    const H = Color(0xFF1a1a1a);
    const D = Color(0xFF5a3010); // marrón oscuro boca
    switch (state) {
      case MascotState.sleeping:
        return [C,H,B,B,B,B,B,D,B,B,D,B,B,B,B,B,H,C];
      case MascotState.celebrating:
        return [C,H,B,B,B,D,D,D,D,D,D,D,D,B,B,B,H,C];
      case MascotState.alert:
        return [C,H,B,B,B,B,B,P,P,P,B,B,B,B,B,B,H,C];
      default:
        return [C,H,B,B,B,B,D,B,B,B,B,D,B,B,B,B,H,C];
    }
  }

  void _drawGrid(Canvas canvas, List<List<Color>> grid) {
    final paint = Paint()..isAntiAlias = false;
    // Centrar horizontalmente
    const offsetX = 1.0 * px;
    const offsetY = 2.0 * px;

    for (int row = 0; row < grid.length; row++) {
      final cols = grid[row];
      for (int col = 0; col < cols.length; col++) {
        final color = cols[col];
        if (color.alpha == 0) continue;
        paint.color = color;
        canvas.drawRect(
          Rect.fromLTWH(
            offsetX + col * px,
            offsetY + row * px,
            px,
            px,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      old.state != state || old.animValue != animValue;
}
