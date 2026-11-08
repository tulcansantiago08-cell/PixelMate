# Motor de jornada (SAN-19, SAN-20, SAN-21)

Código en `lib/domain/session/`, Dart puro sin dependencias de Flutter:

| Archivo | Responsabilidad |
|---|---|
| `workday_config.dart` | Tiempos configurables y validación |
| `phase_planner.dart` | `planWorkday()`: lista exacta de fases de la jornada |
| `workday_timer.dart` | Estado de la jornada (pausa, saltar, finalizar, guardar/restaurar) |

Pruebas: `test/domain/phase_planner_test.dart` y `test/domain/workday_timer_test.dart`.

## Decisiones

1. **El descanso largo reemplaza al último descanso corto.**
   Ciclo por defecto: 50 + 10 + 50 + 10 + 50 + 30 = 200 min.
2. **Los descansos cuentan dentro de la jornada.** El plan suma exactamente
   la duración elegida; la última fase se recorta si no cabe entera.
   8 h = 2 ciclos + enfoque 50 + descanso 10 + enfoque 20.
3. **Temporizador por marcas de tiempo, no por contador.** Se guardan
   `startedAt`, pausas y saltos; el estado se calcula con `statusAt(now)`.
   Un tic de interfaz perdido no desajusta nada.
4. **La pausa alarga la jornada.** El tiempo en pausa no avanza el plan.
5. **El reposo del Mac y la app cerrada sí cuentan.** El tiempo real sigue
   pasando; al volver, la jornada está donde corresponde según el reloj.
6. **Saltar una fase acorta la jornada.** El tramo saltado no se recupera ni
   cuenta como tiempo efectivo; un enfoque saltado no cuenta como completado.
7. **Inmutable.** Cada acción devuelve un `WorkdayTimer` nuevo, lo que facilita
   las pruebas y evita estados a medias.
8. **Si el reloj del sistema retrocede**, el tiempo transcurrido nunca es
   negativo.
9. **Recuperación**: `toJson()` / `fromJson()` con campo `version` para
   migraciones futuras. Guardarlo en SQLite (drift) queda para SAN-27.

## Pendiente

- Controlador en la capa de aplicación (Riverpod) que guarde una única jornada
  activa y programe un solo aviso con `nextTransitionAt()`.
- Persistencia en SQLite y recuperación al abrir la app.
- Avisos de 5 min / 30 s y diálogos de la mascota en cada transición.
- Interfaz: iniciar, pausar, saltar y finalizar desde el menú.
