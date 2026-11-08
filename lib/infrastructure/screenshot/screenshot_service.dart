import 'package:flutter/services.dart';

/// Servicio Dart que llama al plugin Swift de captura de pantalla.
class ScreenshotService {
  static const _channel = MethodChannel('com.pixelmate/screen_capture');

  /// Retorna true si el permiso de grabación de pantalla está concedido.
  Future<bool> hasPermission() async {
    return await _channel.invokeMethod<bool>('hasPermission') ?? false;
  }

  /// Solicita permiso al usuario (abre el diálogo de macOS).
  Future<bool> requestPermission() async {
    return await _channel.invokeMethod<bool>('requestPermission') ?? false;
  }

  /// Captura la pantalla y retorna la imagen como base64 JPEG.
  /// Lanza [ScreenCaptureException] si no hay permiso o falla la captura.
  Future<String> captureBase64() async {
    try {
      final result = await _channel.invokeMethod<String>('captureScreen');
      if (result == null) throw ScreenCaptureException('Resultado nulo');
      return result;
    } on PlatformException catch (e) {
      throw ScreenCaptureException(e.message ?? 'Error desconocido');
    }
  }
}

class ScreenCaptureException implements Exception {
  final String message;
  ScreenCaptureException(this.message);

  @override
  String toString() => 'ScreenCaptureException: $message';
}
