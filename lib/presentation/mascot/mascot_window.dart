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
import '../../application/goals/daily_goal.dart';
import '../../application/mascot/accessory_providers.dart';
import '../../application/mascot/idle_behavior.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../application/mascot/mascot_walker.dart';
import '../../application/progress/progress_providers.dart';
import '../../application/progress/progression.dart';
import '../../domain/mascot/pet_species.dart';
import 'pet_sprites.dart';
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
      // Tras saludar, pregunta qué vamos a hacer (si no hay sesión en curso).
      ref.read(activityDetectionProvider.notifier).askWelcome();
    });

    _eventsSub =
        ref.read(workdayControllerProvider.notifier).events.listen((event) {
      final mode = ref.read(workdayControllerProvider.notifier).currentMode;
      _wake(animate: false);
      final reaction = reactionFor(event, mode: mode);
      if (reaction == null || !mounted) return;
      _react(reaction, replace: true);
    });
  }

  /// Reacciones que esperan su turno (por ejemplo, un logro justo al
  /// terminar la jornada se dice después del mensaje de fin).
  final _pendingReactions = <MascotReaction>[];

  /// Muestra un mensaje con su estado de ánimo durante unos segundos.
  /// Con [replace] sustituye al actual; si no, espera a que termine.
  void _react(MascotReaction reaction, {bool replace = false}) {
    if (!mounted) return;
    if (!replace && _reactionTimer?.isActive == true) {
      _pendingReactions.add(reaction);
      return;
    }
    _reactionTimer?.cancel();
    setState(() {
      _speech = reaction.message;
      _reactionMood = reaction.mood;
    });
    _reactionTimer = Timer(_reactionDuration, () {
      if (!mounted) return;
      if (_pendingReactions.isNotEmpty) {
        _react(_pendingReactions.removeAt(0));
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

  void _showMenu(BuildContext context, Offset position) => showWorkdayMenu(
        context: context,
        globalPosition: position,
        controller: ref.read(workdayControllerProvider.notifier),
        view: ref.read(workdayControllerProvider),
        onShowStats: () => _openPanel(MascotPanel.stats),
        onWalk: () => _walker.start(),
      );

  /// Clic en la mascota: abre o cierra el chat (o cierra otro panel).
  Future<void> _togglePanel() =>
      _openPanel(ref.read(mascotPanelProvider) == MascotPanel.none
          ? MascotPanel.chat
          : MascotPanel.none);

  MascotState _mascotState(WorkdayView view, MascotPanel panel) {
    if (panel == MascotPanel.chat) return MascotState.chatting;
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
    ref.listen(dailyGoalProvider, (before, after) {
      if (goalJustReached(before, after)) {
        _walker.stop();
        _react(MascotReaction(goalReachedMessage(after!.goal),
            MascotState.celebrating));
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
                    child: panel == MascotPanel.chat
                        ? const ChatBubble()
                        : StatsPanel(
                            onClose: () => _openPanel(MascotPanel.none)),
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
