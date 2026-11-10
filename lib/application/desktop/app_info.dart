import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Datos de la app instalada.
abstract class AppInfo {
  /// "0.1.0 (1)".
  Future<String> version();

  /// Abre el repositorio de PixelMate en el navegador.
  Future<void> openRepository();
}

class FakeAppInfo implements AppInfo {
  final String value;
  int opened = 0;
  FakeAppInfo([this.value = 'dev']);

  @override
  Future<String> version() async => value;

  @override
  Future<void> openRepository() async => opened++;
}

/// Se sobrescribe en `main()`.
final appInfoProvider = Provider<AppInfo>((_) => FakeAppInfo());

final appVersionProvider =
    FutureProvider<String>((ref) => ref.watch(appInfoProvider).version());
