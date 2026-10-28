# Estado actual del proyecto

Revisión: 2026-10-27. La versión anterior se instaló en el emulador con el proxy activo: el GTFS terminó de importarse sin error, creó una base de 198 MB en unos 3 minutos y mostró paradas cercanas. Esto reprodujo el error anterior: patrones idénticos se insertaban varias veces y SQLite rechazaba la clave primaria. La revisión actual conserva esas correcciones; ya se instaló en Android sin borrar su base. Falta medir importación y planificación en ese emulador, donde el primer render del mapa todavía reportó cuadros omitidos.

En esta revisión se redujo el trabajo del planificador: consulta horarios solo para las ocho paradas más cercanas a cada extremo, filtra viajes por calendario y ventana horaria, inicia desde salidas posibles del origen y usa búsquedas acotadas por hora para transbordos. Una medición de extremo a extremo con el feed oficial guardado en una base temporal, para Montevideo Shopping → Nuevo Centro y salida programada, devolvió cuatro opciones en 4,1 s en el equipo de desarrollo. La importación SQLite agrupa registros y espera únicamente al confirmar cada lote; en el mismo equipo, analizar e importar 4.920 paradas, 37.445 viajes y 2.221.190 horarios llevó 9,6 s + 13,9 s (23,5 s total). Ninguna de estas mediciones representa Android: la referencia de ~3 min es de una implementación anterior y todavía falta repetir ambas pruebas en el emulador o teléfono.

## 1. Salud técnica

- `flutter analyze`: 0 errores, 0 warnings y 0 infos (`No issues found`).
- `flutter test`: 162 pruebas pasan, 0 fallan. Fallidas: ninguna.
- `git log --oneline -15`: 10 commits; los más recientes completan los arribos por parada (A3) y el detalle del planificador (B3).
- Dependencias directas de `pubspec.yaml`: `flutter` y `flutter_localizations` (SDK); `flutter_riverpod ^3.4.3`; `go_router ^18.1.1`; `shared_preferences ^2.5.6`; `material_symbols_icons ^4.2960.0`; `maplibre 0.3.7`; `geolocator 14.1.2`; `connectivity_plus ^7.3.1`; `http ^1.6.0`; `archive ^4.5.2`; `sqflite ^2.4.5`; `path ^1.9.1`; `path_provider ^2.1.6`; `flutter_local_notifications ^22.3.2`.
- Desarrollo: `flutter_test` (SDK), `flutter_lints ^6.0.0`, `sqflite_common_ffi ^2.4.5`.
- En las dependencias directas no hay SDK de publicidad, analítica ni tracking; no se auditó cada dependencia transitiva.

## 2. Estado de cada función

| Función | Estado | Archivos o clases principales | Cómo se comprobó |
|---|---|---|---|
| 1. Navegación, temas y `es-UY` | completa y probada | `app_shell.dart`, `app_router.dart`, `settings_screen.dart`, `app_es_UY.arb` | `navigation_test`, `theme_navigation_test`, `theme_preference_test` |
| 2. Mapa, teselas, atribución, controles y panel | implementado; falta inspección visual web | `MapScreen`, `map_config.dart` | `map_config_test`, `map_screen_test`; Chrome inicia, pero su consola informa recursos opcionales del estilo no cargados |
| 3. Ubicación, permisos, estados y punto azul | completa y probada | `MapLocationController`, `GeolocatorLocationRepository` | `map_location_controller_test`; permisos en dispositivo no verificados |
| 4. GTFS, SQLite y repositorio | completa y probada (sintéticos y feed oficial en emulador) | `gtfs_parser.dart`, `transit_database.dart`, `sqflite_transit_repository.dart` | `transit_data_test`, `gtfs_performance_test`; feed oficial importado: 4.930 paradas, 325 líneas, 2.221.437 horarios y 332.505 puntos de shape |
| 5. Paradas y próximos ómnibus en el panel | completa y probada (datos sintéticos) | `MapScreen`, `StopDetailsSheet`, `_stopLayers`, `_nearbyBuses` | `map_screen_test`, `stop_details_sheet_test`; lista de paradas cercanas verificada en emulador con feed oficial |
| 6. Tiempo real: parser, matcher, HTTP, polling y mapa | completa y probada (datos sintéticos) | `stm_online_geojson_parser.dart`, `RealtimeMatcher`, `MontevideoRealtimeBusSource`, `LiveBusesController`, `MapScreen` | `montevideo_realtime_bus_source_test`, `live_buses_controller_test`, `live_bus_layer_test`, `map_screen_test`; feed oficial no verificado |
| 7. Arribos en vivo por parada | parcial; endpoint oficial pendiente de verificar payload | `TransitArrivalsSource`, `StopDetailsSheet`, `upcomingDepartures` | `transit_data_test`, `transit_arrivals_source_test`, `stop_details_sheet_test`; ETA local aproximado. La API publica `upcomingbuses`, pero el esquema accesible no identifica campo/unidad del ETA |
| 8. Detalle de parada y línea, recorrido y horarios | completa en código | `StopDetailsSheet`, `LineDetailsSheet`, `MapScreen` | hoja de parada y detalle de línea con variante, paradas ordenadas, horario estimado y buses observados; ver `line_details_sheet_test` y `stop_details_sheet_test` |
| 9. Búsqueda de lugares, paradas y líneas | búsqueda integrada al escribir, con consentimiento inicial para geocodificación | `TripSearchSheet`, `SearchDestinationSheet`, `LocalTransitSearchSource`, `RemoteGeocodingSource` | `search_controller_test`, `trip_search_sheet_test`; GTFS y lugares se combinan sin botón adicional cuando la búsqueda en línea está habilitada |
| 10. Planificador, resultados y horario | implementado; datos y trazados requieren validación real | `TransitTripPlanner`, `PlannerConfig`, `TripSearchSheet`, `TripPlanDetails` | `trip_planner_test`, `trip_search_sheet_test`; permite salir ahora, salir a una hora o llegar a una hora (hoy/mañana, 24 h); “llegar a las” prueba hasta 18 salidas candidatas; descarta itinerarios dominados, ordena por rápido/caminata/transbordos, ofrece «Caminar» y transbordos peatonales, y ejecuta la búsqueda en un isolate en plataformas nativas. La tarjeta muestra salida–llegada, duración, chips de línea, caminata, transbordos y etiqueta semántica |
| 11. Detalle y viaje en curso/aviso de bajada | implementado; falta validación física | `TripPlanDetails`, `ActiveTripController`, `ActiveTripTracker`, notificaciones locales | inicia con acción explícita, seguimiento local en segundo plano y aviso a 300 m o dos paradas; ver `active_trip_controller_test` y `active_trip_tracker_test` |
| 12. Favoritos | completa y probada (almacenamiento local) | `Favorite`, `FavoritesRepository`, `FavoritesScreen`, `favoritesControllerProvider`, `mapActionProvider` | `favorites_test`, `stop_details_sheet_test`, `map_screen_test`; guarda paradas, líneas y las ranuras Casa/Trabajo en `shared_preferences`; el mapa aún no se probó en dispositivo |
| 13. Privacidad y atribuciones | implementada en código; faltan comprobaciones de proveedor/dispositivo | pantalla de privacidad, `_showAttribution`, preferencias y textos ARB | controles para búsqueda remota y buses en vivo, limpieza local, explicación de ubicación y fuentes; la consulta remota requiere consentimiento y nunca envía GPS |
| 14. Identidad visual, isotipo, ícono e Inter | parcial | `RumboLogo`, `pubspec.yaml`, recursos de plataforma | Inter local está declarada y existen archivos de icono; el isotipo es placeholder. El aspecto de los assets no se verificó |

## 3. Datos y servicios

- La app no carga datos sintéticos por defecto. Android/iOS reutilizan un GTFS oficial cacheado en SQLite y, si no hay uno, intentan descargarlo desde el proxy configurado. Chrome mantiene el GTFS oficial compacto en memoria, ya que `sqflite` no funciona en web. El feed sintético solo se carga con `--dart-define=RUMBO_DEMO_MODE=true`.
- En el emulador Android se verificó la descarga y la importación del feed oficial servido por el proxy: versión 1.1, 4.930 paradas, 325 líneas, 1.089 variantes, 37.451 viajes, 2.221.437 horarios y 332.505 puntos de shape. La versión anterior tardó alrededor de 3 minutos y produjo una base de 198 MB; cambios posteriores eliminan trabajo redundante y falta medirlos desde cero. La licencia y las condiciones de uso del feed para producción siguen sin confirmar.
- `lib/core/config/map_config.dart`: estilos `https://tiles.openfreemap.org/styles/positron` y `https://tiles.openfreemap.org/styles/dark`. Configurados, pero no probados en ejecución.
- `lib/core/config/transit_config.dart`: `http://10.0.2.2:8765` en Android y `http://127.0.0.1:8765` en otras plataformas (debug). Compone `/gtfs/latest`, `/api/buses?format=geojson` y `/geocode`; son rutas del proxy local, no URLs oficiales confirmadas.
- `lib/features/map/data/montevideo_realtime_bus_source.dart` compone `/buses?format=geojson` sobre la base `.../api`. El proxy del repo implementa `/api/buses`; la documentación `docs/api/montevideo_publictransport.md` describe la ruta del proxy como `/api/buses`.
- `lib/features/stops_and_lines/data/transit_arrivals_source.dart` combina horarios GTFS con una proyección local de las posiciones observadas: proyecta cada bus sobre el shape de la variante y estima su llegada usando su velocidad reportada o una velocidad de respaldo. Esa proyección no equivale al ETA oficial de la API. La app aún no interpreta `upcomingbuses` porque el esquema público de respuesta no identifica los campos de ETA.
- `lib/features/search/presentation/search_controller.dart` conserva el fallback `http://127.0.0.1:8765/geocode`. `lib/features/search/data/remote_geocoding_source.dart` y `lib/features/trip_planner/data/open_street_map_place_source.dart` incluyen `https://github.com/mewnite/RumboAPP` solo en el encabezado User-Agent, no como destino de una petición.
- `lib/features/favorites/` guarda una lista JSON en `shared_preferences` bajo `favorites_v1`, sin red. Las paradas y líneas se identifican por su id; Casa y Trabajo usan las ranuras `place-home` y `place-work`, con nombre y coordenadas del lugar elegido. Una entrada dañada se omite al cargar sin invalidar el resto; si todo el JSON está dañado, se empieza con una lista vacía.
- En web, `web/index.html` carga `https://unpkg.com/maplibre-gl@^5.0/dist/maplibre-gl.js` y `https://unpkg.com/maplibre-gl@^5.0/dist/maplibre-gl.css`.
- El proxy de `tool/montevideo_api_proxy.py` configura `https://api.montevideo.gub.uy/api/transportepublico` como upstream de transporte; la app no lo llama directamente. El destino de geocodificación depende de `PLACE_SEARCH_URL` del proxy/`.env`, cuyo valor efectivo no se verificó. Disponibilidad y condiciones del upstream no verificadas.
- La ubicación precisa se usa para centrar el mapa y consultar la base local; la petición de teselas revela al proveedor el área aproximada visible. No se encontró envío de coordenadas en el flujo del planificador conectado. La búsqueda remota envía el texto consultado al endpoint `/geocode` configurado; el destino upstream efectivo del proxy no se verificó.
- El archivo local `.env` contiene claves `CLIENT_ID` y `CLIENT_SECRET`; está excluido por `.gitignore` y no está versionado. No se imprimieron sus valores.

## 4. Problemas y deuda

- `TODO`/`FIXME`: no se encontraron coincidencias en `lib/`, `test/` ni `docs/`.
- La versión anterior se verificó en el emulador: el GTFS oficial terminó de cargar y aparecieron paradas; falta verificar los buses que devolvió el proxy. HTTP 200 por sí solo no confirma posiciones válidas dentro del área visible.
- Si el planificador se abre antes de que Riverpod emita su primer estado, espera el resultado real del GTFS y no dispara la excepción genérica de “GTFS no disponible”. Los errores de red/parser se preservan con su diagnóstico.
- El parser deduplica por `pattern_id`; antes se fallaba con `UNIQUE constraint failed: trip_patterns.pattern_id` porque se comparaba identidad de objetos. Se agregó una prueba SQLite con dos viajes del mismo patrón.
- La importación nativa usa patrones ya calculados y omite el JSONL duplicado de 2.221.437 filas. Reporta avance y desactiva journaling solo en la base temporal, que reemplaza la vigente al terminar.
- La importación y el planificador se optimizaron en código; falta medir el tiempo de extremo a extremo en Android y el tiempo de una planificación con el feed real. La base del emulador no se borró.
- La revisión anterior se ejecutó en un emulador Android y verificó el mapa, búsqueda de direcciones e importación del feed oficial. Permisos de ubicación, tema oscuro, escala de fuente y un teléfono físico quedan sin verificar en esta revisión.
- El ETA en vivo usa la proyección sobre el shape y una velocidad de 18 km/h cuando el dato reportado es menor a 8 km/h; no se validó contra arribos oficiales ni contra el comportamiento real de la flota.
- El detalle de parada actualiza sus arribos locales cuando se refrescan las posiciones observadas; el cálculo ETA local no equivale a una llegada oficial ni validada.
- El planificador traza segmentos rectos/esquemáticos entre puntos; su propio detalle aclara que no es navegación peatonal ni ETA en vivo.
- Favoritos se guarda solo en el dispositivo: no hay sincronización entre dispositivos ni recuperación al desinstalar. El renombrado cambia únicamente el nombre visible, no las coordenadas. Además de Casa y Trabajo, el modelo admite lugares sin ranura, pero todavía no hay una acción para agregarlos desde la interfaz.
- No hay teléfono físico para validar permisos “Siempre”, servicio persistente, notificaciones o aviso de bajada. El emulador Android sí está disponible.

## 5. Cómo probarlo

Desde la raíz del proyecto:

```sh
flutter pub get
flutter run
flutter run -d chrome
flutter analyze
flutter test
dart format .
```

Para una fuente real en debug, el README indica iniciar `python tool/montevideo_api_proxy.py`; en teléfono USB requiere `adb reverse tcp:8765 tcp:8765` y `--dart-define=RUMBO_API_BASE_URL=http://127.0.0.1:8765`. El proxy y sus credenciales son solo de desarrollo.

Al abrir (comportamiento verificado en emulador Android):
1. Mapa centrado en Montevideo, barra de búsqueda, botón de ubicación y atribución.
2. Panel inferior “Paradas y ómnibus”; sin proxy disponible muestra estado/error de datos oficiales y sugerencia de proxy.
3. La ubicación solo se solicita al tocar el control y aceptar la explicación.
4. La búsqueda abre el panel de planificación. La búsqueda remota está apagada por defecto; al escribir un nombre de lugar, Rumbo pide consentimiento una vez y luego mezcla lugares con paradas y líneas sin botón adicional.
5. Con datos disponibles, el mapa lista paradas cercanas y dibuja hasta 60 buses visibles de la API; antes de elegir filtros muestra los buses del área y, con GTFS cargado, prioriza líneas de las paradas cercanas. Abre el detalle de parada con arribos calculados localmente.
6. Favoritos muestra Casa y Trabajo (con «Definir» si faltan), las paradas y las líneas guardadas. Tocar un lugar abre el planificador con ese destino; tocar una línea la dibuja en el mapa; tocar una parada abre su detalle. Deslizar elimina con «Deshacer» y mantener presionado permite renombrar. Las ranuras definidas aparecen como atajos debajo de la búsqueda del mapa.
7. Ajustes permite elegir tema claro, oscuro o sistema, muestra el estado/fuente de datos y permite habilitar la búsqueda de direcciones en línea.
8. La pantalla de privacidad permite gestionar búsqueda remota, buses en vivo y datos locales; el detalle del plan permite iniciar o finalizar un viaje activo con avisos.

## 6. Qué falta, en orden de dependencias

1. Confirmar la licencia, las condiciones de uso y la vigencia del feed oficial para producción. La importación en emulador ya se verificó, pero no reemplaza esa confirmación legal/operativa.
2. Verificar con una respuesta oficial autorizada el payload de `upcomingbuses`, en especial campo/unidad del ETA, y el límite de consultas asignado a esta cuenta. La documentación oficial describe endpoint y filtros pero el modelo de respuesta publicado es incompleto para implementarlo sin adivinar.
3. Validar en un teléfono físico el mapa, los marcadores de buses, la hoja de parada, los estados sin conexión/servicio caído y el comportamiento del polling en segundo plano.
4. Validar el matcher de variantes y el ETA local con identificadores y shapes del feed oficial. El feed ya está importado; falta contrastar el ETA contra datos reales y confirmar la frecuencia de actualización.
5. Validar el detalle de línea, la hoja de parada y los horarios en un dispositivo con datos del feed oficial.
6. Validar el planificador con el feed oficial ya importado y definir trazados peatonales fiables; hoy la caminata es una estimación en línea recta.
7. Validar viaje activo, permisos, notificaciones y aviso de bajada en un Android físico y en iOS; hoy solo está compilado Android y probado con dobles.
8. Validar en dispositivo los controles de privacidad, la atribución y las condiciones del geocodificador configurado.

### Preguntas para mí

1. ¿Qué feed GTFS oficial, licencia y entorno de proxy autorizás para pruebas y producción?
2. ¿Qué contrato confirmado debe usarse para buses y arribos, y qué frecuencia/ETA se permite?
3. Para producción: ¿qué proveedor de búsqueda remota y condiciones de uso aprobás? La búsqueda permanece apagada hasta que la persona la habilita y acepta el consentimiento inicial.
