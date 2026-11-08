import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'application/activity/activity_providers.dart';
import 'application/activity/detection_settings.dart';
import 'application/desktop/mascot_window_port.dart';
import 'application/goals/daily_goal.dart';
import 'application/mascot/mascot_settings.dart';
import 'application/workday/workday_providers.dart';
import 'infrastructure/activity/macos_app_activity.dart';
import 'infrastructure/desktop/macos_login_item.dart';
import 'infrastructure/desktop/native_mascot_window.dart';
import 'infrastructure/desktop/system_notifier.dart';
import 'infrastructure/persistence/sqlite_workday_store.dart';
import 'presentation/desktop/desktop_shell.dart';
import 'presentation/mascot/mascot_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Base de datos local (jornada activa + historial).
  final dataDir = await getApplicationSupportDirectory();
  await dataDir.create(recursive: true);
  final store = SqliteWorkdayStore.open(p.join(dataDir.path, 'pixelmate.db'));
  final prefs = await SharedPreferences.getInstance();

  await windowManager.ensureInitialized();
  final window = NativeMascotWindow(prefs);
  const options = WindowOptions(
    size: NativeMascotWindow.compactSize,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    alwaysOnTop: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await window.init(); // esquina inferior derecha o última posición
    await windowManager.show();
  });

  // Detección de apps: catálogo incluido + el del usuario, si existe.
  final detection = DetectionSettings(prefs);
  final mascotSettings = MascotSettings(prefs);
  final dailyGoal = DailyGoalSettings(prefs);
  final catalog = await loadAppCatalog(
      userFilePath: p.join(dataDir.path, 'detectable_apps.json'));

  final container = ProviderContainer(overrides: [
    workdayStoreProvider.overrideWithValue(store),
    mascotWindowProvider.overrideWithValue(window),
    detectionSettingsProvider.overrideWithValue(detection),
    mascotSettingsProvider.overrideWithValue(mascotSettings),
    dailyGoalSettingsProvider.overrideWithValue(dailyGoal),
    appCatalogProvider.overrideWithValue(catalog),
    foregroundAppsProvider.overrideWithValue(MacosAppActivity().foregroundApps),
  ]);

  final shell = DesktopShell(
    container: container,
    window: window,
    notifier: SystemNotifier(),
    detection: detection,
    mascot: mascotSettings,
    loginItem: MacosLoginItem(),
    quitApp: () async {
      container.dispose();
      store.close();
      await windowManager.destroy();
    },
  );

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PixelMateApp(),
  ));
  await shell.start();
  // Empieza a escuchar la app activa desde el arranque.
  container.read(activityDetectionProvider);
}

class PixelMateApp extends StatelessWidget {
  const PixelMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
      ),
      home: const MascotWindow(),
    );
  }
}
