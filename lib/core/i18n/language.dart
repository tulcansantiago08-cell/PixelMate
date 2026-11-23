import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Idiomas de la app. El español es el predeterminado.
enum AppLanguage {
  es('es', 'Español'),
  en('en', 'English');

  /// Código para el reconocimiento de voz, la voz y las fechas.
  final String code;

  /// Nombre escrito en ese mismo idioma.
  final String nativeName;

  const AppLanguage(this.code, this.nativeName);

  static AppLanguage parse(String? code) =>
      AppLanguage.values.firstWhere((l) => l.code == code,
          orElse: () => AppLanguage.es);
}

/// Idioma elegido, guardado en las preferencias. Al cambiarlo, la app se
/// vuelve a dibujar con los textos del nuevo idioma.
class LanguageSettings extends ChangeNotifier {
  static const _key = 'app.language';

  /// El idioma con el que [tr] escribe los textos. Las pruebas lo dejan en
  /// español.
  static AppLanguage current = AppLanguage.es;

  final SharedPreferences? _prefs;

  LanguageSettings([this._prefs]) {
    current = AppLanguage.parse(_prefs?.getString(_key));
  }

  AppLanguage get language => current;

  bool get isEnglish => current == AppLanguage.en;

  Future<void> setLanguage(AppLanguage value) async {
    if (value == current) return;
    current = value;
    await _prefs?.setString(_key, value.code);
    notifyListeners();
  }
}

/// El texto en el idioma de la app: `tr('Ajustes', 'Settings')`. Se escribe
/// cada texto en los dos idiomas junto a donde se usa, así funciona también
/// con valores dentro (`tr('Quedan $n min', '$n min left')`).
String tr(String es, String en) =>
    LanguageSettings.current == AppLanguage.en ? en : es;

/// Se sobrescribe en `main()`.
final languageSettingsProvider =
    ChangeNotifierProvider<LanguageSettings>((_) => LanguageSettings());

/// Vuelve a construir todos los widgets, conservando su estado: así cada
/// `tr()` se vuelve a evaluar con el idioma nuevo sin cerrar paneles.
void rebuildAllWidgets(BuildContext context) {
  void rebuild(Element element) {
    element.markNeedsBuild();
    element.visitChildren(rebuild);
  }

  (context as Element).visitChildren(rebuild);
}
