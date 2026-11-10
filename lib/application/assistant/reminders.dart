import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'assistant_executor.dart';
import 'code_writer.dart';
import 'mac_actions.dart';
import 'personal_store.dart';
import 'video_finder.dart';

/// Avisa los recordatorios a su hora. Los que vencieron con la app cerrada
/// se avisan al abrirla. El estado es el último aviso (un objeto nuevo cada
/// vez, para que quien escucha reaccione).
class ReminderController extends StateNotifier<ReminderAlert?> {
  final PersonalStore _store;
  final DateTime Function() _now;
  Timer? _timer;

  ReminderController(this._store,
      {DateTime Function()? now, Duration every = const Duration(seconds: 15)})
      : _now = now ?? DateTime.now,
        super(null) {
    _timer = Timer.periodic(every, (_) => check());
    scheduleMicrotask(check);
  }

  Future<void> check() async {
    final now = _now();
    final due = await _store.takeDue(now);
    if (due.isEmpty || !mounted) return;
    state = ReminderAlert(due, now);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ReminderAlert {
  final List<ReminderItem> items;
  final DateTime at;
  const ReminderAlert(this.items, this.at);

  /// "⏰ ¡Recuerda: llamar a mamá!" (y si llegaron tarde, desde cuándo).
  String get message {
    String one(ReminderItem r) {
      final late = at.difference(r.due) > const Duration(minutes: 2);
      return late ? '${r.text} (era para ${describeWhen(r.due, at)})' : r.text;
    }

    return items.length == 1
        ? '⏰ ¡Recuerda: ${one(items.single)}!'
        : '⏰ Recordatorios: ${items.map(one).join(' · ')}';
  }
}

final reminderProvider =
    StateNotifierProvider<ReminderController, ReminderAlert?>(
        (ref) => ReminderController(ref.watch(personalStoreProvider)));

final assistantExecutorProvider = Provider<AssistantExecutor>((ref) =>
    AssistantExecutor(
        ref.watch(personalStoreProvider), ref.watch(macActionsProvider),
        videos: ref.watch(videoFinderProvider),
        coder: ref.watch(codeWriterProvider)));
