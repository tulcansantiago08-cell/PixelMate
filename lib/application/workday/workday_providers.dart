import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'workday_controller.dart';
import 'workday_store.dart';

/// Se sobrescribe en `main()` con la base de datos real ya abierta.
final workdayStoreProvider = Provider<WorkdayStore>(
  (_) => throw UnimplementedError('workdayStoreProvider sin configurar'),
);

final workdayControllerProvider =
    StateNotifierProvider<WorkdayController, WorkdayView>(
  (ref) => WorkdayController(store: ref.watch(workdayStoreProvider)),
);
