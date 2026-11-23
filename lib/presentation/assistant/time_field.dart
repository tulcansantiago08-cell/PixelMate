import '../../core/i18n/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../infrastructure/desktop/native_effects.dart';
import '../stats/stats_style.dart';

/// Elegir una hora: la hora en una lista (con a. m. / p. m., para no
/// confundirla con el formato de 24 horas) y los minutos escritos (00–59).
class TimeField extends StatefulWidget {
  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  /// Prefijo de las claves de prueba ("daily" → "daily-hour", "daily-minute").
  final String keyPrefix;

  const TimeField({
    super.key,
    required this.hour,
    required this.minute,
    required this.onChanged,
    this.keyPrefix = 'time',
  });

  @override
  State<TimeField> createState() => _TimeFieldState();
}

class _TimeFieldState extends State<TimeField> {
  late final _minutes =
      TextEditingController(text: widget.minute.toString().padLeft(2, '0'));

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  void _typed(String text) {
    // Vacío cuenta como «en punto» (lo que se guarda es lo que se ve).
    final m = text.isEmpty ? 0 : int.tryParse(text);
    if (m != null && m >= 0 && m <= 59) widget.onChanged(widget.hour, m);
  }

  @override
  Widget build(BuildContext context) {
    const label = TextStyle(color: StatsStyle.textSecondary, fontSize: 11);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(tr('Hora', 'Time'), style: label),
        const SizedBox(width: 8),
        DropdownButton<int>(
          key: ValueKey('${widget.keyPrefix}-hour'),
          value: widget.hour,
          dropdownColor: StatsStyle.surfaceRaised,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          menuMaxHeight: 240,
          items: [
            for (var h = 0; h < 24; h++)
              DropdownMenuItem(
                  value: h,
                  child: Text(
                      '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? tr('a. m.', 'AM') : tr('p. m.', 'PM')}')),
          ],
          onChanged: (v) {
            if (v != null) widget.onChanged(v, widget.minute);
          },
        ),
        const SizedBox(width: 8),
        const Text('min', style: label),
        const SizedBox(width: 6),
        SizedBox(
          width: 44,
          child: TextField(
            key: ValueKey('${widget.keyPrefix}-minute'),
            controller: _minutes,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 2,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              hintText: '00',
              hintStyle: TextStyle(color: Colors.white38),
            ),
            onChanged: _typed,
            onTap: () {
              focusApp();
              _minutes.selection = TextSelection(
                  baseOffset: 0, extentOffset: _minutes.text.length);
            },
          ),
        ),
      ],
    );
  }
}
