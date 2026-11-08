import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/desktop/login_item.dart';
import 'package:pixelmate/application/progress/celebrations.dart';
import 'package:pixelmate/domain/session/workday_config.dart';
import 'package:pixelmate/application/desktop/sounds.dart';
import 'package:pixelmate/application/desktop/global_shortcut.dart';
import 'package:pixelmate/application/desktop/mascot_panel.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/mascot/mascot_settings.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/desktop/system_notifier.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/desktop/desktop_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prueba el camino real de la barra de menú: el menú que se envía al
/// plugin nativo y el clic que llega de macOS con el id del elemento.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');
  const codec = StandardMethodCodec();
  late List<Map<String, dynamic>> menus;

  setUp(() {
    menus = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setContextMenu') {
        menus.add(
            Map<String, dynamic>.from((call.arguments as Map)['menu'] as Map));
      }
      return true;
    });
  });

  /// Busca el id que el plugin recibió para la etiqueta dada.
  int idOf(String label) {
    int? find(List items) {
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item['label'] == label) return item['id'] as int;
        final sub = item['submenu'];
        if (sub != null) {
          final r = find((sub as Map)['items'] as List);
          if (r != null) return r;
        }
      }
      return null;
    }

    final id = find(menus.last['items'] as List);
    expect(id, isNotNull, reason: 'No hay "$label" en el menú');
    return id!;
  }

  /// Simula el clic que macOS envía a Flutter.
  Future<void> click(String label) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
          MethodCall('onTrayMenuItemClick', {'id': idOf(label)})),
      (_) {},
    );
    await pumpEventQueue();
  }

  /// Elemento del último menú con esa etiqueta (o `null`).
  Map<String, dynamic>? itemOf(String label) {
    for (final raw in menus.last['items'] as List) {
      final item = Map<String, dynamic>.from(raw as Map);
      if (item['label'] == label) return item;
    }
    return null;
  }

  Future<(ProviderContainer, NoopMascotWindow)> startShell({
    LoginItemPort? loginItem,
    GlobalShortcutPort? shortcut,
    ShortcutSettings? shortcutSettings,
    SoundPlayer? sounds,
    SoundSettings? soundSettings,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final window = NoopMascotWindow();
    final container = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      mascotWindowProvider.overrideWithValue(window),
    ]);
    addTearDown(container.dispose);
    final shell = DesktopShell(
      container: container,
      window: window,
      notifier: SystemNotifier(),
      detection: DetectionSettings(prefs),
      mascot: MascotSettings(),
      launchAtLogin: LaunchAtLogin(loginItem ?? NoopLoginItem()),
      shortcut: shortcut,
      shortcutSettings: shortcutSettings,
      sounds: sounds,
      soundSettings: soundSettings,
      quitApp: () async {},
    );
    await shell.start();
    addTearDown(shell.dispose);
    await pumpEventQueue();
    return (container, window);
  }

  test('"Estadísticas" en la barra de menú abre el panel', () async {
    final (container, _) = await startShell();
    await click('Estadísticas');
    expect(container.read(mascotPanelProvider), MascotPanel.stats);
  });

  test('con una jornada en marcha también abre el panel', () async {
    final (container, _) = await startShell();
    await click('8 horas');
    expect(container.read(workdayControllerProvider).isActive, isTrue);
    await click('Estadísticas');
    expect(container.read(mascotPanelProvider), MascotPanel.stats);
    container.read(workdayControllerProvider.notifier).finish();
  });

  test('con la mascota oculta, la muestra y abre el panel', () async {
    final (container, window) = await startShell();
    await click('Ocultar mascota');
    expect(window.visible.value, isFalse);
    await click('Estadísticas');
    expect(window.visible.value, isTrue);
    expect(container.read(mascotPanelProvider), MascotPanel.stats);
  });

  test('sin soporte no aparece "Abrir al iniciar sesión"', () async {
    await startShell();
    expect(itemOf('Abrir al iniciar sesión'), isNull);
  });

  test('"Abrir al iniciar sesión" se activa y desactiva', () async {
    final login = NoopLoginItem(supported: true);
    await startShell(loginItem: login);
    expect(itemOf('Abrir al iniciar sesión')!['checked'], isFalse);

    await click('Abrir al iniciar sesión');
    expect(login.enabled, isTrue);
    expect(itemOf('Abrir al iniciar sesión')!['checked'], isTrue);

    await click('Abrir al iniciar sesión');
    expect(login.enabled, isFalse);
    expect(itemOf('Abrir al iniciar sesión')!['checked'], isFalse);
  });

  test('si macOS pide aprobarlo, la casilla queda sin marcar', () async {
    final login = NoopLoginItem(supported: true, grant: false);
    await startShell(loginItem: login);
    await click('Abrir al iniciar sesión');
    expect(login.enabled, isFalse);
    expect(itemOf('Abrir al iniciar sesión')!['checked'], isFalse);
  });

  test('el atajo global abre y cierra el chat, y muestra la mascota', () async {
    final shortcut = NoopGlobalShortcut();
    final settings = ShortcutSettings();
    final (container, window) =
        await startShell(shortcut: shortcut, shortcutSettings: settings);
    expect(shortcut.registered, isTrue, reason: 'activado por defecto');
    expect(settings.working, isTrue);

    await click('Ocultar mascota');
    shortcut.press();
    await pumpEventQueue();
    expect(window.visible.value, isTrue);
    expect(container.read(mascotPanelProvider), MascotPanel.chat);
    shortcut.press();
    await pumpEventQueue();
    expect(container.read(mascotPanelProvider), MascotPanel.none);

    await settings.setEnabled(false);
    await pumpEventQueue();
    expect(shortcut.registered, isFalse);
  });

  test('si otra app usa el atajo, se avisa en Ajustes', () async {
    final settings = ShortcutSettings();
    await startShell(
        shortcut: NoopGlobalShortcut(available: false),
        shortcutSettings: settings);
    expect(settings.working, isFalse);
  });

  test('los sonidos acompañan la jornada solo si están activados', () async {
    final player = NoopSoundPlayer();
    final sound = SoundSettings();
    final (container, _) =
        await startShell(sounds: player, soundSettings: sound);
    final workday = container.read(workdayControllerProvider.notifier);

    workday.start(const WorkdayConfig());
    await pumpEventQueue();
    expect(player.played, isEmpty, reason: 'apagados por defecto');
    workday.finish();
    await pumpEventQueue();

    await sound.setEnabled(true);
    workday.start(const WorkdayConfig(workday: Duration(hours: 4)));
    await pumpEventQueue();
    workday.skipPhase(); // enfoque -> descanso
    await pumpEventQueue();
    workday.finish();
    await pumpEventQueue();
    expect(player.played.take(3),
        [PetSound.focus, PetSound.rest, PetSound.finish]);
  });

  test('las celebraciones suenan y avisan', () async {
    final player = NoopSoundPlayer();
    final sound = SoundSettings();
    await sound.setEnabled(true);
    final (container, _) =
        await startShell(sounds: player, soundSettings: sound);
    container
        .read(celebrationProvider.notifier)
        .add(const Celebration('¡Nivel 4!', 'Subiste', levelUp: true));
    await pumpEventQueue();
    expect(player.played, [PetSound.level]);
    container
        .read(celebrationProvider.notifier)
        .add(const Celebration('Logro', 'Hasta el final'));
    await pumpEventQueue();
    expect(player.played, [PetSound.level], reason: 'solo el nivel suena');
  });
}
