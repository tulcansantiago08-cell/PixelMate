import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screenshot/screenshot_service.dart';

// El chat vive en `application/assistant/chat_controller.dart`; se
// reexporta para quien lo importaba desde aquí.
export '../../application/assistant/chat_controller.dart'
    show ChatMessage, chatProvider;

/// API key de Claude (opcional): `--dart-define=ANTHROPIC_API_KEY=...`.
const claudeApiKey =
    String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');

final screenshotServiceProvider = Provider<ScreenshotService>(
  (_) => ScreenshotService(),
);

/// Captura con permiso: lo pide si aún no está concedido.
Future<String> captureScreenWithPermission(ScreenshotService s) async {
  if (!await s.hasPermission()) await s.requestPermission();
  return s.captureBase64();
}
