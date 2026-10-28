# Rendimiento

## Fase 0: línea base

Fecha de ejecución: 2026-10-28.

La utilidad de medición está en
[`lib/core/debug/performance_measurement.dart`](../lib/core/debug/performance_measurement.dart).
Solo emite logs y eventos de Timeline cuando la aplicación corre en debug o
profile. Las etiquetas observadas son `startup.feed`, `search.local.*`,
`search.remote.*`, `transit.nearby_stops`, `transit.stop_details` y
`trip.plan`.

### Ejecución realizada

| Medición | Resultado | Estado |
|---|---:|---|
| Arranque Android en `--profile` | no medido | `flutter run --profile -d emulator-5554` quedó en `assembleProfile` y fue detenido después de más de 4 minutos |
| Consulta local `105` | no medido | no se pudo iniciar la app profile |
| Consulta remota `pocit` | no medido | el proxy `127.0.0.1:8765` no estaba disponible |
| Consulta remota `plaza` | no medido | el proxy `127.0.0.1:8765` no estaba disponible |
| Consulta remota `tres cruces` | no medido | el proxy `127.0.0.1:8765` no estaba disponible |
| Apertura del detalle de parada | no medido | no se pudo iniciar la app profile |
| `nearbyStops` | no medido | no se pudo iniciar la app profile |
| Planificación típica | no medido | no se pudo iniciar la app profile |
| Tamaño de la base oficial | no medido en esta ejecución | no se accedió a la base del dispositivo |
| Memoria aproximada | no medido | no se pudo capturar una sesión profile |

### Referencias históricas

Estos valores estaban documentados antes de esta fase y no se presentan como
mediciones nuevas:

- Feed oficial en una base temporal: 4,1 s para cuatro opciones de
  Montevideo Shopping → Nuevo Centro en el equipo de desarrollo.
- Importación en ese equipo: 9,6 s de análisis y 13,9 s de importación,
  23,5 s total.
- Una instalación Android anterior: aproximadamente 3 minutos y una base de
  198 MB. Corresponde a una implementación anterior y no fue repetida en esta
  ejecución.

## Auditoría visual

### Tokens actuales antes de Fase 2

Los tokens se concentran en `lib/core/theme/app_colors.dart` y el tema en
`lib/core/theme/app_theme.dart`:

- `ink`: `#0A122A`
- `ivory`: `#FBFBF6`
- `deepBlue`: `#1B658D` (debe migrar a `rumbo`)
- `lime`: `#D4E257`
- `mint`: `#D5E257` (token anterior que debe eliminarse)
- `white`: `#FFFFFF`
- `surfaceGray`: `#F1F3F5` (token anterior que debe eliminarse)
- `secondaryText`: `#4A5568`
- `darkSurface`: `#121C38`
- `darkElevatedSurface`: `#1B2848`
- `darkSecondaryText`: `#A9B3C7`
- `darkPrimary`: `#5FA8D3`
- `lightError`: `#C62828`
- `darkError`: `#FF8A80`

### Colores fijos fuera de `lib/core/theme`

- [`map_screen.dart`](../lib/features/map/presentation/map_screen.dart):
  `Colors.transparent`, colores derivados de `route.color` y colores de
  estructura de los marcadores.
- [`app_theme.dart`](../lib/core/theme/app_theme.dart): `Colors.transparent`
  en superficies de componentes; debe quedar cubierto por tokens del tema en
  Fase 2.
- [`line_details_sheet.dart`](../lib/features/stops_and_lines/presentation/line_details_sheet.dart)
  y [`stop_details_sheet.dart`](../lib/features/stops_and_lines/presentation/stop_details_sheet.dart):
  `Color(...)` para colores de líneas provenientes de los datos GTFS.
- [`search_destination_sheet.dart`](../lib/features/search/presentation/search_destination_sheet.dart):
  colores derivados del tipo de resultado y del tema.

Los colores de líneas provenientes de GTFS son una excepción permitida por la
especificación. No se encontraron colores hexadecimales literales en widgets;
los hexadecimales de datos de línea se convierten dinámicamente desde el feed.

### Pantallas sin tema

No se marcó ninguna pantalla como completamente sin tema: las pantallas usan
`Theme.of(context)` o `AppColors`, aunque todavía existen tokens heredados y
estilos puntuales que Fase 2 debe centralizar.

## Fase 1: búsqueda y datos más rápidos

Implementado sin agregar dependencias:

- Índice local normalizado, construido una vez por feed mediante `compute`,
  reutilizado por SQLite y web, con coincidencia por código, prefijo, palabra
  y contenido, máximo 20 resultados y orden estable.
- El índice incluye nombres y códigos de paradas, nombres de líneas y destinos
  de variantes.
- Debounce remoto de 200 ms, timeout de 8 s, cancelación lógica de respuestas
  viejas y caché LRU de 20 consultas.
- La planificación consulta como máximo 15 paradas cercanas por extremo.

Los presupuestos de Fase 1 siguen **no medidos** en un dispositivo Android
profile con el feed oficial: no se pudo iniciar una sesión profile utilizable
con el proxy activo. `EXPLAIN QUERY PLAN` de las consultas SQLite y la
validación de apertura read-only quedan pendientes para la siguiente iteración
de datos.
