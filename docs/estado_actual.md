# Estado actual del proyecto

Revisión: 2026-10-25. No se inspeccionaron assets ni el contenido de fixtures. No se ejecutó la app en un emulador.

## 1. Salud técnica

- `flutter analyze`: 0 errores, 0 warnings y 0 infos (`No issues found`).
- `flutter test`: 112 pruebas pasan, 0 fallan. Fallidas: ninguna.
- `git log --oneline -15`: 7 commits; el más reciente es el de presentación de resultados y detalle del planificador (B3).
- Dependencias directas de `pubspec.yaml`: `flutter` y `flutter_localizations` (SDK); `flutter_riverpod ^3.4.3`; `go_router ^18.1.1`; `shared_preferences ^2.5.6`; `material_symbols_icons ^4.2960.0`; `maplibre 0.3.7`; `geolocator 14.1.2`; `connectivity_plus ^7.3.1`; `http ^1.6.0`; `archive ^4.5.2`; `sqflite ^2.4.5`; `path ^1.9.1`; `path_provider ^2.1.6`; `flutter_local_notifications ^22.3.2`.
- Desarrollo: `flutter_test` (SDK), `flutter_lints ^6.0.0`, `sqflite_common_ffi ^2.4.5`.
- En las dependencias directas no hay SDK de publicidad, analítica ni tracking; no se auditó cada dependencia transitiva.

## 2. Estado de cada función

| Función | Estado | Archivos o clases principales | Cómo se comprobó |
|---|---|---|---|
| 1. Navegación, temas y `es-UY` | completa y probada | `app_shell.dart`, `app_router.dart`, `settings_screen.dart`, `app_es_UY.arb` | `navigation_test`, `theme_navigation_test`, `theme_preference_test` |
| 2. Mapa, teselas, atribución, controles y panel | completa y probada | `MapScreen`, `map_config.dart` | `map_config_test`, `map_screen_test`; ejecución real no verificada |
| 3. Ubicación, permisos, estados y punto azul | completa y probada | `MapLocationController`, `GeolocatorLocationRepository` | `map_location_controller_test`; permisos en dispositivo no verificados |
| 4. GTFS, SQLite y repositorio | completa y probada (con datos sintéticos) | `gtfs_parser.dart`, `transit_database.dart`, `sqflite_transit_repository.dart` | `transit_data_test`, `gtfs_performance_test` |
| 5. Paradas y próximos ómnibus en el panel | parcial | `MapScreen`, `_stopLayers`, `_nearbyBuses` | código: dibuja paradas y lista buses cercanos; no lista arribos por parada |
| 6. Tiempo real: parser, matcher, HTTP, polling y mapa | parcial | `stm_online_geojson_parser.dart`, `RealtimeMatcher`, `MontevideoRealtimeBusSource`, `MapScreen` | `montevideo_realtime_bus_source_test`, `live_buses_controller_test`; no dibuja buses en el mapa |
| 7. Arribos en vivo por parada | parcial | `TransitArrivalsSource`, `upcomingDepartures` | existe lógica de dominio, pero no pantalla ni integración visible; no se encontró test dedicado |
| 8. Detalle de parada y línea, recorrido y horarios | parcial | expansiones de parada/línea en `MapScreen` | se puede seleccionar una variante y dibujar su shape; no hay detalle de parada/línea ni horarios visibles |
| 9. Búsqueda de lugares, paradas y líneas | parcial | `TripSearchSheet`, `LocalTransitSearchSource`, `RemoteGeocodingSource` | tests de búsqueda y de `trip_search_sheet`; está dentro del planificador, no como pantalla independiente |
| 10. Planificador, resultados y horario | parcial | `TransitTripPlanner`, `PlannerConfig`, `TripSearchSheet`, `TripPlanDetails` | `trip_planner_test`, `trip_search_sheet_test`; permite salir ahora, salir a una hora o llegar a una hora (hoy/mañana, 24 h); “llegar a las” prueba hasta 18 salidas candidatas; descarta itinerarios dominados, ordena por rápido/caminata/transbordos, ofrece «Caminar» y transbordos peatonales, y ejecuta la búsqueda en un isolate en plataformas nativas. La tarjeta muestra salida–llegada, duración, chips de línea, caminata, transbordos y etiqueta semántica; el estado vacío sugiere ampliar la caminata o cambiar la hora |
| 11. Detalle y viaje en curso/aviso de bajada | parcial | `TripPlanDetails`, capas de plan en `MapScreen` | se muestra una línea de tiempo vertical esquemática con horas estimadas, caminata aproximada y aviso de horarios programados; el mapa dibuja bus continuo, caminata punteada y origen/destino, pero no hay seguimiento activo ni aviso de bajada |
| 12. Favoritos | solo interfaz/placeholder | `FavoritesScreen` | `theme_navigation_test`; solo muestra estado vacío, no hay acción para guardar |
| 13. Privacidad y atribuciones | parcial | `_showAttribution` en `MapScreen`, textos ARB | `map_screen_test`; hay atribución y nota de ubicación, no una pantalla de privacidad |
| 14. Identidad visual, isotipo, ícono e Inter | parcial | `RumboLogo`, `pubspec.yaml`, recursos de plataforma | Inter local está declarada y existen archivos de icono; el isotipo es placeholder. El aspecto de los assets no se verificó |

## 3. Datos y servicios

- La app carga primero `assets/sample_gtfs/sample_gtfs.zip`, identificado por el código como sintético. En Android/iOS lo importa a SQLite. En debug, la configuración también intenta actualizar desde un proxy local; el acceso a un feed real depende de que ese proxy esté disponible y configurado. En release la URL queda vacía salvo `RUMBO_API_BASE_URL`. No se verificó ningún feed oficial real.
- `lib/core/config/map_config.dart`: estilos `https://tiles.openfreemap.org/styles/positron` y `https://tiles.openfreemap.org/styles/dark`. Configurados, pero no probados en ejecución.
- `lib/core/config/transit_config.dart`: `http://10.0.2.2:8765` en Android y `http://127.0.0.1:8765` en otras plataformas (debug). Compone `/gtfs/latest`, `/api/buses?format=geojson` y `/geocode`; son rutas del proxy local, no URLs oficiales confirmadas.
- `lib/features/map/data/montevideo_realtime_bus_source.dart` compone `/buses?format=geojson` sobre la base `.../api`. El proxy del repo implementa `/api/buses`; la documentación `docs/api/montevideo_publictransport.md` describe la ruta del proxy como `/api/buses`.
- `lib/features/search/presentation/search_controller.dart` conserva el fallback `http://127.0.0.1:8765/geocode`. `lib/features/search/data/remote_geocoding_source.dart` y `lib/features/trip_planner/data/open_street_map_place_source.dart` incluyen `https://github.com/mewnite/RumboAPP` solo en el encabezado User-Agent, no como destino de una petición.
- En web, `web/index.html` carga `https://unpkg.com/maplibre-gl@^5.0/dist/maplibre-gl.js` y `https://unpkg.com/maplibre-gl@^5.0/dist/maplibre-gl.css`.
- El proxy de `tool/montevideo_api_proxy.py` configura `https://api.montevideo.gub.uy/api/transportepublico` como upstream de transporte; la app no lo llama directamente. El destino de geocodificación depende de `PLACE_SEARCH_URL` del proxy/`.env`, cuyo valor efectivo no se verificó. Disponibilidad y condiciones del upstream no verificadas.
- La ubicación precisa se usa para centrar el mapa y consultar la base local; la petición de teselas revela al proveedor el área aproximada visible. No se encontró envío de coordenadas en el flujo del planificador conectado. La búsqueda remota envía el texto consultado al endpoint `/geocode` configurado; el destino upstream efectivo del proxy no se verificó.
- El archivo local `.env` contiene claves `CLIENT_ID` y `CLIENT_SECRET`; está excluido por `.gitignore` y no está versionado. No se imprimieron sus valores.

## 4. Problemas y deuda

- `TODO`/`FIXME`: no se encontraron coincidencias en `lib/`, `test/` ni `docs/`.
- Los tests y el análisis no reportaron fallos. No se ejecutó la app en dispositivo; fallos de red, mapas o permisos en ejecución quedan no verificados.
- El punto débil funcional más claro: el panel del mapa muestra buses próximos en una lista, no como marcadores. La posición en vivo tampoco se transforma en ETA.
- `TransitArrivalsSource` asigna `now` a la hora de un bus en vivo; no calcula una hora estimada de llegada. No está conectado a una vista.
- `TripSearchSheet._search` llama a `searchService.search()` con `allowRemote` predeterminado (`true`); con feed oficial y consulta de 3+ caracteres puede enviar el texto al geocodificador mientras se escribe. El aviso ARB dice que se envía al tocar “Buscar lugares o direcciones”, por lo que el momento del envío no coincide con el copy.
- El planificador traza segmentos rectos/esquemáticos entre puntos; su propio detalle aclara que no es navegación peatonal ni ETA en vivo.
- Favoritos, viaje activo y aviso de bajada no tienen flujo funcional. `privacyMessage` está localizado, pero no se encontró una pantalla que lo presente.

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

Al abrir (comportamiento esperado según código; dispositivo no verificado):
1. Mapa centrado en Montevideo, barra de búsqueda, botón de ubicación y atribución.
2. Panel inferior “Paradas y ómnibus”; sin proxy disponible muestra estado/error de datos oficiales y sugerencia de proxy.
3. La ubicación solo se solicita al tocar el control y aceptar la explicación.
4. La búsqueda abre el panel de planificación; lugares remotos requieren endpoint disponible.
5. Con feed oficial, el mapa lista paradas cercanas y permite expandir líneas/variantes.
6. Favoritos muestra el estado vacío.
7. Ajustes permite elegir tema claro, oscuro o sistema y muestra el estado/fuente de datos.
8. No hay pantalla de privacidad, arribos por parada ni viaje en curso.

## 6. Qué falta, en orden de dependencias

1. Confirmar feed GTFS oficial, licencia, vigencia y proxy desplegable. Sin datos reales no hay paradas, líneas ni horarios de servicio verificados.
2. Confirmar/documentar contratos, rutas y límites del proxy para GTFS, flota, geocodificación y —si existe— arribos. Las rutas actuales son configurables/de desarrollo, no un contrato oficial verificado.
3. Con el GTFS real, completar presentación de paradas cercanas y arribos por parada. Para arribos en vivo hacen falta ETA o una decisión explícita sobre qué significa mostrar un bus detectado en la variante.
4. Completar detalle de parada y línea con horarios y recorrido. Depende de identificadores, shapes y horarios válidos del feed.
5. Dibujar buses sobre el mapa y validar el matcher con identificadores oficiales de variante; hoy el polling solo alimenta el panel/lista.
6. Completar el planificador con selección de hora de llegada y trazados de caminata fiables; necesita horarios GTFS validados y, para rutas a pie, una fuente/decisión de enrutamiento.
7. Implementar viaje activo y aviso de bajada; requiere definir el criterio/umbral del aviso, notificaciones y validación de capacidades/permisos en Android e iOS.
8. Implementar favoritos persistidos y controles para guardar; falta decidir qué entidades se pueden guardar (paradas, lugares, líneas o viajes).
9. Crear una pantalla de privacidad que reúna flujos de ubicación, geocodificación y atribución; requiere confirmar proveedor y condiciones del servicio remoto.

### Preguntas para mí

1. ¿Qué feed GTFS oficial, licencia y entorno de proxy autorizás para pruebas y producción?
2. ¿Qué contrato confirmado debe usarse para buses y arribos, y qué frecuencia/ETA se permite?
3. ¿Autorizás el envío del texto de búsqueda al gateway/proveedor remoto mientras se escribe, o solo tras una acción explícita?
4. ¿Qué se podrá guardar en Favoritos: paradas, lugares, líneas, viajes o una combinación?
5. ¿Qué criterio de proximidad debe activar el aviso de bajada y aceptás notificación/ubicación en segundo plano solo durante el viaje activo?
