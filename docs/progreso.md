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

## Fase 3: variantes oficiales y arribos oficiales (diagnóstico completado)
- El API/proxy documenta `lineVariantId` en buses y variantes, pero no un mapeo validado a `trip_id`/`shape_id` del GTFS.
- No se genera `variant_map.csv` ni se emparejan variantes por texto; faltan fixtures oficiales para probar ese cruce.
- El proxy reenvía `upcomingbuses`, pero docs/api no describe su respuesta; no se implementa cliente ni se consulta desde la app.
- Se mantiene ETA local aproximado por shape; dependencia pendiente de contrato documentado y datos de prueba autorizados.
- Pruebas manuales con servicios reales: no realizadas.

## Prioridad: mapa, paradas, buses y destinos (completa)
- El mapa dibuja las posiciones de buses visibles de la API aunque todavía no se haya elegido una línea; al cargar el GTFS limita además a las líneas de las paradas del área y mantiene el tope de marcadores.
- Abrir una ficha de parada recalcula los arribos cuando llega una nueva actualización de posiciones; horarios GTFS continúan rotulados como estimados.
- La búsqueda remota del proxy acepta nombres de POIs; las sugerencias muestran el nombre corto cuando el geocodificador lo proporciona y solo se consulta al tocar «Buscar lugares o direcciones» con la opción habilitada.
- Se agregó prueba de la búsqueda «Shopping Nuevo Centro» con cliente HTTP falso y de buses visibles sin selección de línea.
- Verificado: proxy local responde en `/health`; estilos OpenFreeMap claro/oscuro y runtime MapLibre responden HTTP 200; `flutter run -d chrome` conectó la app.
- Unit/widget tests: 150 en verde; `flutter analyze`: sin issues. Emulador Android/iOS no disponible para esta validación.

## Fase 4: privacidad y datos locales (completa)
- Se agregó pantalla de privacidad con explicación de red/ubicación, atribución, licencias y controles de geocodificación explícita y buses en vivo.
- El control de buses persiste; al desactivarlo detiene el polling, descarta respuestas pendientes y borra posiciones en memoria.
- La acción de limpiar datos elimina favoritos, búsquedas recientes y caché ambiente del mapa; no borra preferencias de tema.
- Sin dependencias nuevas; la ubicación precisa sigue en el dispositivo y las búsquedas remotas requieren consentimiento y acción por consulta.
- Tests específicos: preferencia de buses entre aperturas, descarte de fetch al desactivar y borrado local/cache; conjunto total: 150 en verde.

## Fase 5: viaje activo y aviso de bajada (implementado; validación física pendiente)
- Un plan con variante GTFS permite iniciar seguimiento desde su detalle; la ubicación se solicita solo al tocar «Iniciar viaje con avisos» y requiere permiso en segundo plano y notificaciones.
- Geolocator usa ubicación procesada solo en el dispositivo: Android mantiene servicio/notificación persistente y actualiza paradas restantes; iOS usa Location Updates y avisos locales.
- El aviso se activa al estar a 300 m del destino o quedar a dos paradas, lo que ocurra primero; el contador usa el orden de paradas de la variante.
- «Finalizar viaje», cambiar recorrido o cerrar el detalle cancela la suscripción y las notificaciones; al desactivar servicios se detiene.
- Sin dependencias nuevas: se reutilizan `geolocator` y `flutter_local_notifications`. No se envía ubicación al proxy ni a geocodificación.
- Unit/widget tests: 150 en verde; `flutter analyze` sin issues; APK debug Android compilado y `flutter run -d chrome` conectado. No probado en dispositivo físico ni iOS. Chrome muestra avisos de recursos opcionales del estilo MapLibre (PMTiles/imagen `wood-pattern`); queda pendiente confirmar visualmente teselas y marcadores en un navegador.
