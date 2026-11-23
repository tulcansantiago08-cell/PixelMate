import '../../core/i18n/language.dart';
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
    final language = ref.watch(languageSettingsProvider);

    return Container(
      decoration: StatsStyle.panel(),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(tr('Ajustes', 'Settings'),
                  style: TextStyle(
                      color: StatsStyle.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: tr('Cerrar', 'Close'),
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
                  _Section(tr('Mascota', 'Pet')),
                  _Row(
                    label: tr('Nombre', 'Name'),
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
                    label: tr('Cómo te llamo', 'What I call you'),
                    trailing: TextButton(
                      key: const ValueKey('settings-username'),
                      onPressed: () async {
                        final typed = await showRenameDialog(
                            context, mascot.userName ?? '',
                            title: tr('¿Cómo te llamo?', 'What should I call you?'),
                            hint: tr('Tu nombre o apodo', 'Your name or nickname'),
                            fieldKey: 'user-name');
                        if (typed != null) await mascot.setUserName(typed);
                      },
                      child: _Editable(mascot.userName ?? tr('Dímelo', 'Tell me')),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(tr('Especie', 'Species'),
                        style: TextStyle(
                            color: StatsStyle.textPrimary, fontSize: 12)),
                  ),
                  _SpeciesPicker(
                    level: level,
                    active: ref.watch(activeSpeciesProvider),
                    onChoose: mascot.setSpecies,
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(tr('Accesorio', 'Accessory'),
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
                    label: tr('Aura brillante', 'Shiny aura'),
                    help: level >= auraUnlockLevel
                        ? tr('Chispitas alrededor de ${mascot.name}.', 'Sparkles around ${mascot.name}.')
                        : tr('🔒 Se desbloquea en el nivel $auraUnlockLevel.', '🔒 Unlocks at level $auraUnlockLevel.'),
                    value: level >= auraUnlockLevel && mascot.aura,
                    onChanged: level >= auraUnlockLevel ? mascot.setAura : null,
                  ),
                  _Switch(
                    keyName: 'walk',
                    label: tr('Pasear por el escritorio', 'Walk around the desktop'),
                    value: mascot.walkEnabled,
                    onChanged: mascot.setWalkEnabled,
                  ),
                  _Section(tr('Enfoque', 'Focus')),
                  _Row(
                    label: tr('Meta diaria', 'Daily goal'),
                    trailing: PopupMenuButton<Duration>(
                      key: const ValueKey('settings-goal'),
                      tooltip: tr('Cambiar la meta diaria', 'Change the daily goal'),
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
                                    ? tr('Sin meta', 'No goal')
                                    : tr('${formatSpent(o)} al día', '${formatSpent(o)} a day'),
                                style: const TextStyle(
                                    color: StatsStyle.textPrimary,
                                    fontSize: 12)),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                            goal.enabled
                                ? tr('${formatSpent(goal.goal)} ▾', '${formatSpent(goal.goal)} ▾')
                                : tr('Sin meta ▾', 'No goal ▾'),
                            style: const TextStyle(
                                color: StatsStyle.textPrimary, fontSize: 12)),
                      ),
                    ),
                  ),
                  _Switch(
                    keyName: 'guard',
                    label: tr('Guardián del enfoque', 'Focus guard'),
                    help: tr('Avisa si WhatsApp, Mensajes, juegos… siguen al frente durante el enfoque.', 'Warns you if WhatsApp, Messages, games… stay in front during focus.'),
                    value: guard.enabled,
                    onChanged: guard.setEnabled,
                  ),
                  _Switch(
                    keyName: 'deepfocus',
                    label: tr('Enfoque profundo', 'Deep focus'),
                    help: tr('Durante el enfoque, los festejos (nivel, logros, racha) esperan al descanso.', 'During focus, celebrations (level, achievements, streak) wait for the break.'),
                    value: mascot.deepFocus,
                    onChanged: mascot.setDeepFocus,
                  ),
                  _Switch(
                    keyName: 'wellness',
                    label: tr('Consejos de bienestar en los descansos', 'Wellbeing tips during breaks'),
                    help: tr('Agua, estirarse, descansar la vista…', 'Water, stretching, resting your eyes…'),
                    value: mascot.wellnessTips,
                    onChanged: mascot.setWellnessTips,
                  ),
                  _Switch(
                    keyName: 'music',
                    label: tr('Bailar con la música', 'Dance to the music'),
                    help: tr('Cuando suena Spotify o Música, baila y dice la canción (no durante el enfoque). Solo escucha el aviso de cambio de canción.', 'When Spotify or Music is playing, it dances and says the song (not during focus). It only listens for the song-change notice.'),
                    value: mascot.musicReactions,
                    onChanged: mascot.setMusicReactions,
                  ),
                  _Switch(
                    keyName: 'voice',
                    label: tr('Responder en voz alta', 'Answer out loud'),
                    help:
                        tr('Cuando le hablas con el micrófono o $voiceShortcutLabel, lee su respuesta con la voz del Mac.', "When you talk to it with the microphone or $voiceShortcutLabel, it reads its answer with the Mac's voice."),
                    value: mascot.voiceReplies,
                    onChanged: mascot.setVoiceReplies,
                  ),
                  _Switch(
                    keyName: 'wake',
                    label: tr('Despertarla con «Oye ${mascot.name}»', 'Wake it with “Hey ${mascot.name}”'),
                    help: tr('Di «oye ${mascot.name}» o «hola ${mascot.name}» y te escucha. Entiende la voz en tu Mac, sin internet; mientras está activo verás el punto naranja del micrófono.', "Say “hey ${mascot.name}” or “hi ${mascot.name}” and it listens. It understands speech on your Mac, without internet; while it's on you'll see the orange microphone dot."),
                    value: mascot.wakeWord,
                    onChanged: mascot.setWakeWord,
                  ),
                  _Switch(
                    keyName: 'wakestrict',
                    label: tr('Modo estricto', 'Strict mode'),
                    help: tr('Solo despierta con «Oye ${mascot.name}» al empezar a hablar (no con «hola» ni en medio de una frase): menos falsas alarmas.', 'It only wakes with “Hey ${mascot.name}” at the start of what you say (not with “hi” or mid-sentence): fewer false alarms.'),
                    value: mascot.wakeStrict,
                    onChanged: mascot.wakeWord ? mascot.setWakeStrict : null,
                  ),
                  _Switch(
                    keyName: 'briefing',
                    label: tr('Resumen del día', 'Daily summary'),
                    help: tr('Por la mañana te cuenta lo que tienes hoy: calendario, tareas diarias y recordatorios.', 'In the morning it tells you what you have today: calendar, daily tasks and reminders.'),
                    value: mascot.morningBriefing,
                    onChanged: mascot.setMorningBriefing,
                  ),
                  const _AlarmOptions(),
                  _Switch(
                    keyName: 'night',
                    label: tr('Recordarme descansar de noche', 'Remind me to rest at night'),
                    help: tr('Desde las 22:00, si sigue una jornada.', 'From 22:00, if a workday is still running.'),
                    value: mascot.nightReminders,
                    onChanged: mascot.setNightReminders,
                  ),
                  _Switch(
                    keyName: 'detection',
                    label: tr('Detectar apps y sugerir modo', 'Detect apps and suggest a mode'),
                    help: tr('Al abrir tu editor o un juego, te propone empezar una jornada.', 'When you open your editor or a game, it suggests starting a workday.'),
                    value: detection.enabled,
                    onChanged: detection.setEnabled,
                  ),
                  _Section(tr('Extras', 'Extras')),
                  _Switch(
                    keyName: 'shortcut',
                    label: tr('Atajos $shortcutLabel (chat) y $voiceShortcutLabel (hablarle)', 'Shortcuts $shortcutLabel (chat) and $voiceShortcutLabel (talk to it)'),
                    help: shortcut.enabled && !shortcut.working
                        ? tr('⚠️ Otra app ya usa $shortcutLabel.', '⚠️ Another app already uses $shortcutLabel.')
                        : tr('Funcionan desde cualquier app.', 'They work from any app.'),
                    value: shortcut.enabled,
                    onChanged: shortcut.setEnabled,
                  ),
                  _Switch(
                    keyName: 'sound',
                    label: tr('Sonidos 8-bit', '8-bit sounds'),
                    help: tr('Al empezar el enfoque, descansar, cumplir la meta y subir de nivel.', 'When focus starts, on breaks, on reaching the goal and on leveling up.'),
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
                        child: Text(tr('▶️ Probar sonido', '▶️ Test sound')),
                      ),
                    ),
                  if (launch.supported) ...[
                    _Section(tr('Sistema', 'System')),
                    // Idioma de toda la app: español (predeterminado) o inglés.
                    _Row(
                      label: tr('Idioma', 'Language'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final option in AppLanguage.values)
                            TextButton(
                              key: ValueKey('settings-language-${option.code}'),
                              onPressed: () => language.setLanguage(option),
                              child: Text(
                                option.nativeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: option == language.language
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: option == language.language
                                      ? StatsStyle.accent
                                      : StatsStyle.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _Switch(
                      keyName: 'login',
                      label: tr('Abrir al iniciar sesión', 'Open at login'),
                      value: launch.enabled,
                      onChanged: (v) async {
                        final ok = await launch.setEnabled(v);
                        if (mounted) setState(() => _needsApproval = !ok);
                      },
                    ),
                    if (_needsApproval)
                      Text(launchAtLoginApprovalHint,
                          style: const TextStyle(
                              color: StatsStyle.textSecondary, fontSize: 10)),
                  ],
                  _Section(tr('Inteligencia artificial', 'Artificial intelligence')),
                  PlainText(
                    ai == null
                        ? tr('Comprobando…', 'Checking…')
                        : ai.assistant != null
                            ? (ai.assistant!.onDevice
                                ? tr('✅ ${ai.assistant!.label}: gratis, sin conexión y privada.', '✅ ${ai.assistant!.label}: free, offline and private.')
                                : tr('✅ ${ai.assistant!.label} (usa tu API key).', '✅ ${ai.assistant!.label} (uses your API key).'))
                            : '⚠️ ${ai.problem ?? tr('Sin IA disponible.', 'No AI available.')}',
                    key: const ValueKey('settings-ai'),
                    style: const TextStyle(
                        color: StatsStyle.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const ValueKey('settings-welcome'),
                    onPressed: widget.onShowWelcome,
                    child: Text(tr('Ver la bienvenida otra vez', 'See the welcome again')),
                  ),
                  _Section(tr('Modo Concentración', 'Focus mode')),
                  const _FocusModeOptions(),
                  _Section(tr('Copia de seguridad', 'Backup')),
                  const _BackupButtons(),
                  _Section(tr('Acerca de', 'About')),
                  Text(
                    'PixelMate '
                    '${ref.watch(appVersionProvider).valueOrNull ?? ''}',
                    key: const ValueKey('settings-version'),
                    style: const TextStyle(
                        color: StatsStyle.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  Text(
                    tr('Tu compañero pixel art para enfocarte, descansar y jugar. Tus datos se quedan en este Mac.', 'Your pixel art companion to focus, rest and play. Your data stays on this Mac.'),
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
                    label: tr('Buscar actualizaciones solo', 'Check for updates automatically'),
                    help: tr('Una vez al día pregunta a GitHub por la última versión (no envía datos tuyos).', 'Once a day it asks GitHub for the latest version (it sends none of your data).'),
                    value: updates.enabled,
                    onChanged: updates.setEnabled,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      key: const ValueKey('settings-github'),
                      onPressed: () =>
                          ref.read(appInfoProvider).openRepository(),
                      child: Text(tr('Ver el proyecto en GitHub ↗', 'See the project on GitHub ↗')),
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
