/// Configuración de una jornada con ciclos de enfoque y descanso.
///
/// Un ciclo completo es: [focusesPerCycle] bloques de enfoque, con un
/// descanso corto entre ellos, y un descanso largo al final que
/// **reemplaza** al último descanso corto.
///
/// Con los valores por defecto: 50+10+50+10+50+30 = 200 minutos por ciclo.
class WorkdayConfig {
  final Duration focus;
  final Duration shortBreak;
  final Duration longBreak;
  final int focusesPerCycle;
  final Duration workday;

  const WorkdayConfig({
    this.focus = const Duration(minutes: 50),
    this.shortBreak = const Duration(minutes: 10),
    this.longBreak = const Duration(minutes: 30),
    this.focusesPerCycle = 3,
    this.workday = const Duration(hours: 8),
  });

  /// Estudio: bloques algo más cortos que el trabajo.
  static const study = WorkdayConfig(
    focus: Duration(minutes: 45),
    shortBreak: Duration(minutes: 10),
    longBreak: Duration(minutes: 20),
    focusesPerCycle: 3,
    workday: Duration(hours: 3),
  );

  /// Gamer: 60 min de juego y 5 de descanso visual, repetido.
  static const gaming = WorkdayConfig(
    focus: Duration(minutes: 60),
    shortBreak: Duration(minutes: 5),
    longBreak: Duration(minutes: 5),
    focusesPerCycle: 1,
    workday: Duration(hours: 3),
  );

  /// Duraciones de jornada ofrecidas en la interfaz (además de personalizada).
  static const presetWorkdays = [
    Duration(hours: 4),
    Duration(hours: 6),
    Duration(hours: 8),
    Duration(hours: 9),
  ];

  /// Duración de un ciclo completo, incluido el descanso largo.
  Duration get cycleLength =>
      focus * focusesPerCycle + shortBreak * (focusesPerCycle - 1) + longBreak;

  /// Lanza [ArgumentError] si la configuración no es utilizable.
  void validate() {
    if (focus <= Duration.zero) {
      throw ArgumentError.value(focus, 'focus', 'debe ser mayor que cero');
    }
    if (shortBreak < Duration.zero || longBreak < Duration.zero) {
      throw ArgumentError('Los descansos no pueden ser negativos');
    }
    if (focusesPerCycle < 1) {
      throw ArgumentError.value(
          focusesPerCycle, 'focusesPerCycle', 'debe ser al menos 1');
    }
    if (workday <= Duration.zero) {
      throw ArgumentError.value(workday, 'workday', 'debe ser mayor que cero');
    }
  }

  WorkdayConfig copyWith({
    Duration? focus,
    Duration? shortBreak,
    Duration? longBreak,
    int? focusesPerCycle,
    Duration? workday,
  }) =>
      WorkdayConfig(
        focus: focus ?? this.focus,
        shortBreak: shortBreak ?? this.shortBreak,
        longBreak: longBreak ?? this.longBreak,
        focusesPerCycle: focusesPerCycle ?? this.focusesPerCycle,
        workday: workday ?? this.workday,
      );

  Map<String, dynamic> toJson() => {
        'focusSeconds': focus.inSeconds,
        'shortBreakSeconds': shortBreak.inSeconds,
        'longBreakSeconds': longBreak.inSeconds,
        'focusesPerCycle': focusesPerCycle,
        'workdaySeconds': workday.inSeconds,
      };

  factory WorkdayConfig.fromJson(Map<String, dynamic> json) => WorkdayConfig(
        focus: Duration(seconds: json['focusSeconds'] as int),
        shortBreak: Duration(seconds: json['shortBreakSeconds'] as int),
        longBreak: Duration(seconds: json['longBreakSeconds'] as int),
        focusesPerCycle: json['focusesPerCycle'] as int,
        workday: Duration(seconds: json['workdaySeconds'] as int),
      );

  @override
  bool operator ==(Object other) =>
      other is WorkdayConfig &&
      other.focus == focus &&
      other.shortBreak == shortBreak &&
      other.longBreak == longBreak &&
      other.focusesPerCycle == focusesPerCycle &&
      other.workday == workday;

  @override
  int get hashCode =>
      Object.hash(focus, shortBreak, longBreak, focusesPerCycle, workday);
}
