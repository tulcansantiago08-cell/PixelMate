import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'application/workday/workday_providers.dart';
import 'infrastructure/persistence/sqlite_workday_store.dart';
import 'presentation/mascot/mascot_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(320, 480), // más grande para acomodar el chat
    minimumSize: Size(160, 200),
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    alwaysOnTop: true,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setAsFrameless();
    await windowManager.setIgnoreMouseEvents(false);
    await windowManager.show();
    await windowManager.focus();
  });

  // Base de datos local (jornada activa + historial).
  final dataDir = await getApplicationSupportDirectory();
  await dataDir.create(recursive: true);
  final store = SqliteWorkdayStore.open(p.join(dataDir.path, 'pixelmate.db'));

  runApp(
    ProviderScope(
      overrides: [workdayStoreProvider.overrideWithValue(store)],
      child: const PixelMateApp(),
    ),
  );
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
