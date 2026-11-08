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

## Integración en la app

| Capa | Archivo | Qué hace |
|---|---|---|
| Aplicación | `lib/application/workday/workday_controller.dart` | Una sola jornada activa; la guarda en cada cambio; tic de 1 s; emite sucesos sin repetirlos |
| Aplicación | `lib/application/workday/workday_event.dart` | Sucesos: inicio, cambio de fase, quedan 5 min / 30 s, quedan 30 / 5 min de jornada, pausa, fin |
| Aplicación | `lib/application/workday/workday_dialogue.dart` | Frase y estado de ánimo de la mascota para cada suceso |
| Infraestructura | `lib/infrastructure/persistence/sqlite_workday_store.dart` | SQLite: tabla `active_workday` (máx. 1 fila) y `workday_history` |
| Presentación | `lib/presentation/workday/` | Globo con fase, cuenta regresiva y progreso; menú de clic derecho |

- Base de datos: `~/Library/Application Support/<bundle id>/pixelmate.db`
  (o el contenedor del sandbox en Release).
- Al abrir la app se recupera la jornada. Si terminó mientras estaba cerrada,
  se registra en el historial; no se repiten avisos de fases ya pasadas.
- Si el Mac despierta y se cruzan dos avisos a la vez, solo sale el más cercano.

## Pendiente

- Icono en la barra de menú (SAN-8) con las mismas acciones.
- Configurar tiempos personalizados desde un panel (hoy solo 4/6/8/9 h).
- Modo estudio y gamer reutilizando este motor (SAN-22, SAN-23).
- Estadísticas a partir de `workday_history` (SAN-26).
