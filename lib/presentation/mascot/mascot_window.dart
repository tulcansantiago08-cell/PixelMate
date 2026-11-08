import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../application/activity/activity_providers.dart';
import '../../application/desktop/mascot_panel.dart';
import '../../application/desktop/mascot_window_port.dart';
import '../../application/workday/workday_controller.dart';
import '../../application/workday/workday_dialogue.dart';
import '../../application/workday/workday_providers.dart';
import '../../domain/activity/activity_mode.dart';
import '../../domain/mascot/mascot_state.dart';
import '../../domain/session/session_phase.dart';
import '../../domain/session/workday_timer.dart';
import '../activity/suggestion_bubble.dart';
import '../chat/chat_bubble.dart';
import '../stats/stats_panel.dart';
import 'mascot_quick_actions.dart';
import '../workday/workday_badge.dart';
import '../workday/workday_menu.dart';
import '../../application/assistant/chat_controller.dart';
import '../../application/workday/workday_event.dart';
import '../../application/activity/focus_guard_controller.dart';
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/accessory_providers.dart';
import '../../application/mascot/idle_behavior.dart';
import '../../application/mascot/late_night.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/mascot/mascot_walker.dart';
import '../../application/progress/progress_providers.dart';
import '../../application/progress/progression.dart';
import '../../domain/mascot/pet_species.dart';
import 'pet_sprites.dart';
import 'rename_dialog.dart';
import '../onboarding/welcome_panel.dart';
import '../settings/settings_panel.dart';
import 'sprite_mascot.dart';

class MascotWindow extends ConsumerStatefulWidget {
  const MascotWindow({super.key});

  @override
  ConsumerState<MascotWindow> createState() => _MascotWindowState();
}

/// Clave de la mascota (para pruebas y accesibilidad).
const mascotKey = ValueKey('mascot');

class _MascotWindowState extends ConsumerState<MascotWindow> {
  bool _greeting = true;

  // Vida propia en reposo: estirarse, saludar, dormirse.
  final _idle = IdleBehavior(now: DateTime.now());
  Timer? _idleTimer;
  PetAnimation? _oneShot;
  late final MascotWalker _walker;
  static const _idleCheck = Duration(seconds: 30);

  // Reacción temporal a un suceso de la jornada.
  String? _speech;
  MascotState? _reactionMood;
  Timer? _reactionTimer;
  StreamSubscription<dynamic>? _eventsSub;

  static const _reactionDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _idleTimer = Timer.periodic(_idleCheck, (_) => _onIdleTick());
    _walker = MascotWalker(window: ref.read(mascotWindowProvider))
      ..addListener(_onWalkerChanged);

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _greeting = false);
      // La primera vez, la bienvenida guiada; si no, pregunta qué vamos a
      // hacer (si no hay sesión en curso).
      if (!ref.read(mascotSettingsProvider).onboardingDone) {
        _openPanel(MascotPanel.welcome);
      } else {
        ref.read(activityDetectionProvider.notifier).askWelcome();
      }
    });

    _eventsSub =
        ref.read(workdayControllerProvider.notifier).events.listen((event) {
      final mode = ref.read(workdayControllerProvider.notifier).currentMode;
      _wake(animate: false);
      final reaction = reactionFor(event, mode: mode);
      if (reaction == null || !mounted) return;
      _react(reaction, replace: true);
      if (event is WorkdayFinished) _summarize(event, mode);
    });
  }

  /// Al terminar la jornada, la IA del Mac (si la hay) hace un resumen; se
  /// dice después del mensaje de fin y queda guardado en el chat.
  Future<void> _summarize(WorkdayFinished event, ActivityMode? mode) async {
    final text = await ref.read(chatProvider.notifier).summarizeFinishedWorkday(
          event.status,
          mode: mode,
          distractions: ref.read(distractionsTodayProvider),
        );
    if (text != null && mounted) {
      _react(MascotReaction('📝 $text', MascotState.chatting),
          duration: const Duration(seconds: 15));
    }
  }

  /// Reacciones que esperan su turno (por ejemplo, un logro justo al
  /// terminar la jornada se dice después del mensaje de fin).
  final _pendingReactions = <(MascotReaction, Duration?)>[];

  /// Muestra un mensaje con su estado de ánimo durante unos segundos.
  /// Con [replace] sustituye al actual; si no, espera a que termine.
  void _react(MascotReaction reaction,
      {bool replace = false, Duration? duration}) {
    if (!mounted) return;
    if (!replace && _reactionTimer?.isActive == true) {
      _pendingReactions.add((reaction, duration));
      return;
    }
    _reactionTimer?.cancel();
    setState(() {
      _speech = reaction.message;
      _reactionMood = reaction.mood;
    });
    _reactionTimer = Timer(duration ?? _reactionDuration, () {
      if (!mounted) return;
      if (_pendingReactions.isNotEmpty) {
        final (next, nextDuration) = _pendingReactions.removeAt(0);
        _react(next, duration: nextDuration);
        return;
      }
      setState(() {
        _speech = null;
        _reactionMood = null;
      });
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _reactionTimer?.cancel();
    _idleTimer?.cancel();
    _walker
      ..removeListener(_onWalkerChanged)
      ..stop()
      ..dispose();
    super.dispose();
  }

  void _onWalkerChanged() {
    if (mounted) setState(() {});
  }

  bool get _isIdle =>
      !_greeting &&
      _reactionMood == null &&
      ref.read(mascotPanelProvider) == MascotPanel.none &&
      ref.read(activityDetectionProvider) == null &&
      !ref.read(workdayControllerProvider).isActive;

  void _onIdleTick() {
    if (!mounted || _oneShot != null || _walker.walking) return;
    final decision = _idle.tick(
      DateTime.now(),
      idle: _isIdle,
      canWalk: ref.read(mascotSettingsProvider).walkEnabled,
    );
    switch (decision) {
      case StartWalk():
        _walker.start();
      case PlayOnce(:final animation):
        setState(() => _oneShot = animation);
      case FallAsleep():
        setState(() {});
      case StayStill():
        break;
    }
  }

  /// Registra actividad; si dormía, se despierta (con animación).
  /// Devuelve `true` si estaba dormida.
  bool _wake({bool animate = true}) {
    // Cualquier interacción o suceso detiene el paseo.
    _walker.stop();
    final wasAsleep = _idle.activity(DateTime.now());
    if (wasAsleep && mounted) {
      setState(() => _oneShot = animate ? PetAnimation.wakeUp : null);
    }
    return wasAsleep;
  }

  /// Clic en la mascota: si duerme, solo la despierta.
  void _onMascotTap() {
    if (_wake()) return;
    _togglePanel();
  }

  Future<void> _openPanel(MascotPanel next) => setMascotPanel(
        window: ref.read(mascotWindowProvider),
        panel: ref.read(mascotPanelProvider.notifier),
        next: next,
      );

  /// Fin de la bienvenida (completa o saltada).
  Future<void> _finishWelcome() async {
    await ref.read(mascotSettingsProvider).completeOnboarding();
    await _openPanel(MascotPanel.none);
    if (!mounted) return;
    _react(
        MascotReaction('¡Encantado de conocerte! Soy '
            '${ref.read(petNameProvider)} 🐾', MascotState.celebrating),
        replace: true);
  }

  /// Mientras sea > 0 la ventana sigue ampliada (menú o diálogo abiertos).
  int _holdExpanded = 0;

  /// `true` si la ventana la amplió el menú (y no un panel).
  bool _grownForMenu = false;

  /// Abre el menú ⋯. En la ventana compacta no cabe entero, así que la
  /// amplía mientras está abierto (la mascota no se mueve: la ventana crece
  /// hacia arriba y a la izquierda).
  Future<void> _showMenu(BuildContext context, Offset position) async {
    final window = ref.read(mascotWindowProvider);
    var at = position;
    _holdExpanded++;
    final MenuAction? action;
    try {
      if (ref.read(mascotPanelProvider) == MascotPanel.none) {
        final before = await window.bounds();
        await window.setExpanded(true);
        _grownForMenu = true;
        final after = await window.bounds();
        at = position + (before.topLeft - after.topLeft);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (!context.mounted) return;
      action = await showWorkdayMenu(
        context: context,
        globalPosition: at,
        controller: ref.read(workdayControllerProvider.notifier),
        view: ref.read(workdayControllerProvider),
        onShowStats: () => _openPanel(MascotPanel.stats),
        onWalk: () async {
          await _shrinkIfIdle(); // pasea con su tamaño normal
          await _walker.start();
        },
        onRename: () => _rename(context),
        onSettings: () => _openPanel(MascotPanel.settings),
      );
    } finally {
      _holdExpanded--;
    }
    await action?.call();
    await _shrinkIfIdle();
  }

  /// Vuelve al tamaño compacto si no hay panel, menú ni diálogo abiertos.
  Future<void> _shrinkIfIdle() async {
    if (!mounted || !_grownForMenu || _holdExpanded > 0) return;
    // Si se abrió un panel, el tamaño ya es cosa suya.
    if (ref.read(mascotPanelProvider) != MascotPanel.none) {
      _grownForMenu = false;
      return;
    }
    _grownForMenu = false;
    await ref.read(mascotWindowProvider).setExpanded(false);
  }

  /// Ponerle nombre a la mascota (desde el menú ⋯).
  Future<void> _rename(BuildContext context) async {
    final settings = ref.read(mascotSettingsProvider);
    _holdExpanded++;
    final String? typed;
    try {
      typed = await showRenameDialog(context, settings.name);
    } finally {
      _holdExpanded--;
    }
    await _shrinkIfIdle();
    if (typed == null) return;
    final name = await settings.setName(typed);
    if (name == null || !mounted) return;
    _react(
        MascotReaction(
            '¡Me encanta! Desde ahora soy $name 🐾', MascotState.celebrating),
        replace: true);
  }

  /// Clic en la mascota: abre o cierra el chat (o cierra otro panel).
  Future<void> _togglePanel() =>
      _openPanel(ref.read(mascotPanelProvider) == MascotPanel.none
          ? MascotPanel.chat
          : MascotPanel.none);

  MascotState _mascotState(WorkdayView view, MascotPanel panel) {
    if (panel == MascotPanel.chat) return MascotState.chatting;
    if (panel == MascotPanel.welcome) return MascotState.greeting;
    if (_reactionMood != null) return _reactionMood!;
    if (_greeting) return MascotState.greeting;
    final status = view.status;
    if (status == null || status.state == WorkdayRunState.paused) {
      return _idle.asleep ? MascotState.sleeping : MascotState.idle;
    }
    return switch (status.phase?.kind) {
      SessionPhase.focus => focusMood(view.mode ?? ActivityMode.work),
      SessionPhase.shortBreak || SessionPhase.longBreak => MascotState.resting,
      _ => MascotState.idle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(workdayControllerProvider);
    final suggestion = ref.watch(activityDetectionProvider);
    final panel = ref.watch(mascotPanelProvider);
    final pet = ref.watch(loadedPetProvider).valueOrNull;
    // Si la mascota pregunta algo, deja de pasear.
    ref.listen(activityDetectionProvider, (_, s) {
      if (s != null) _walker.stop();
    });
    // Subir de nivel o desbloquear un logro: lo celebra.
    ref.listen(progressProvider, (before, after) {
      if (before == null) return;
      for (final event in progressEvents(before, after)) {
        _walker.stop();
        _react(MascotReaction(
            progressMessage(event).message, MascotState.celebrating));
      }
    });
    // De noche, si sigue la jornada: recordar descansar.
    ref.listen(lateNightProvider, (before, message) {
      if (message != null && before == null) {
        _walker.stop();
        _react(MascotReaction(message, MascotState.tired),
            replace: true, duration: const Duration(seconds: 15));
      }
    });
    // Guardián del enfoque: un aviso amable si hay una distracción al frente.
    ref.listen(focusGuardProvider, (before, nudge) {
      if (nudge != null && before == null) {
        _walker.stop();
        _react(
            MascotReaction(
                focusNudgeMessage(nudge, ref.read(workdayControllerProvider)),
                MascotState.alert),
            replace: true);
      }
    });
    ref.listen(dailyGoalProvider, (before, after) {
      if (goalJustReached(before, after)) {
        _walker.stop();
        _react(MascotReaction(
            goalReachedMessage(after!.goal), MascotState.celebrating));
      }
    });
    final walking = _walker.walking;

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
              // El panel abierto ocupa el espacio disponible arriba.
              if (panel == MascotPanel.none)
                const Spacer()
              else
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    child: switch (panel) {
                      MascotPanel.chat => const ChatBubble(),
                      MascotPanel.settings => SettingsPanel(
                          onClose: () => _openPanel(MascotPanel.none),
                          onShowWelcome: () =>
                              _openPanel(MascotPanel.welcome),
                        ),
                      MascotPanel.welcome =>
                        WelcomePanel(onDone: _finishWelcome),
                      _ => StatsPanel(
                          onClose: () => _openPanel(MascotPanel.none)),
                    },
                  ),
                ),

              if (panel == MascotPanel.none)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: suggestion != null
                      ? SuggestionBubble(
                          suggestion: suggestion,
                          onChoose: (action) => ref
                              .read(activityDetectionProvider.notifier)
                              .choose(action),
                        )
                      : WorkdayBadge(view: view, speech: _speech),
                ),

              // Mascota fija abajo, con accesos rápidos a su izquierda.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MascotQuickActions(
                    statsOpen: panel == MascotPanel.stats,
                    onStats: () {
                      _wake();
                      _openPanel(panel == MascotPanel.stats
                          ? MascotPanel.none
                          : MascotPanel.stats);
                    },
                    onMenu: (position) {
                      _wake();
                      _showMenu(context, position);
                    },
                  ),
                  GestureDetector(
                    key: mascotKey,
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) async {
                      _wake(animate: false); // arrastrarla detiene el paseo
                      await windowManager.startDragging();
                    },
                    onTap: _onMascotTap,
                    onSecondaryTapDown: (details) {
                      _wake();
                      _showMenu(context, details.globalPosition);
                    },
                    child: pet == null
                        ? const SizedBox.square(dimension: 160)
                        : SpriteMascot(
                            pet: pet,
                            animation: walking
                                ? PetAnimation.walk
                                : animationFor(_mascotState(view, panel)),
                            // El gato mira a la izquierda (cola a la derecha):
                            // se voltea al caminar hacia la derecha.
                            flipped: walking && !_walker.facingLeft,
                            oneShot: walking ? null : _oneShot,
                            accessory: pet.accessories[
                                ref.watch(equippedAccessoryProvider)],
                            onOneShotDone: () {
                              if (mounted) setState(() => _oneShot = null);
                            },
                          ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
