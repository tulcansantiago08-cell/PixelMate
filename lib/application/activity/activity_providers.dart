import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/activity/detectable_app.dart';
import '../workday/workday_providers.dart';
import 'activity_detection_controller.dart';
import 'detection_settings.dart';
import 'suggestion.dart';
import 'suggestion_engine.dart';

/// Se sobrescriben en `main()`; por defecto no hay detección (pruebas).
final foregroundAppsProvider =
    Provider<Stream<ForegroundApp>>((_) => const Stream.empty());

final appCatalogProvider = Provider<AppCatalog>((_) => const AppCatalog([]));

final detectionSettingsProvider = Provider<DetectionSettings>(
  (_) => throw UnimplementedError('detectionSettingsProvider sin configurar'),
);

final activityDetectionProvider =
    StateNotifierProvider<ActivityDetectionController, Suggestion?>((ref) {
  return ActivityDetectionController(
    foregroundApps: ref.watch(foregroundAppsProvider),
    engine: SuggestionEngine(catalog: ref.watch(appCatalogProvider)),
    settings: ref.watch(detectionSettingsProvider),
    workday: ref.watch(workdayControllerProvider.notifier),
  );
});
