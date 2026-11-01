# Progreso

## Línea base de optimización (completa)
- Medidos APK release split: 27,9 MB armeabi-v7a, 32,9 MB arm64-v8a y 34,6 MB x86_64.
- Medido análisis arm64: `lib` 48,45 MB, assets 0,96 MB y fuentes Inter 783,6 KB.
- La base GTFS, arranque, memoria, fluidez, reconstrucciones y consumo de red quedan no medidos por falta de sesión conectada.
- El comando combinado `--split-per-abi --analyze-size` no es compatible con el Flutter instalado; se documentó el equivalente ejecutable.

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
- La API oficial documenta `upcomingbuses` como buses próximos/ETA y los filtros de línea, pero el esquema visible no expone los campos ni unidad del ETA; se mantiene pendiente el parser hasta tener respuesta autorizada. Se corrigió la documentación local con el contrato público disponible.
- Se mantiene ETA local aproximado por shape; dependencia pendiente de contrato documentado y datos de prueba autorizados.
- Pruebas manuales con servicios reales: no realizadas.

## Prioridad: mapa, paradas, buses y destinos (completa)
- El mapa dibuja todas las posiciones aceptadas dentro del área visible; solo filtra por línea cuando la persona selecciona una línea y mantiene el tope de marcadores.
- Abrir una ficha de parada recalcula los arribos cuando llega una nueva actualización de posiciones; horarios GTFS continúan rotulados como estimados.
- La búsqueda remota del proxy acepta nombres de POIs; las sugerencias muestran el nombre corto cuando el geocodificador lo proporciona. Al habilitar búsquedas en línea, lugares y transporte se consultan juntos al escribir.
- Se agregó prueba de la búsqueda «Shopping Nuevo Centro» con cliente HTTP falso y de buses visibles sin selección de línea.
- Verificado: proxy local responde en `/health`; estilos OpenFreeMap claro/oscuro y runtime MapLibre responden HTTP 200; `flutter run -d chrome` conectó la app.
- Unit/widget tests: 150 en verde; `flutter analyze`: sin issues. Emulador Android/iOS no disponible para esta validación.

## Fase 4: privacidad y datos locales (completa)
- Se agregó pantalla de privacidad con explicación de red/ubicación, atribución, licencias y controles de geocodificación explícita y buses en vivo.
- El control de buses persiste; al desactivarlo detiene el polling, descarta respuestas pendientes y borra posiciones en memoria.
- La acción de limpiar datos elimina favoritos, búsquedas recientes y caché ambiente del mapa; no borra preferencias de tema.
- Sin dependencias nuevas; la ubicación precisa sigue en el dispositivo y las búsquedas remotas requieren consentimiento inicial.
- Tests específicos: preferencia de buses entre aperturas, descarte de fetch al desactivar y borrado local/cache; conjunto total: 150 en verde.

## Fase 5: viaje activo y aviso de bajada (implementado; validación física pendiente)
- Un plan con variante GTFS permite iniciar seguimiento desde su detalle; la ubicación se solicita solo al tocar «Iniciar viaje con avisos» y requiere permiso en segundo plano y notificaciones.
- Geolocator usa ubicación procesada solo en el dispositivo: Android mantiene servicio/notificación persistente y actualiza paradas restantes; iOS usa Location Updates y avisos locales.
- El aviso se activa al estar a 300 m del destino o quedar a dos paradas, lo que ocurra primero; el contador usa el orden de paradas de la variante.
- «Finalizar viaje», cambiar recorrido o cerrar el detalle cancela la suscripción y las notificaciones; al desactivar servicios se detiene.
- Sin dependencias nuevas: se reutilizan `geolocator` y `flutter_local_notifications`. No se envía ubicación al proxy ni a geocodificación.
- Unit/widget tests: 150 en verde; `flutter analyze` sin issues; APK debug Android compilado y `flutter run -d chrome` conectado. No probado en dispositivo físico ni iOS. Chrome muestra avisos de recursos opcionales del estilo MapLibre (PMTiles/imagen `wood-pattern`); queda pendiente confirmar visualmente teselas y marcadores en un navegador.

## Corrección web: feed real y búsqueda de destinos
- La app dejaba visible el GTFS sintético al no tener proxy, y las consultas web usaban SQLite, que no está disponible en Chrome; esto impedía buscar paradas y calcular recorridos con el feed descargado.
- El demo ahora requiere `RUMBO_DEMO_MODE=true`. En el flujo normal se consulta GTFS por el proxy y se muestra el estado sin conexión si no responde.
- Chrome mantiene los patrones GTFS compactos en memoria y los usa en mapa, búsqueda local, detalle de parada/línea y planificador; Android/iOS siguen con SQLite.
- El acceso a POIs pide consentimiento antes de enviar consultas; puede usarse aunque el feed aún no esté listo.
- El proxy local atiende CORS para `localhost`, `127.0.0.1` y `::1` en HTTP, para permitir Flutter web desde un puerto de desarrollo; no habilita orígenes externos.
- El proxy puede arrancar sin credenciales STM para que la búsqueda de shoppings/terminales funcione; el feed y los buses muestran error de autenticación hasta configurar el acceso.
- Verificación: 151 tests Flutter, 10 tests del proxy, `flutter analyze` sin issues y `flutter run -d chrome` conectado. No se inició el proxy con credenciales durante esta corrección.

## Corrección de datos, búsqueda y modo oscuro
- El GTFS cacheado en SQLite se reconoce como utilizable aunque no exista una copia parseada en memoria; el mapa y el planificador consultan el repositorio en disco sin volver a declarar el feed ausente.
- La búsqueda de destinos combina paradas, líneas y lugares en línea al escribir; el botón separado se quitó y el primer uso pide consentimiento antes de transmitir el texto.
- Sin una línea seleccionada, el mapa muestra todos los buses válidos dentro del área visible; el panel indica cuántos marcadores recibió para distinguir falta de posiciones de filtros o encuadre.
- Los componentes compartidos, formularios, marcadores y trayectos usan colores del tema para responder al modo oscuro.
- La importación inicial devuelve el estado de error con su diagnóstico en vez de convertirlo en un `AsyncError` y perderlo para el planificador; las búsquedas esperan a que termine el feed.
- El mapa vuelve a consultar el área visible cuando termina de cargar el estilo, para que la primera respuesta de buses se filtre/renderice aunque la persona no mueva el mapa.
- En emulador se reprodujo el fallo `UNIQUE constraint failed: trip_patterns.pattern_id`: distintos objetos compartían el mismo ID de patrón. El parser ahora deduplica por id, cubierto por prueba SQLite con dos viajes.
- Una búsqueda iniciada antes del primer estado del proveedor espera el feed; los errores conservan el diagnóstico en lugar del mensaje genérico.
- La importación usa patrones calculados, no genera/recorre otro JSONL de 2,2 millones de filas, muestra avance y desactiva journaling en el archivo temporal descartable.
- La versión anterior completó la importación oficial (4.930 paradas) y mostró paradas en el emulador en ~3 minutos. Falta validar con una instalación limpia los cambios finales de rendimiento/avance; 161 tests y `flutter analyze` pasan.

## Fase 1: peso de la app (completa)
- R8 y `shrinkResources` quedaron activados; el build release split con ofuscación terminó correctamente.
- APK medidos: 26,3 MB armeabi-v7a, 31,5 MB arm64-v8a y 33,3 MB x86_64.
- El objetivo de -25 % no se alcanza por el peso nativo de MapLibre; quedó documentada la meta realista.
- `flutter analyze` sin issues y `flutter test`: 184 tests en verde.
