# Progreso

## Fase 1: horarios compactos por patrón de recorrido (completa, probada con tests)

- Se reemplazó el esquema `stop_times` por `trip_patterns` + `pattern_stops` (DB v6, esquema viejo se descarta y reimporta).
- El importador agrupa `stop_times` por viaje en streaming, computa `pattern_id` (hash SHA-256 estable de la secuencia de paradas y desfases) y asigna `pattern_id`/`start_secs` a cada viaje; nunca mantiene todos los horarios en memoria.
- Se adaptaron `sqflite_transit_repository`, `transit_database`, `gtfs_parser` y `local_transit_search_source` a consultar `pattern_stops` en lugar de `stop_times`.
- Se agregó la dependencia `crypto` solo para el hash estable de patrones (sin red ni tracking).
- Tests nuevos: `test/trip_patterns_test.dart` (patrones compartidos/distintos, desfases post-medianoche, importación, migración v5→v6). Total: 140 tests en verde.
- `flutter analyze` sin errores ni warnings; `dart format .` aplicado.
- Medición con feed oficial: no medido (falta acceso al feed oficial/proxy sin credenciales).

## Fase 2: detalle de línea (completa, probada con tests)

- Se creó `LineDetailsSheet` con nombre público, selector de variante, recorrido en mapa (shape o paradas), lista ordenada, horarios estimados y buses en vivo.
- Botón de favorito persistente y acceso desde búsqueda, detalle de parada y Favoritos; tocar una parada abre su detalle.
- Estados de carga, vacío, error y sin conexión implementados con localización en `es-UY` y tokens de tema.
- Se agregaron `stopsForVariant` y `upcomingDeparturesForVariant` a `TransitRepository`, `SqfliteTransitRepository` y fake.
- Tests nuevos: `test/line_details_sheet_test.dart` (selector de variante, orden de paradas, favorito, estados, buses en vivo). Total: 144 tests en verde.
- No probado: visualización en emulador y dispositivo físico.
