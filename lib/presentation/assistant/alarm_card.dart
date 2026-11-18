import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/alarm.dart';
import '../../application/assistant/daily_tasks.dart';

/// Tarjeta de la alarma que suena: la hora, qué toca y los botones para
/// posponerla o apagarla. La campana se mueve mientras suena.
class AlarmCard extends ConsumerStatefulWidget {
  const AlarmCard({super.key});

  @override
  ConsumerState<AlarmCard> createState() => _AlarmCardState();
}

class _AlarmCardState extends ConsumerState<AlarmCard>
    with SingleTickerProviderStateMixin {
  late final _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600))
    ..repeat();

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  String _hm(DateTime t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final alarm = ref.watch(alarmProvider);
    final controller = ref.read(alarmProvider.notifier);
    final first = alarm.ringing.isEmpty ? null : alarm.ringing.first;
    // Las de tareas diarias se pueden dar por hechas desde aquí.
    final daily = [
      for (final r in alarm.ringing)
        if (r.id.startsWith(DailyTaskStore.alarmPrefix))
          r.id.substring(DailyTaskStore.alarmPrefix.length)
    ];
    return Container(
      key: const ValueKey('alarm-card'),
      width: 236,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE0245E), Color(0xFFFF8A3D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white70, width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x66E0245E), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _shake,
                builder: (_, child) => Transform.rotate(
                  angle: sin(_shake.value * 2 * pi * 2) * 0.35,
                  child: child,
                ),
                child: const Text('⏰', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 8),
              Text(
                first == null ? '' : _hm(first.due),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            alarm.text,
            key: const ValueKey('alarm-text'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('alarm-snooze'),
                  onPressed: () => controller.snooze(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  child: const Text('😴 5 min', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('alarm-stop'),
                  onPressed: () async {
                    final store = ref.read(dailyTaskStoreProvider);
                    final now = DateTime.now();
                    for (final id in daily) {
                      await store.setDone(id, true, now);
                    }
                    await controller.stop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE0245E),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  child: Text(daily.isEmpty ? 'Apagar' : '✅ Hecha',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
