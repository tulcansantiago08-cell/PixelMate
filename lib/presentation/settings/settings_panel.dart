import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/activity/activity_providers.dart';
import '../../application/activity/focus_guard_controller.dart';
import '../../application/assistant/chat_controller.dart';
import '../../application/desktop/global_shortcut.dart';
import '../../application/desktop/login_item.dart';
import '../../application/desktop/sounds.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/accessory_providers.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/progress/progress_providers.dart';
import '../../domain/mascot/pet_kind.dart';
import '../mascot/rename_dialog.dart';
import '../stats/level_card.dart';
import '../stats/stats_style.dart';

/// Todas las opciones en un solo lugar.
class SettingsPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onShowWelcome;

  const SettingsPanel(
      {super.key, required this.onClose, required this.onShowWelcome});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  /// macOS pidió aprobar "abrir al iniciar sesión".
  bool _needsApproval = false;

  @override
  Widget build(BuildContext context) {
    final mascot = ref.watch(mascotSettingsProvider);
    final goal = ref.watch(dailyGoalSettingsProvider);
    final guard = ref.watch(focusGuardSettingsProvider);
    final detection = ref.watch(detectionSettingsProvider);
    final launch = ref.watch(launchAtLoginProvider);
    final level = ref.watch(progressProvider.select((p) => p.level));
    final equipped = ref.watch(equippedAccessoryProvider);
    final ai = ref.watch(assistantChoiceProvider).valueOrNull;
    final shortcut = ref.watch(shortcutSettingsProvider);
    final sound = ref.watch(soundSettingsProvider);

    return Container(
      decoration: BoxDecoration(
        color: StatsStyle.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StatsStyle.accent, width: 2),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child: Text('⚙️ Ajustes',
                  style: TextStyle(
                      color: StatsStyle.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Cerrar',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close,
                  size: 18, color: StatsStyle.textSecondary),
            ),
          ]),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                mascot,
                goal,
                guard,
                detection,
                launch,
                shortcut,
                sound,
              ]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.only(right: 4),
                children: [
                  const _Section('Mascota'),
                  _Row(
                    label: 'Nombre',
                    trailing: TextButton(
                      key: const ValueKey('settings-rename'),
                      onPressed: () async {
                        final typed =
                            await showRenameDialog(context, mascot.name);
                        if (typed != null) await mascot.setName(typed);
                      },
                      child: Text('${mascot.name} ✏️'),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 4),
                    child: Text('Especie',
                        style: TextStyle(
                            color: StatsStyle.textPrimary, fontSize: 12)),
                  ),
                  _SpeciesPicker(
                    level: level,
                    active: ref.watch(activeSpeciesProvider),
                    onChoose: mascot.setSpecies,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text('Accesorio',
                        style: TextStyle(
                            color: StatsStyle.textPrimary, fontSize: 12)),
                  ),
                  AccessoryPicker(
                    level: level,
                    equipped: equipped,
                    onEquip: mascot.setAccessory,
                  ),
                  _Switch(
                    keyName: 'walk',
                    label: 'Pasear por el escritorio',
                    value: mascot.walkEnabled,
                    onChanged: mascot.setWalkEnabled,
                  ),
                  const _Section('Enfoque'),
                  _Row(
                    label: 'Meta diaria',
                    trailing: PopupMenuButton<Duration>(
                      key: const ValueKey('settings-goal'),
                      tooltip: 'Cambiar la meta diaria',
                      initialValue: goal.goal,
                      onSelected: goal.setGoal,
                      color: StatsStyle.surfaceRaised,
                      itemBuilder: (_) => [
                        for (final o in DailyGoalSettings.options)
                          PopupMenuItem(
                            value: o,
                            height: 32,
                            child: Text(
                                o == Duration.zero
                                    ? 'Sin meta'
                                    : '${formatSpent(o)} al día',
                                style: const TextStyle(
                                    color: StatsStyle.textPrimary,
                                    fontSize: 12)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                            goal.enabled
                                ? '${formatSpent(goal.goal)} ▾'
                                : 'Sin meta ▾',
                            style: const TextStyle(
                                color: StatsStyle.textPrimary, fontSize: 12)),
                      ),
                    ),
                  ),
                  _Switch(
                    keyName: 'guard',
                    label: 'Guardián del enfoque',
                    help: 'Avisa si WhatsApp, Mensajes, juegos… siguen al '
                        'frente durante el enfoque.',
                    value: guard.enabled,
                    onChanged: guard.setEnabled,
                  ),
                  _Switch(
                    keyName: 'night',
                    label: 'Recordarme descansar de noche',
                    help: 'Desde las 22:00, si sigue una jornada.',
                    value: mascot.nightReminders,
                    onChanged: mascot.setNightReminders,
                  ),
                  _Switch(
                    keyName: 'detection',
                    label: 'Detectar apps y sugerir modo',
                    help: 'Al abrir tu editor o un juego, te propone '
                        'empezar una jornada.',
                    value: detection.enabled,
                    onChanged: detection.setEnabled,
                  ),
                  const _Section('Extras'),
                  _Switch(
                    keyName: 'shortcut',
                    label: 'Atajo $shortcutLabel para abrir el chat',
                    help: shortcut.enabled && !shortcut.working
                        ? '⚠️ Otra app ya usa $shortcutLabel.'
                        : 'Funciona desde cualquier app.',
                    value: shortcut.enabled,
                    onChanged: shortcut.setEnabled,
                  ),
                  _Switch(
                    keyName: 'sound',
                    label: 'Sonidos 8-bit',
                    help: 'Al empezar el enfoque, descansar, cumplir la '
                        'meta y subir de nivel.',
                    value: sound.enabled,
                    onChanged: sound.setEnabled,
                  ),
                  if (sound.enabled)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const ValueKey('settings-sound-test'),
                        onPressed: () =>
                            ref.read(soundPlayerProvider).play(PetSound.level),
                        child: const Text('▶️ Probar sonido'),
                      ),
                    ),
                  if (launch.supported) ...[
                    const _Section('Sistema'),
                    _Switch(
                      keyName: 'login',
                      label: 'Abrir al iniciar sesión',
                      value: launch.enabled,
                      onChanged: (v) async {
                        final ok = await launch.setEnabled(v);
                        if (mounted) setState(() => _needsApproval = !ok);
                      },
                    ),
                    if (_needsApproval)
                      const Text(launchAtLoginApprovalHint,
                          style: TextStyle(
                              color: StatsStyle.textSecondary, fontSize: 10)),
                  ],
                  const _Section('Inteligencia artificial'),
                  Text(
                    ai == null
                        ? 'Comprobando…'
                        : ai.assistant != null
                            ? (ai.assistant!.onDevice
                                ? '✅ ${ai.assistant!.label}: gratis, sin '
                                    'conexión y privada.'
                                : '✅ ${ai.assistant!.label} (usa tu API key).')
                            : '⚠️ ${ai.problem ?? 'Sin IA disponible.'}',
                    key: const ValueKey('settings-ai'),
                    style: const TextStyle(
                        color: StatsStyle.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const ValueKey('settings-welcome'),
                    onPressed: widget.onShowWelcome,
                    child: const Text('Ver la bienvenida otra vez'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(title.toUpperCase(),
            style: const TextStyle(
                color: StatsStyle.textMuted,
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600)),
      );
}

class _Row extends StatelessWidget {
  final String label;
  final Widget trailing;
  const _Row({required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(label,
              style:
                  const TextStyle(color: StatsStyle.textPrimary, fontSize: 12)),
        ),
        trailing,
      ]);
}

class _Switch extends StatelessWidget {
  final String keyName;
  final String label;
  final String? help;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Switch({
    required this.keyName,
    required this.label,
    this.help,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: StatsStyle.textPrimary, fontSize: 12)),
                if (help != null)
                  Text(help!,
                      style: const TextStyle(
                          color: StatsStyle.textMuted, fontSize: 10)),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.75,
            child: Switch(
              key: ValueKey('settings-$keyName'),
              value: value,
              activeTrackColor: StatsStyle.accent,
              onChanged: onChanged,
            ),
          ),
        ]),
      );
}

/// Elegir especie: las desbloqueadas se eligen con un toque; las demás
/// muestran el nivel que piden.
class _SpeciesPicker extends StatelessWidget {
  final int level;
  final PetKind active;
  final ValueChanged<PetKind> onChoose;

  const _SpeciesPicker(
      {required this.level, required this.active, required this.onChoose});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final k in PetKind.values)
            Tooltip(
              message: k.unlockedAt(level)
                  ? k.label
                  : '${k.label}: se desbloquea en el nivel ${k.unlockLevel}',
              child: Material(
                color: k == active ? StatsStyle.accent : StatsStyle.surface,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  key: ValueKey('species-${k.id}'),
                  borderRadius: BorderRadius.circular(6),
                  onTap: k.unlockedAt(level) ? () => onChoose(k) : null,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: k.unlockedAt(level)
                              ? StatsStyle.accent
                              : StatsStyle.grid),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(k.unlockedAt(level) ? k.emoji : '🔒',
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                          k.unlockedAt(level)
                              ? k.label
                              : '${k.label} · Nv. ${k.unlockLevel}',
                          style: TextStyle(
                              fontSize: 11,
                              color: k == active
                                  ? Colors.white
                                  : k.unlockedAt(level)
                                      ? StatsStyle.textPrimary
                                      : StatsStyle.textMuted)),
                    ]),
                  ),
                ),
              ),
            ),
        ],
      );
}
