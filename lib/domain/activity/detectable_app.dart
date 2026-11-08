/// App que está en primer plano, tal como la informa el sistema.
class ForegroundApp {
  final String? bundleId;
  final String name;
  final String? executable;

  const ForegroundApp({this.bundleId, required this.name, this.executable});

  /// Identificador estable para exclusiones: bundle id o, si no hay, nombre.
  String get key => bundleId ?? name;

  factory ForegroundApp.fromMap(Map<Object?, Object?> map) => ForegroundApp(
        bundleId: map['bundleId'] as String?,
        name: (map['name'] as String?) ?? (map['executable'] as String?) ?? '?',
        executable: map['executable'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is ForegroundApp &&
      other.bundleId == bundleId &&
      other.name == name &&
      other.executable == executable;

  @override
  int get hashCode => Object.hash(bundleId, name, executable);

  @override
  String toString() => 'ForegroundApp($name, $bundleId)';
}

enum AppCategory {
  development,
  gaming,

  /// Mensajería, redes y video: no sugieren un modo, pero el guardián del
  /// enfoque avisa si se abren durante un bloque de enfoque.
  distraction,
}

/// Regla para reconocer una app. Basta con que coincida un criterio.
class DetectableApp {
  final String name;
  final AppCategory category;

  /// Identificadores exactos (`com.microsoft.VSCode`).
  final List<String> bundleIds;

  /// Prefijos de identificador (`com.riotgames.LeagueofLegends`), para
  /// juegos con varios procesos (lanzador, cliente, partida).
  final List<String> bundleIdPrefixes;

  /// Texto que contiene el nombre de la app, sin distinguir mayúsculas.
  /// Útil para juegos sin bundle id (p. ej. Minecraft se ejecuta con Java).
  final List<String> nameContains;

  const DetectableApp({
    required this.name,
    required this.category,
    this.bundleIds = const [],
    this.bundleIdPrefixes = const [],
    this.nameContains = const [],
  });

  bool matches(ForegroundApp app) {
    final id = app.bundleId;
    if (id != null) {
      if (bundleIds.contains(id)) return true;
      if (bundleIdPrefixes.any(id.startsWith)) return true;
    }
    final name = app.name.toLowerCase();
    return nameContains.any((n) => name.contains(n.toLowerCase()));
  }

  factory DetectableApp.fromJson(Map<String, dynamic> json) => DetectableApp(
        name: json['name'] as String,
        category: AppCategory.values.byName(json['category'] as String),
        bundleIds: _strings(json['bundleIds']),
        bundleIdPrefixes: _strings(json['bundleIdPrefixes']),
        nameContains: _strings(json['nameContains']),
      );

  static List<String> _strings(Object? v) =>
      v == null ? const [] : (v as List).cast<String>();
}

/// Catálogo de apps reconocibles.
class AppCatalog {
  final List<DetectableApp> apps;

  const AppCatalog(this.apps);

  /// La primera regla que coincide, o `null`.
  DetectableApp? identify(ForegroundApp app) {
    for (final rule in apps) {
      if (rule.matches(app)) return rule;
    }
    return null;
  }

  /// Lee el formato `{"apps": [...]}`. Las entradas inválidas se ignoran
  /// para que un error en el archivo del usuario no rompa la detección.
  static AppCatalog parse(Map<String, dynamic> json,
      {void Function(Object error)? onInvalid}) {
    final apps = <DetectableApp>[];
    for (final entry in (json['apps'] as List? ?? const [])) {
      try {
        apps.add(DetectableApp.fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        onInvalid?.call(e);
      }
    }
    return AppCatalog(apps);
  }

  /// Las reglas del usuario van primero para que puedan sobrescribir.
  AppCatalog withUserApps(AppCatalog user) =>
      AppCatalog([...user.apps, ...apps]);
}
