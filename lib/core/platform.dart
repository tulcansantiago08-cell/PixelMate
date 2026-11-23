import 'dart:io';

/// Si la app corre en un Mac: allí están la IA de Apple, la voz, el control
/// de apps, música y volumen, el Calendario y los Contactos, Concentración,
/// los atajos globales y abrir al iniciar sesión. En Windows y Linux esas
/// opciones no se muestran.
///
/// En las pruebas cuenta como Mac, para probar también esas pantallas.
bool get isMacDesktop =>
    Platform.isMacOS || Platform.environment.containsKey('FLUTTER_TEST');
