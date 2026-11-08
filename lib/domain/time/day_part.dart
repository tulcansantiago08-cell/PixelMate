/// Parte del día según la hora local.
enum DayPart {
  /// 5:00–11:59
  morning,

  /// 12:00–18:59
  afternoon,

  /// 19:00–22:59
  evening,

  /// 23:00–4:59
  night;

  static DayPart of(DateTime localTime) {
    final h = localTime.hour;
    if (h >= 5 && h < 12) return morning;
    if (h >= 12 && h < 19) return afternoon;
    if (h >= 19 && h < 23) return evening;
    return night;
  }

  /// De noche la mascota tiene sueño: se duerme antes y no pasea.
  bool get sleepy => this == night;
}
