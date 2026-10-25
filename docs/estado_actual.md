# Estado actual del proyecto

Revisión: 2026-10-25. Se ejecutó la app debug en un emulador Android y se importó el feed oficial servido por el proxy local. No se inspeccionaron assets ni el contenido de fixtures.

## 1. Salud técnica

- `flutter analyze`: 0 errores, 0 warnings y 0 infos (`No issues found`).
- `flutter test`: 133 pruebas pasan, 0 fallan. Fallidas: ninguna.
- `git log --oneline -15`: 10 commits; los más recientes completan los arribos por parada (A3) y el detalle del planificador (B3).
- Dependencias directas de `pubspec.yaml`: `flutter` y `flutter_localizations` (SDK); `flutter_riverpod ^3.4.3`; `go_router ^18.1.1`; `shared_preferences ^2.5.6`; `material_symbols_icons ^4.2960.0`; `maplibre 0.3.7`; `geolocator 14.1.2`; `connectivity_plus ^7.3.1`; `http ^1.6.0`; `archive ^4.5.2`; `sqflite ^2.4.5`; `path ^1.9.1`; `path_provider ^2.1.6`; `flutter_local_notifications ^22.3.2`.
- Desarrollo: `flutter_test` (SDK), `flutter_lints ^6.0.0`, `sqflite_common_ffi ^2.4.5`.
- En las dependencias directas no hay SDK de publicidad, analítica ni tracking; no se auditó cada dependencia transitiva.

## 2. Estado de cada función

| Función | Estado | Archivos o clases principales | Cómo se comprobó |
|---|---|---|---|
| 1. Navegación, temas y `es-UY` | completa y probada | `app_shell.dart`, `app_router.dart`, `settings_screen.dart`, `app_es_UY.arb` | `navigation_test`, `theme_navigation_test`, `theme_preference_test` |
| 2. Mapa, teselas, atribución, controles y panel | completa y probada | `MapScreen`, `map_config.dart` | `map_config_test`, `map_screen_test`; mapa y búsqueda verificados en emulador Android |
| 3. Ubicación, permisos, estados y punto azul | completa y probada | `MapLocationController`, `GeolocatorLocationRepository` | `map_location_controller_test`; permisos en dispositivo no verificados |
| 4. GTFS, SQLite y repositorio | completa y probada (sintéticos y feed oficial en emulador) | `gtfs_parser.dart`, `transit_database.dart`, `sqflite_transit_repository.dart` | `transit_data_test`, `gtfs_performance_test`; feed oficial importado: 4.930 paradas, 325 líneas, 2.221.437 horarios y 332.505 puntos de shape |
| 5. Paradas y próximos ómnibus en el panel | completa y probada (datos sintéticos) | `MapScreen`, `StopDetailsSheet`, `_stopLayers`, `_nearbyBuses` | `map_screen_test`, `stop_details_sheet_test`; lista de paradas cercanas verificada en emulador con feed oficial |
| 6. Tiempo real: parser, matcher, HTTP, polling y mapa | completa y probada (datos sintéticos) | `stm_online_geojson_parser.dart`, `RealtimeMatcher`, `MontevideoRealtimeBusSource`, `LiveBusesController`, `MapScreen` | `montevideo_realtime_bus_source_test`, `live_buses_controller_test`, `live_bus_layer_test`, `map_screen_test`; feed oficial no verificado |
| 7. Arribos en vivo por parada | completa y probada (datos sintéticos) | `TransitArrivalsSource`, `StopDetailsSheet`, `upcomingDepartures` | `transit_data_test`, `transit_arrivals_source_test`, `stop_details_sheet_test`; ETA local calculado en el dispositivo, sin endpoint de arribos |
| 8. Detalle de parada y línea, recorrido y horarios | parcial | `StopDetailsSheet`, expansiones de parada/línea en `MapScreen` | hoja de parada con nombre, código, líneas, hasta 8 arribos y acción «Cómo llegar»; la línea solo dibuja su shape, sin hoja de detalle ni horarios por línea |
| 9. Búsqueda de lugares, paradas y líneas | parcial | `TripSearchSheet`, `LocalTransitSearchSource`, `RemoteGeocodingSource`, `RemotePlaceSearchEnabledController` | `search_controller_test`, `trip_search_sheet_test`; la búsqueda remota está apagada por defecto y solo se ejecuta tras una acción explícita. Sigue dentro del planificador, no como pantalla independiente |
| 10. Planificador, resultados y horario | parcial | `TransitTripPlanner`, `PlannerConfig`, `TripSearchSheet`, `TripPlanDetails` | `trip_planner_test`, `trip_search_sheet_test`; permite salir ahora, salir a una hora o llegar a una hora (hoy/mañana, 24 h); “llegar a las” prueba hasta 18 salidas candidatas; descarta itinerarios dominados, ordena por rápido/caminata/transbordos, ofrece «Caminar» y transbordos peatonales, y ejecuta la búsqueda en un isolate en plataformas nativas. La tarjeta muestra salida–llegada, duración, chips de línea, caminata, transbordos y etiqueta semántica; el estado vacío sugiere ampliar la caminata o cambiar la hora |
| 11. Detalle y viaje en curso/aviso de bajada | parcial | `TripPlanDetails`, capas de plan en `MapScreen` | se muestra una línea de tiempo vertical esquemática con horas estimadas, caminata aproximada y aviso de horarios programados; el mapa dibuja bus continuo, caminata punteada y origen/destino, pero no hay seguimiento activo ni aviso de bajada |
| 12. Favoritos | completa y probada (almacenamiento local) | `Favorite`, `FavoritesRepository`, `FavoritesScreen`, `favoritesControllerProvider`, `mapActionProvider` | `favorites_test`, `stop_details_sheet_test`, `map_screen_test`; guarda paradas, líneas y las ranuras Casa/Trabajo en `shared_preferences`; el mapa aún no se probó en dispositivo |
| 13. Privacidad y atribuciones | parcial | `_showAttribution` en `MapScreen`, interruptor de búsqueda remota en Ajustes, textos ARB | `map_screen_test`, `settings_transit_status_test`, `search_controller_test`; hay atribución, nota de ubicación y aviso de envío del texto, pero no una pantalla de privacidad |
| 14. Identidad visual, isotipo, ícono e Inter | parcial | `RumboLogo`, `pubspec.yaml`, recursos de plataforma | Inter local está declarada y existen archivos de icono; el isotipo es placeholder. El aspecto de los assets no se verificó |

## 3. Datos y servicios

- La app carga primero `assets/sample_gtfs/sample_gtfs.zip`, identificado por el código como sintético. En Android/iOS lo importa a SQLite. En debug, la configuración también intenta actualizar desde un proxy local; el acceso a un feed real depende de que ese proxy esté disponible y configurado. En release la URL queda vacía salvo `RUMBO_API_BASE_URL`.
- En el emulador Android se verificó la descarga y la importación del feed oficial servido por el proxy: versión 1.1, 4.930 paradas, 325 líneas, 1.089 variantes, 37.451 viajes, 2.221.437 horarios y 332.505 puntos de shape. La base resultante ocupa 168,5 MB y el proceso completo tardó alrededor de 10 minutos. La licencia y las condiciones de uso del feed para producción siguen sin confirmar.
- `lib/core/config/map_config.dart`: estilos `https://tiles.openfreemap.org/styles/positron` y `https://tiles.openfreemap.org/styles/dark`. Configurados, pero no probados en ejecución.
- `lib/core/config/transit_config.dart`: `http://10.0.2.2:8765` en Android y `http://127.0.0.1:8765` en otras plataformas (debug). Compone `/gtfs/latest`, `/api/buses?format=geojson` y `/geocode`; son rutas del proxy local, no URLs oficiales confirmadas.
- `lib/features/map/data/montevideo_realtime_bus_source.dart` compone `/buses?format=geojson` sobre la base `.../api`. El proxy del repo implementa `/api/buses`; la documentación `docs/api/montevideo_publictransport.md` describe la ruta del proxy como `/api/buses`.
- `lib/features/stops_and_lines/data/transit_arrivals_source.dart` combina `upcomingDepartures` con un ETA local por bus: proyecta la posición sobre el shape de la variante, descarta los buses que ya pasaron la parada y usa la velocidad reportada si es de 8 km/h o más, o 18 km/h por defecto. Un arribo en vivo reemplaza la próxima salida programada de su variante; si no hay bus en vivo, se conservan los horarios programados.
- `lib/features/search/presentation/search_controller.dart` conserva el fallback `http://127.0.0.1:8765/geocode`. `lib/features/search/data/remote_geocoding_source.dart` y `lib/features/trip_planner/data/open_street_map_place_source.dart` incluyen `https://github.com/mewnite/RumboAPP` solo en el encabezado User-Agent, no como destino de una petición.
- `lib/features/favorites/` guarda una lista JSON en `shared_preferences` bajo `favorites_v1`, sin red. Las paradas y líneas se identifican por su id; Casa y Trabajo usan las ranuras `place-home` y `place-work`, con nombre y coordenadas del lugar elegido. Una entrada dañada se omite al cargar sin invalidar el resto; si todo el JSON está dañado, se empieza con una lista vacía.
- En web, `web/index.html` carga `https://unpkg.com/maplibre-gl@^5.0/dist/maplibre-gl.js` y `https://unpkg.com/maplibre-gl@^5.0/dist/maplibre-gl.css`.
- El proxy de `tool/montevideo_api_proxy.py` configura `https://api.montevideo.gub.uy/api/transportepublico` como upstream de transporte; la app no lo llama directamente. El destino de geocodificación depende de `PLACE_SEARCH_URL` del proxy/`.env`, cuyo valor efectivo no se verificó. Disponibilidad y condiciones del upstream no verificadas.
- La ubicación precisa se usa para centrar el mapa y consultar la base local; la petición de teselas revela al proveedor el área aproximada visible. No se encontró envío de coordenadas en el flujo del planificador conectado. La búsqueda remota envía el texto consultado al endpoint `/geocode` configurado; el destino upstream efectivo del proxy no se verificó.
- El archivo local `.env` contiene claves `CLIENT_ID` y `CLIENT_SECRET`; está excluido por `.gitignore` y no está versionado. No se imprimieron sus valores.

## 4. Problemas y deuda

- `TODO`/`FIXME`: no se encontraron coincidencias en `lib/`, `test/` ni `docs/`.
- Los tests y el análisis no reportaron fallos. Se ejecutó la app en un emulador Android: se verificaron el mapa, la búsqueda de direcciones, la importación del feed oficial y el estado en Ajustes. Permisos de ubicación, tema oscuro, escala de fuente y un teléfono físico quedan sin verificar.
- El ETA en vivo usa la proyección sobre el shape y una velocidad de 18 km/h cuando el dato reportado es menor a 8 km/h; no se validó contra arribos oficiales ni contra el comportamiento real de la flota.
- El detalle de parada se calcula al abrirlo: no se refresca periódicamente mientras la hoja permanece visible.
- El planificador traza segmentos rectos/esquemáticos entre puntos; su propio detalle aclara que no es navegación peatonal ni ETA en vivo.
- Favoritos se guarda solo en el dispositivo: no hay sincronización entre dispositivos ni recuperación al desinstalar. El renombrado cambia únicamente el nombre visible, no las coordenadas. Además de Casa y Trabajo, el modelo admite lugares sin ranura, pero todavía no hay una acción para agregarlos desde la interfaz.
- Viaje activo y aviso de bajada no tienen flujo funcional. `privacyMessage` está localizado, pero no se encontró una pantalla que lo presente.

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
4. La búsqueda abre el panel de planificación. La búsqueda remota está apagada por defecto; se habilita en Ajustes y el texto solo se envía al tocar «Buscar lugares o direcciones».
5. Con datos disponibles, el mapa lista paradas cercanas, dibuja buses de las líneas/variantes seleccionadas o de la parada abierta (máximo 60 y solo en la zona visible) y abre el detalle de parada con sus arribos.
6. Favoritos muestra Casa y Trabajo (con «Definir» si faltan), las paradas y las líneas guardadas. Tocar un lugar abre el planificador con ese destino; tocar una línea la dibuja en el mapa; tocar una parada abre su detalle. Deslizar elimina con «Deshacer» y mantener presionado permite renombrar. Las ranuras definidas aparecen como atajos debajo de la búsqueda del mapa.
7. Ajustes permite elegir tema claro, oscuro o sistema, muestra el estado/fuente de datos y permite habilitar la búsqueda de direcciones en línea.
8. No hay pantalla de privacidad ni viaje en curso.

## 6. Qué falta, en orden de dependencias

1. Confirmar la licencia, las condiciones de uso y la vigencia del feed oficial para producción. La importación en emulador ya se verificó, pero no reemplaza esa confirmación legal/operativa.
2. Confirmar/documentar contratos, rutas y límites del proxy para GTFS, flota, geocodificación y —si existe— arribos. No hay endpoint de arribos documentado; el ETA local debe validarse con datos reales. Las rutas actuales son configurables/de desarrollo, no un contrato oficial verificado.
3. Validar en un teléfono físico el mapa, los marcadores de buses, la hoja de parada, los estados sin conexión/servicio caído y el comportamiento del polling en segundo plano.
4. Validar el matcher de variantes y el ETA local con identificadores y shapes del feed oficial. El feed ya está importado; falta contrastar el ETA contra datos reales y confirmar la frecuencia de actualización.
5. Completar el detalle de línea con recorrido y horarios; hoy solo se puede dibujar el shape de una variante.
6. Validar el planificador con el feed oficial ya importado y definir trazados peatonales fiables; hoy la caminata es una estimación en línea recta.
7. Implementar viaje activo y aviso de bajada; requiere definir el criterio/umbral del aviso, notificaciones y validación de capacidades/permisos en Android e iOS.
8. Crear una pantalla de privacidad que reúna flujos de ubicación, geocodificación y atribución; requiere confirmar proveedor y condiciones del servicio remoto.

### Preguntas para mí

1. ¿Qué feed GTFS oficial, licencia y entorno de proxy autorizás para pruebas y producción?
2. ¿Qué contrato confirmado debe usarse para buses y arribos, y qué frecuencia/ETA se permite?
3. ¿Autorizás el envío del texto de búsqueda al gateway/proveedor remoto mientras se escribe, o solo tras una acción explícita?
4. ¿Qué criterio de proximidad debe activar el aviso de bajada y aceptás notificación/ubicación en segundo plano solo durante el viaje activo?
