import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/assistant/chat_controller.dart';
import '../../application/desktop/login_item.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/mascot_settings.dart';
import '../stats/stats_style.dart';

/// Bienvenida de la primera vez: nombre, meta, arranque y cómo usarla.
class WelcomePanel extends ConsumerStatefulWidget {
  /// Se llama al terminar o al saltarla.
  final VoidCallback onDone;

  const WelcomePanel({super.key, required this.onDone});

  @override
  ConsumerState<WelcomePanel> createState() => _WelcomePanelState();
}

class _WelcomePanelState extends ConsumerState<WelcomePanel> {
  static const _steps = 4;

  /// Botones pequeños: el panel mide unos 300 px de ancho.
  static const _compact = ButtonStyle(
    padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
    minimumSize: WidgetStatePropertyAll(Size(0, 32)),
    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    visualDensity: VisualDensity.compact,
  );
  int _step = 0;
  late final _name =
      TextEditingController(text: ref.read(mascotSettingsProvider).name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_step == 0) await ref.read(mascotSettingsProvider).setName(_name.text);
    if (_step == _steps - 1) {
      widget.onDone();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(petNameProvider);
    return Container(
      decoration: StatsStyle.panel(),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: switch (_step) {
                0 => _nameStep(),
                1 => _goalStep(name),
                2 => _startupStep(),
                _ => _tipsStep(name),
              },
            ),
          ),
          Row(children: [
            for (var i = 0; i < _steps; i++)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == _step ? StatsStyle.accent : StatsStyle.grid,
                ),
              ),
            const Spacer(),
            if (_step < _steps - 1)
              TextButton(
                key: const ValueKey('welcome-skip'),
                onPressed: widget.onDone,
                style: _compact,
                child: const Text('Saltar',
                    style: TextStyle(color: StatsStyle.textMuted)),
              ),
            const SizedBox(width: 4),
            FilledButton(
              key: const ValueKey('welcome-next'),
              onPressed: _next,
              style: _compact,
              child: Text(_step == _steps - 1 ? '¡Empecemos!' : 'Siguiente'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                color: StatsStyle.textPrimary,
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w600)),
      );

  /// Una línea con ícono, para las explicaciones.
  Widget _tip(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: StatsStyle.card(radius: 8),
            child: Icon(icon, size: 15, color: StatsStyle.accentLight),
          ),
          const SizedBox(width: 8),
          Expanded(child: _body(text)),
        ]),
      );

  Widget _body(String text) => Text(text,
      style: const TextStyle(color: StatsStyle.textSecondary, fontSize: 12));

  Widget _nameStep() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('¡Hola!'),
          _body('Soy tu nueva mascota. Vivo en tu escritorio y te acompaño '
              'mientras trabajas, estudias o juegas.\n\n¿Cómo quieres '
              'llamarme?'),
          TextField(
            key: const ValueKey('welcome-name'),
            controller: _name,
            maxLength: MascotSettings.maxNameLength,
            style: const TextStyle(color: StatsStyle.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Michi, Luna, Nube…',
              hintStyle: TextStyle(color: StatsStyle.textMuted),
              counterStyle: TextStyle(color: StatsStyle.textMuted),
            ),
            onSubmitted: (_) => _next(),
          ),
        ],
      );

  Widget _goalStep(String name) {
    final goal = ref.watch(dailyGoalSettingsProvider);
    return ListenableBuilder(
      listenable: goal,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Encantado, soy $name'),
          _body('¿Cuánto quieres enfocarte al día? Te aviso cuando lo '
              'cumplas. Puedes cambiarlo cuando quieras.'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in DailyGoalSettings.options)
                ChoiceChip(
                  key: ValueKey('welcome-goal-${o.inHours}'),
                  label:
                      Text(o == Duration.zero ? 'Sin meta' : '${o.inHours} h'),
                  selected: goal.goal == o,
                  selectedColor: StatsStyle.accent,
                  labelStyle: TextStyle(
                      fontSize: 12,
                      color: goal.goal == o
                          ? Colors.white
                          : StatsStyle.textSecondary),
                  backgroundColor: StatsStyle.surfaceRaised,
                  showCheckmark: false,
                  onSelected: (_) => goal.setGoal(o),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _startupStep() {
    final launch = ref.watch(launchAtLoginProvider);
    final ai = ref.watch(assistantChoiceProvider).valueOrNull;
    final assistant = ai?.assistant;
    return ListenableBuilder(
      listenable: launch,
      builder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Siempre a tu lado'),
          if (launch.supported) ...[
            Row(children: [
              Expanded(child: _body('Abrir PixelMate al encender tu Mac')),
              Switch(
                key: const ValueKey('welcome-login'),
                value: launch.enabled,
                activeTrackColor: StatsStyle.accent,
                onChanged: launch.setEnabled,
              ),
            ]),
            const SizedBox(height: 8),
          ],
          _body(assistant == null
              ? (ai == null
                  ? 'Comprobando la IA…'
                  : 'Para charlar conmigo: ${ai.problem ?? ''}')
              : assistant.onDevice
                  ? 'Puedo charlar contigo gratis y sin internet, con la '
                      'IA de tu Mac. Pregúntame cuánto te falta o pídeme '
                      'que empiece una jornada.'
                  : 'Charlamos con ${assistant.label}.'),
        ],
      ),
    );
  }

  Widget _tipsStep(String name) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('¡Listo! Así me usas'),
          _tip(Icons.chat_bubble_outline_rounded,
              'Haz clic en mí para charlar.'),
          _tip(Icons.bar_chart_rounded, 'Tus estadísticas, nivel y logros.'),
          _tip(Icons.more_horiz_rounded, 'Jornadas, pausa, paseo y mi nombre.'),
          _tip(Icons.open_with_rounded, 'Arrástrame a donde quieras.'),
          _tip(Icons.settings_outlined,
              'Todo lo demás en Ajustes (barra de menú).'),
          const SizedBox(height: 6),
          _body('Cuando abras tu editor o un juego, $name te propondrá '
              'empezar.'),
        ],
      );
}
