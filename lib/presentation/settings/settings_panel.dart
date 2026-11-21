import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/activity/activity_providers.dart';
import '../../application/activity/focus_guard_controller.dart';
import '../../application/assistant/alarm_settings.dart';
import '../../application/assistant/chat_controller.dart';
import '../../application/assistant/mac_actions.dart';
import '../../application/desktop/app_info.dart';
import '../../application/desktop/updates.dart';
import '../../application/desktop/global_shortcut.dart';
import '../../application/desktop/login_item.dart';
import '../../application/desktop/sounds.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/accessory_providers.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/progress/progress_providers.dart';
import '../../application/settings/backup.dart';
import '../../application/workday/focus_mode.dart';
import '../../domain/mascot/pet_accessory.dart';
import '../../domain/mascot/pet_kind.dart';
import '../mascot/rename_dialog.dart';
import '../common/plain_text.dart';
import '../stats/level_card.dart';
import '../stats/stats_style.dart';

part 'settings_controls.dart';
part 'settings_species.dart';
part 'settings_updates.dart';
part 'settings_alarms.dart';
part 'settings_focus_mode.dart';
part 'settings_backup.dart';

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
    final updates = ref.watch(updateSettingsProvider);
    final sound = ref.watch(soundSettingsProvider);

    return Container(
      decoration: StatsStyle.panel(),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Ajustes',
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
                updates,
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
                      child: _Editable(mascot.name),
                    ),
                  ),
                  _Row(
                    label: 'Cómo te llamo',
                    trailing: TextButton(
                      key: const ValueKey('settings-username'),
                      onPressed: () async {
                        final typed = await showRenameDialog(
                            context, mascot.userName ?? '',
                            title: '¿Cómo te llamo?',
                            hint: 'Tu nombre o apodo',
                            fieldKey: 'user-name');
                        if (typed != null) await mascot.setUserName(typed);
                      },
                      child: _Editable(mascot.userName ?? 'Dímelo'),
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
                    keyName: 'aura',
                    label: 'Aura brillante',
                    help: level >= auraUnlockLevel
                        ? 'Chispitas alrededor de ${mascot.name}.'
                        : '🔒 Se desbloquea en el nivel $auraUnlockLevel.',
                    value: level >= auraUnlockLevel && mascot.aura,
                    onChanged: level >= auraUnlockLevel ? mascot.setAura : null,
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
                    keyName: 'deepfocus',
                    label: 'Enfoque profundo',
                    help: 'Durante el enfoque, los festejos (nivel, logros, '
                        'racha) esperan al descanso.',
                    value: mascot.deepFocus,
                    onChanged: mascot.setDeepFocus,
                  ),
                  _Switch(
                    keyName: 'wellness',
                    label: 'Consejos de bienestar en los descansos',
                    help: 'Agua, estirarse, descansar la vista…',
                    value: mascot.wellnessTips,
                    onChanged: mascot.setWellnessTips,
                  ),
                  _Switch(
                    keyName: 'music',
                    label: 'Bailar con la música',
                    help: 'Cuando suena Spotify o Música, baila y dice la '
                        'canción (no durante el enfoque). Solo escucha el '
                        'aviso de cambio de canción.',
                    value: mascot.musicReactions,
                    onChanged: mascot.setMusicReactions,
                  ),
                  _Switch(
                    keyName: 'voice',
                    label: 'Responder en voz alta',
                    help:
                        'Cuando le hablas con el micrófono o $voiceShortcutLabel, '
                        'lee su respuesta con la voz del Mac.',
                    value: mascot.voiceReplies,
                    onChanged: mascot.setVoiceReplies,
                  ),
                  _Switch(
                    keyName: 'wake',
                    label: 'Despertarla con «Oye ${mascot.name}»',
                    help: 'Di «oye ${mascot.name}» o «hola ${mascot.name}» y '
                        'te escucha. Entiende la voz en tu Mac, sin internet; '
                        'mientras está activo verás el punto naranja del '
                        'micrófono.',
                    value: mascot.wakeWord,
                    onChanged: mascot.setWakeWord,
                  ),
                  _Switch(
                    keyName: 'wakestrict',
                    label: 'Modo estricto',
                    help: 'Solo despierta con «Oye ${mascot.name}» al empezar '
                        'a hablar (no con «hola» ni en medio de una frase): '
                        'menos falsas alarmas.',
                    value: mascot.wakeStrict,
                    onChanged: mascot.wakeWord ? mascot.setWakeStrict : null,
                  ),
                  _Switch(
                    keyName: 'briefing',
                    label: 'Resumen del día',
                    help: 'Por la mañana te cuenta lo que tienes hoy: '
                        'calendario, tareas diarias y recordatorios.',
                    value: mascot.morningBriefing,
                    onChanged: mascot.setMorningBriefing,
                  ),
                  const _AlarmOptions(),
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
                    label: 'Atajos $shortcutLabel (chat) y '
                        '$voiceShortcutLabel (hablarle)',
                    help: shortcut.enabled && !shortcut.working
                        ? '⚠️ Otra app ya usa $shortcutLabel.'
                        : 'Funcionan desde cualquier app.',
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
                  PlainText(
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
                  const _Section('Modo Concentración'),
                  const _FocusModeOptions(),
                  const _Section('Copia de seguridad'),
                  const _BackupButtons(),
                  const _Section('Acerca de'),
                  Text(
                    'PixelMate '
                    '${ref.watch(appVersionProvider).valueOrNull ?? ''}',
                    key: const ValueKey('settings-version'),
                    style: const TextStyle(
                        color: StatsStyle.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  const Text(
                    'Tu compañero pixel art para enfocarte, descansar y '
                    'jugar. Tus datos se quedan en este Mac.',
                    style: TextStyle(
                        color: StatsStyle.textSecondary, fontSize: 11),
                  ),
                  _UpdateRow(
                    state: ref.watch(updateProvider),
                    onCheck: () =>
                        ref.read(updateProvider.notifier).check(manual: true),
                    onDownload: (url) =>
                        ref.read(macActionsProvider).openUrl(url),
                  ),
                  _Switch(
                    keyName: 'updates',
                    label: 'Buscar actualizaciones solo',
                    help: 'Una vez al día pregunta a GitHub por la última '
                        'versión (no envía datos tuyos).',
                    value: updates.enabled,
                    onChanged: updates.setEnabled,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('settings-github'),
                      onPressed: () =>
                          ref.read(appInfoProvider).openRepository(),
                      child: const Text('Ver el proyecto en GitHub ↗'),
                    ),
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
