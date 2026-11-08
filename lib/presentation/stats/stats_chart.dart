import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/stats/activity_stats.dart';
import 'stats_style.dart';

/// Barras apiladas por día: tiempo de enfoque por modo.
///
/// Marcas finas (máx. 24 px), extremo superior redondeado de 4 px y base
/// recta, 2 px de separación entre segmentos, rejilla discreta y tooltip al
/// pasar el ratón por cada día.
class StatsDayChart extends StatelessWidget {
  final List<DayBucket> days;
  final double height;

  const StatsDayChart({super.key, required this.days, this.height = 96});

  static const _gap = 2.0;
  static const _maxBar = 24.0;

  @override
  Widget build(BuildContext context) {
    final maxTotal =
        days.fold<Duration>(Duration.zero, (m, d) => d.total > m ? d.total : m);
    // Escala redondeada a la hora (mínimo 1 h) para que la referencia sea legible.
    final scaleHours = math.max(1, (maxTotal.inMinutes / 60).ceil());
    final scale = Duration(hours: scaleHours);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('máx. $scaleHours h por día',
            style: const TextStyle(color: StatsStyle.textMuted, fontSize: 10)),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: LayoutBuilder(builder: (context, c) {
            final slot = c.maxWidth / days.length;
            final barWidth = math.min(_maxBar, math.max(3.0, slot - _gap));
            return Stack(children: [
              // Rejilla: base y mitad, recesivas.
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 1, color: StatsStyle.grid)),
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: height / 2,
                  child: Container(
                      height: 1,
                      color: StatsStyle.grid.withValues(alpha: 0.5))),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in days)
                    SizedBox(
                      width: slot,
                      child: Tooltip(
                        message: _tooltip(day),
                        waitDuration: const Duration(milliseconds: 150),
                        child: Container(
                          // Zona de toque más grande que la barra.
                          height: height,
                          color: Colors.transparent,
                          alignment: Alignment.bottomCenter,
                          child: _StackedBar(
                            day: day,
                            width: barWidth,
                            maxHeight: height,
                            scale: scale,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ]);
          }),
        ),
        const SizedBox(height: 4),
        Row(children: [
          for (final (i, day) in days.indexed)
            Expanded(
              child: Text(
                _axisLabel(day.day, i),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: StatsStyle.textMuted, fontSize: 10),
              ),
            ),
        ]),
      ],
    );
  }

  String _axisLabel(DateTime d, int i) {
    if (days.length <= 7) return weekdayInitial(d);
    // Mes: solo algunos días para que no se amontonen.
    return (d.day == 1 || d.day % 7 == 1) ? '${d.day}' : '';
  }

  static String _tooltip(DayBucket day) {
    final lines = [longDate(day.day)];
    if (day.total == Duration.zero) {
      lines.add('Sin sesiones');
    } else {
      for (final mode in trackedModes) {
        final d = day.focusByMode[mode];
        if (d != null && d > Duration.zero) {
          lines.add('${StatsStyle.modeLabel(mode)}: ${formatSpent(d)}');
        }
      }
    }
    return lines.join('\n');
  }
}

class _StackedBar extends StatelessWidget {
  final DayBucket day;
  final double width;
  final double maxHeight;
  final Duration scale;

  const _StackedBar({
    required this.day,
    required this.width,
    required this.maxHeight,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final segments = [
      for (final mode in trackedModes)
        if ((day.focusByMode[mode] ?? Duration.zero) > Duration.zero)
          (mode, day.focusByMode[mode]!)
    ];
    if (segments.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    // Las separaciones entre colores también ocupan alto: se descuentan
    // para que la barra del día más largo no se salga del gráfico.
    final available = maxHeight - StatsDayChart._gap * (segments.length - 1);
    // Orden fijo de abajo arriba: trabajo, estudio, juego.
    for (final (i, (mode, d)) in segments.reversed.indexed) {
      final isTop = i == 0;
      final h = math.max(2.0, available * d.inSeconds / scale.inSeconds);
      if (!isTop) children.add(const SizedBox(height: StatsDayChart._gap));
      children.add(Container(
        width: width,
        height: h,
        decoration: BoxDecoration(
          color: StatsStyle.modeColor(mode),
          borderRadius: isTop
              ? const BorderRadius.vertical(top: Radius.circular(4))
              : BorderRadius.zero,
        ),
      ));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
