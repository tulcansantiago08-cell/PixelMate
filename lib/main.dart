import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'application/activity/activity_providers.dart';
import 'core/i18n/language.dart';
import 'application/activity/detection_settings.dart';
import 'application/activity/focus_guard.dart';
import 'application/activity/focus_guard_controller.dart';
import 'application/assistant/chat_controller.dart';
import 'application/assistant/code_writer.dart';
import 'application/assistant/mac_actions.dart';
import 'application/assistant/personal_store.dart';
import 'application/assistant/reminders.dart';
import 'application/assistant/video_finder.dart';
import 'application/desktop/app_info.dart';
import 'application/desktop/global_shortcut.dart';
import 'application/desktop/updates.dart';
import 'application/game/star_catch.dart';
import 'application/mascot/music.dart';
import 'application/assistant/alarm_settings.dart';
import 'application/assistant/apple_reminders.dart';
import 'application/settings/backup.dart';
import 'application/workday/focus_mode.dart';
import 'application/assistant/calendar_notes.dart';
import 'application/assistant/daily_briefing.dart';
import 'application/assistant/daily_tasks.dart';
import 'application/assistant/voice.dart';
import 'infrastructure/music/macos_music.dart';
import 'infrastructure/voice/macos_voice.dart';
import 'application/desktop/login_item.dart';
import 'application/desktop/sounds.dart';
import 'application/desktop/mascot_window_port.dart';
import 'application/goals/daily_goal.dart';
import 'application/mascot/late_night.dart';
import 'application/mascot/mascot_settings.dart';
import 'application/stats/file_saver.dart';
import 'application/stats/weekly_report.dart';
import 'application/workday/workday_providers.dart';
import 'infrastructure/activity/macos_app_activity.dart';
import 'infrastructure/assistant/apple_assistant.dart';
import 'infrastructure/assistant/assistant_setup.dart';
import 'infrastructure/assistant/macos_actions.dart';
import 'infrastructure/assistant/youtube_video_finder.dart';
import 'infrastructure/claude/claude_provider.dart';
import 'infrastructure/screenshot/screenshot_service.dart';
import 'infrastructure/desktop/macos_login_item.dart';
import 'infrastructure/desktop/native_effects.dart';
import 'infrastructure/app/github_update_checker.dart';
import 'infrastructure/app/macos_app_info.dart';
import 'infrastructure/files/macos_backup_files.dart';
import 'infrastructure/files/macos_file_saver.dart';
import 'infrastructure/desktop/native_mascot_window.dart';
import 'infrastructure/desktop/system_notifier.dart';
import 'infrastructure/persistence/sqlite_workday_store.dart';
import 'presentation/desktop/desktop_shell.dart';
import 'presentation/mascot/mascot_window.dart';
import 'presentation/stats/stats_style.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadAppFont();

  // Base de datos local (jornada activa + historial).
  final dataDir = await getApplicationSupportDirectory();
  await dataDir.create(recursive: true);
  final store = SqliteWorkdayStore.open(p.join(dataDir.path, 'pixelmate.db'));
  final prefs = await SharedPreferences.getInstance();
  // El idioma va primero: lo usan los textos del menú y los avisos al arrancar.
  final language = LanguageSettings(prefs);

  // Errores al registro de la app (Library/Logs/pixelmate.log), para poder
  // diagnosticar lo que no se ve.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    appLog('Error: ${details.exceptionAsString()}\n${details.stack}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLog('Error: $error\n$stack');
    return true;
  };

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
  final focusGuard = FocusGuardSettings(prefs);
  final launchAtLogin = LaunchAtLogin(MacosLoginItem());
  final shortcutSettings = ShortcutSettings(prefs);
  final soundSettings = SoundSettings(prefs);
  final sounds = MacosSoundPlayer();
  final weeklyStore = WeeklyReportStore(prefs);
  final personal = PersonalStore(prefs);
  final catalog = await loadAppCatalog(
      userFilePath: p.join(dataDir.path, 'detectable_apps.json'));

  final container = ProviderContainer(overrides: [
    workdayStoreProvider.overrideWithValue(store),
    languageSettingsProvider.overrideWith((_) => language),
    mascotWindowProvider.overrideWithValue(window),
    detectionSettingsProvider.overrideWithValue(detection),
    mascotSettingsProvider.overrideWithValue(mascotSettings),
    dailyGoalSettingsProvider.overrideWithValue(dailyGoal),
    focusGuardSettingsProvider.overrideWithValue(focusGuard),
    launchAtLoginProvider.overrideWithValue(launchAtLogin),
    shortcutSettingsProvider.overrideWithValue(shortcutSettings),
    soundSettingsProvider.overrideWithValue(soundSettings),
    soundPlayerProvider.overrideWithValue(sounds),
    weeklyReportStoreProvider.overrideWithValue(weeklyStore),
    fileSaverProvider.overrideWithValue(MacosFileSaver()),
    appInfoProvider.overrideWithValue(MacosAppInfo()),
    personalStoreProvider.overrideWithValue(personal),
    macActionsProvider.overrideWithValue(MacosActions()),
    videoFinderProvider.overrideWithValue(YouTubeVideoFinder()),
    codeWriterProvider.overrideWithValue(AppleCodeWriter()),
    updateCheckerProvider.overrideWithValue(GitHubUpdateChecker()),
    updateSettingsProvider.overrideWithValue(UpdateSettings(prefs)),
    updateScheduleProvider.overrideWithValue(true),
    gameStoreProvider.overrideWith((_) => GameStore(prefs)),
    musicEventsProvider.overrideWithValue(MacosMusic().events),
    voicePortProvider.overrideWithValue(MacosVoice()),
    dailyTaskStoreProvider.overrideWith((_) => DailyTaskStore(prefs)),
    calendarStoreProvider.overrideWith((_) => CalendarStore(prefs)),
    briefingPrefsProvider.overrideWithValue(prefs),
    backupPrefsProvider.overrideWithValue(prefs),
    appleRemindersPrefsProvider.overrideWithValue(prefs),
    focusModeSettingsProvider.overrideWith((_) => FocusModeSettings(prefs)),
    backupFilesProvider.overrideWithValue(MacosBackupFiles()),
    alarmSettingsProvider.overrideWith((_) => AlarmSettings(prefs)),
    // IA del chat: la de Apple si está disponible; si no, Claude.
    assistantChoiceProvider
        .overrideWith((_) => detectAssistant(claudeApiKey: claudeApiKey)),
    screenCaptureProvider.overrideWithValue(
        () => captureScreenWithPermission(ScreenshotService())),
    appCatalogProvider.overrideWithValue(catalog),
    foregroundAppsProvider.overrideWithValue(MacosAppActivity().foregroundApps),
  ]);

  final shell = DesktopShell(
    container: container,
    window: window,
    notifier: SystemNotifier(),
    detection: detection,
    mascot: mascotSettings,
    launchAtLogin: launchAtLogin,
    focusGuard: focusGuard,
    shortcut: MacosGlobalShortcut(),
    shortcutSettings: shortcutSettings,
    sounds: sounds,
    soundSettings: soundSettings,
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
  container.read(focusGuardProvider);
  container.read(lateNightProvider);
  container.read(reminderProvider);
  container.read(updateProvider);
}

class PixelMateApp extends ConsumerWidget {
  const PixelMateApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Al cambiar de idioma se vuelve a dibujar todo con los textos nuevos.
    ref.listen<LanguageSettings>(languageSettingsProvider, (_, __) {
      rebuildAllWidgets(context);
    });
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: StatsStyle.fontFamily,
        colorScheme: ColorScheme.fromSeed(
          seedColor: StatsStyle.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: StatsStyle.accent,
          onPrimary: Colors.white,
          surface: StatsStyle.surface,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: StatsStyle.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: StatsStyle.glassBorder)),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: StatsStyle.surfaceRaised,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: StatsStyle.glassBorder)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: StatsStyle.accent,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: StatsStyle.textPrimary,
            side: const BorderSide(color: StatsStyle.glassBorder),
            shape: const StadiumBorder(),
          ),
        ),
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: StatsStyle.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: StatsStyle.glassBorder),
          ),
          textStyle: const TextStyle(
              color: StatsStyle.textPrimary,
              fontSize: 11,
              fontFamily: StatsStyle.fontFamily),
        ),
      ),
      home: const MascotWindow(),
    );
  }
}
