# Decisiones técnicas de la base Rumbo

- `flutter_riverpod` — administra el estado compartido y conecta Ajustes con el repositorio de preferencias.
- `go_router` — conserva estado independiente para las tres pestañas mediante navegación con ramas.
- `shared_preferences` — persiste la preferencia de apariencia, que es un dato local pequeño y no sensible.
- `material_symbols_icons` — aporta Material Symbols redondeados como fuente incluida, sin solicitudes de red.
- `flutter_localizations` (SDK) — ofrece las delegaciones oficiales para la interfaz `es-UY` generada desde archivos ARB.
- `flutter_test` (SDK) — permite verificar widgets, contraste, persistencia y navegación sin sumar un framework externo.
- `flutter_lints` — mantiene las reglas de análisis recomendadas por Flutter en desarrollo.
- Inter 4.1 en TTF local con licencia OFL — mantiene la tipografía disponible sin descargar fuentes en ejecución.
- El tema claro usa `surfaceGray` para el fondo, blanco para superficies y `deepBlue` para la acción primaria.
- `mint` ajusta un canal del token original `lime` para que el texto `deepBlue` supere AA; `lime` conserva el color de identidad y usa texto `ink`.
- El widget `LineChip` compara blanco, `deepBlue` e `ink` y elige el que ofrece más contraste para el fondo recibido.
- La selección de apariencia se guarda por nombre de `ThemeMode`; si falta o es inválido, se usa el tema del sistema.
- El isotipo SVG definitivo no estaba en el repositorio; `RumboLogo` muestra un símbolo de ruta provisional.
- La muestra de paleta y tipografía solo se registra y se enlaza en builds de debug.
- No se agregaron dependencias de anuncios, analíticas, tracking, identificadores publicitarios ni fuentes remotas.
- `maplibre` 0.3.7 — renderiza estilos vectoriales en Android, iOS y web; se eligió frente a `maplibre_gl` por su API de caché ambiental con tope en bytes, necesaria para limitar el almacenamiento local. Es una reescritura reciente y requiere validar los toolchains nativos al actualizarlo ([paquete y plataformas](https://pub.dev/packages/maplibre), [alternativa](https://pub.dev/packages/maplibre_gl)).
- `geolocator` — solicita ubicación en primer plano por acción explícita y ofrece seguimiento en segundo plano solo durante un viaje activo iniciado por la persona; las coordenadas se procesan localmente.
- `flutter_local_notifications` — reutiliza las notificaciones locales existentes para mostrar progreso y aviso de bajada; no se agregó un SDK de tracking.
- `connectivity_plus` — informa desconexión para presentar el estado offline; no registra ni envía telemetría.
- `OpenFreeMap` — proveedor vectorial sin clave y con estilos claro/oscuro; sus términos públicos ofrecen el servicio “as-is”, sin SLA, y permiten interrumpirlo. No fijan un máximo de solicitudes de visualización, pero las descargas offline sí se limitan a 3.000 teselas o 50 MB por descarga, hasta 4 solicitudes en paralelo y User-Agent que identifique la app ([términos](https://openfreemap.org/tos/)). Es la opción configurada por ser más adecuada para publicar que el servidor comunitario raster, aunque no garantiza disponibilidad para una operación grande.
- `OpenStreetMap Carto` (`tile.openstreetmap.org`) — alternativa raster para desarrollo con atribución visible. Su política exige User-Agent identificado, Referer web, caché de al menos 7 días si no hay cabeceras, prohíbe descargas masivas/prefetch, puede bloquear el uso y no ofrece SLA ([política](https://operations.osmfoundation.org/policies/tiles/)); por eso no se publica como proveedor predeterminado.
- Las teselas son datos de OpenStreetMap y OpenMapTiles; la atribución accesible aparece en el mapa y en su panel de información. El origen, estilo, atribución, centro y zoom están centralizados en `lib/core/config/map_config.dart`.
- El modo oscuro usa el estilo oscuro ofrecido por el mismo proveedor. En web, la integración requiere MapLibre GL JS/CSS cargados por la página; las fuentes de texto Inter permanecen locales.
- Se limita la caché ambiental nativa a 50 MiB cuando la plataforma implementa el `OfflineManager`; web utiliza su caché del navegador. No se descargan regiones ni áreas completas.
- Para centrar el mapa, el permiso foreground se solicita después de aceptar una explicación. El viaje activo es la única función que pide ubicación `Always`/segundo plano, y solo tras tocar iniciar; finalizarlo cancela la suscripción.
- Rumbo no guarda ni manda la coordenada GPS. Al centrar el mapa, las peticiones de teselas sí pueden permitir al proveedor inferir la zona visible aproximada; la interfaz lo explica junto a la atribución.
- `http` — descarga el feed estático y consulta el cliente GeoJSON detrás del proxy OAuth de desarrollo; las credenciales nunca se envían desde la app.
- El proxy permite CORS solo para orígenes HTTP loopback (`localhost`, `127.0.0.1`, `::1`) en desarrollo web; no publica wildcard ni permite credenciales en solicitudes del navegador.
- `archive` — valida y lee el ZIP GTFS sin ejecutar herramientas externas; se mantiene como adaptador de datos.
- `sqflite` y `path_provider` — guardan el GTFS compacto en SQLite en Android/iOS y sitúan la base bajo almacenamiento privado; Chrome usa `InMemoryTransitRepository` sobre los mismos patrones GTFS porque SQLite no está disponible.
- `path` — construye rutas de archivos de base de forma portable.
- GTFS se convierte a modelos Dart independientes del estándar. Las variantes actuales se derivan de la tupla `route_id + direction_id + shape_id`; esta agrupación evita mezclar sentidos/recorridos distintos, pero no sustituye identificadores oficiales de variante.
- `StopTime` guarda segundos desde el inicio del día de servicio, permitiendo valores como 25:10:00; los arribos posteriores a medianoche se reconstruyen desde el día de servicio anterior.
- En Android/iOS, la descarga estática se escribe a disco; un isolate lee el ZIP desde archivo, descomprime `stop_times.txt` a disco, recorre CSV por bloques de 64 KiB y escribe JSONL. SQLite importa todas las tablas en lotes de 500 dentro de la transacción de reemplazo; el ZIP y la tabla completa de horarios no se mantienen en memoria. Si la importación falla, se conserva el error original aunque también falle el cierre o la limpieza de la base temporal.
- SQLite usa tablas e índices geográficos, por parada/horario y por shape; los feeds se escriben en una base temporal en transacción y se renombran al finalizar para conservar la base anterior frente a fallos.
- El feed sintético solo se carga con `RUMBO_DEMO_MODE=true`; por defecto un proxy ausente produce estado sin conexión y no datos que parezcan rutas del STM.
- El vencimiento se deriva de `feed_info.txt` cuando está disponible; si no hay fecha final, el estado no se marca vencido. La app no declara condiciones de licencia no verificadas.
## Migración de horarios (completada — Fase 1)

El esquema `stop_times` (2.2 M de filas en el feed oficial) se reemplazó por
`trip_patterns` + `pattern_stops` para reducir el tamaño de la base y el tiempo
de importación. Dos viajes con la misma secuencia ordenada de paradas y los
mismos desfases (segundos de llegada/salida respecto del primer horario del
viaje) comparten un patrón, identificado por un hash SHA-256 estable.

Inventario de lo que usaba `stop_times`/`StopTime` y lo que cambió:

- `lib/features/stops_and_lines/data/gtfs_parser.dart`: ya no acumula todos los
  `StopTime` en `GtfsFeed.stopTimes`. Agrupa los tiempos por viaje en streaming
  (sin mantener todos los horarios en memoria), computa `TripPattern` por viaje
  con `pattern_id` (hash SHA-256 de la secuencia de `stop_id:arrival_offset:departure_offset`)
  y asigna `pattern_id` y `start_secs` a cada `Trip`. Si `stop_times.txt` no
  viene ordenado por viaje se detecta el desorden y se documenta en las
  advertencias (se recomienda tabla temporal para feeds no ordenados).
- `lib/features/stops_and_lines/data/gtfs_csv.dart`: sin cambios; sigue leyendo
  `stop_times.txt` en chunks acotados.
- `lib/features/stops_and_lines/data/transit_feed_source.dart`: el flujo nativo
  desde archivo evita JSONL y entrega los patrones compactos; `streamStopTimes`
  conserva el modo compatible para parsear bytes/fixtures.
- `lib/features/stops_and_lines/data/transit_database.dart`: esquema v6.
  `onUpgrade` de v5 a v6 elimina `stop_times`, agrega `pattern_id` y
  `start_secs` a `trips` (si faltan), crea `trip_patterns` y `pattern_stops`
  con índices por `stop_id` y `(pattern_id, ordinal)`. `replaceFeed` escribe
  patrones (y sus paradas con desfases) en lugar de filas de `stop_times`;
  patrones compactos sin releer una copia JSONL de los horarios. El importador
  nunca mantiene todos los horarios en memoria.
- `lib/features/stops_and_lines/data/sqflite_transit_repository.dart`:
  `routesForStop`, `routesForStops`, `upcomingDepartures` y `scheduleForStops`
  ahora consultan `pattern_stops` unido a `trips` (reconstruyendo `StopTime`
  como `start_secs + offset`) en lugar de `stop_times`.
- `lib/features/stops_and_lines/domain/transit_models.dart`: `StopTime` se
  mantiene como modelo de dominio; `Trip` agregó `patternId` y `startSecs`.
  `TripPattern` / `TripPatternStop` modelan el patrón compartido.
- `lib/features/trip_planner/domain/trip_planner.dart`: sin cambios de lógica;
  recibe `StopTime` ya reconstruidos con segundos absolutos desde el repositorio.
- `lib/features/search/data/local_transit_search_source.dart`: el join a
  `stop_times` se cambió a `pattern_stops` + `trips`.
- `lib/features/stops_and_lines/data/fake_transit_repository.dart`: sin cambios
  (usa `List<StopTime>` en memoria para pruebas).
- `lib/features/stops_and_lines/data/transit_arrivals_source.dart`: sin cambios
  (usa `repository.upcomingDepartures`).
- Tests: `test/transit_data_test.dart`, `test/gtfs_performance_test.dart`,
  `test/transit_arrivals_source_test.dart` actualizados al nuevo esquema;
  nuevo `test/trip_patterns_test.dart` cubre patrones compartidos/distintos,
  desfases, viaje post-medianoche, importación y migración v5→v6.

Dependencia nueva: `crypto: ^3.0.3` — usada solo para el hash SHA-256 estable
que identifica cada patrón de recorrido. No implica red, tracking, analítica ni
publicidad.

Esquema nuevo (v6):
- `trip_patterns(pattern_id TEXT PRIMARY KEY)`
- `pattern_stops(pattern_id, ordinal, stop_id, arrival_offset_secs, departure_offset_secs, PRIMARY KEY(pattern_id, ordinal))`, índices por `stop_id` y `(pattern_id, ordinal)`
- `trips(... , pattern_id TEXT, start_secs INTEGER)`, índice `(pattern_id, service_id, start_secs)`
- Se eliminó la tabla `stop_times`. Una base vieja (v5 o inferior) se descarta y se reimporta.

Medición con el feed oficial: no medido (no hay acceso al feed oficial ni al
proxy sin credenciales configuradas; la medición requiere entorno de producción
autorizado).

- Ruta de flota en vivo: el cliente construye la petición sobre `realtimeEndpoint` (con sufijo `/api`) llamando a `/buses?format=geojson`, por lo que la ruta efectiva es `/api/buses`. El proxy local `tool/montevideo_api_proxy.py` implementa `GET /api/buses` y lo reenvía al upstream. Se unificó la documentación para usar `/api/buses` como ruta del proxy.
- El proxy de desarrollo (`tool/montevideo_api_proxy.py`) expone la flota como `GET /api/buses?format=geojson` y la reenvía al upstream `GET /buses`. El cliente Flutter configura `realtimeEndpoint` con sufijo `/api` y pide `/buses`, de modo que la ruta efectiva es `/api/buses`. docs/api, README y este archivo documentan la ruta del proxy, no el path upstream.
- La búsqueda remota de direcciones queda apagada por defecto (`remote_place_search_enabled`). En el planificador, la primera búsqueda textual muestra el consentimiento y luego combina GTFS con geocodificación al escribir, sin un botón adicional. La ubicación precisa nunca se envía.
- En builds debug, el proxy local es `10.0.2.2:8765` en el emulador Android y `127.0.0.1:8765` en otras plataformas. En un teléfono Android por USB se usa `adb reverse tcp:8765 tcp:8765` y `RUMBO_API_BASE_URL=http://127.0.0.1:8765`. En release queda deshabilitado salvo que se configure explícitamente. HTTP se acepta solo en hosts locales de desarrollo (`localhost`, `127.0.0.1`, `10.0.2.2`, `::1`); las otras fuentes deben usar HTTPS. Si el único feed disponible es sintético, se vuelve a intentar la descarga aunque haya una comprobación fallida reciente. Los errores de descarga no renuevan el intervalo de caché.
- La búsqueda de paradas mientras se escribe no bloquea la búsqueda de direcciones: sin feed oficial devuelve una lista vacía y la búsqueda de lugares sigue disponible tras consentimiento. Planificar un viaje sí exige el feed oficial. El proxy `/geocode` acepta y valida los parámetros que envían las dos fuentes de lugares (`countrycodes`, `format`, `limit`, `bias_lat`, `bias_lon`), pero arma su propia consulta upstream.

- `sqflite_common_ffi` (solo desarrollo) — permite probar las transacciones SQLite en escritorio sin emulador ni plugins móviles.
- `Route.shortName` es una etiqueta visible y no se usa como identificador; `RouteVariant.externalVariantId` guarda el código entero STM opcional. Se importa desde `variant_id` de `trips.txt`, o desde `variant_map.csv` por `trip_id`/`shape_id`; si falta, se registra una advertencia.
- El parser STM interpreta `FeatureCollection` y `Point.coordinates` como [longitud, latitud], valida rangos y caja configurable de Uruguay, descarta features inválidas con conteo por motivo y deduplica por `properties.id` conservando la última aparición. `sourceId` conserva tipo/valor recibido; no se considera única la pareja empresa/unidad.
- Las líneas que pasan por una parada se derivan del join GTFS `stop_times → trips → routes`, agrupadas por `stop_id`. Las variantes usan su `shape_id` estático y se pueden dibujar en el mapa; la relación con `lineVariantId` de la API se mantiene opcional porque el feed oficial no trae ese campo y los cruces por texto no son unívocos.
- El snapshot de prueba conserva `frecuencia` y `version` en `rawExtras` sin interpretarlos. `receivedAt` es el instante local entregado al parser; la fuente descrita no trae timestamp ni rumbo.
- El manual de la Intendencia describe `GET /buses` y `GET /buses/geo` en el upstream. Rumbo no llama esos paths desde la app: consulta `GET /api/buses?format=geojson` en el proxy, sin coordenadas del dispositivo, y filtra la flota en el aparato.
- Los códigos de variante y las posiciones incluidos en fixtures son sintéticos. Los nombres de parada son ficticios y sus coordenadas son puntos sintéticos próximos al centro de mapa de Montevideo configurado en Rumbo; no se presentan como paradas reales.
- Las tablas GTFS restantes se procesan en memoria para formar los modelos de dominio. La versión previa tardó cerca de 3 minutos en importar el feed oficial en emulador; la revisión actual evita JSONL redundante y journaling del archivo temporal, aún sin una medición limpia posterior. El pico de memoria y el tiempo en teléfono físico siguen pendientes.
- La medición aislada del camino de archivo (parseo e importación SQLite) fue 1.171 ms en este equipo (ZIP sintético de 2.202 bytes, 18 paradas, 3 líneas, 6 variantes y 48 stop_times); no extrapolarla a feeds de producción ni a millones de horarios.

- `sourceId` mantiene el valor JSON de `properties.id` sin convertirlo; no se usa para formar una identidad de vehículo porque su formato puede cambiar cuando cambia la variante. La deduplicación usa ese valor opaco de forma exacta.
- No hay hora ni rumbo en la fuente de posiciones descrita: Rumbo asigna `receivedAt` al recibir el snapshot y no estima el rumbo. `frecuencia` y `version` permanecen en `rawExtras` hasta confirmar su significado.
- El parser GeoJSON conserva validaciones de rango y campos; el endpoint real se consume a través del proxy para mantener OAuth fuera del APK. La respuesta no incluye timestamp de origen, por lo que la UI muestra la hora local de recepción. Un dato de más de 60 s se dibuja atenuado y en el detalle aparece «hace N s».
- El mapa dibuja buses de líneas y variantes del área local cuando se cargó el GTFS, o todos los buses del viewport antes de tener filtros, recortados a 60 marcadores. El polling corre con el mapa visible y la app en primer plano, se pausa al salir y duplica el intervalo de reintento hasta 60 s.
- El planificador Dart puro busca itinerarios directos y con un transbordo, activa los calendarios GTFS y reconstruye tiempos de servicio que superan medianoche. Consulta SQLite para viajes que sirven paradas candidatas, sin cargar el feed completo desde la UI.
- El horario del viaje se modela con `TripTiming` (`departNow`, `departAt`, `arriveBy`). `departAt` usa el calendario del día elegido; si la hora ya pasó, no se ejecuta la búsqueda. Para `arriveBy` no se recorre el grafo hacia atrás: se reutiliza la búsqueda hacia adelante con salidas candidatas cada 10 minutos hacia atrás, hasta 3 horas antes de la hora pedida (18 consultas como máximo), y se devuelve el primer conjunto de itinerarios que llega a tiempo. El costo en el peor caso es 18 búsquedas en memoria sobre el índice del día; los índices se cachean por día de servicio.
- Los resultados del motor se marcan como horarios programados. La hoja de búsqueda permite elegir destino y fecha/hora de salida (de hoy a 60 días) con `showDatePicker` y `showTimePicker` de Flutter, sin dependencias nuevas. Si no se ajusta la salida, se usa la hora del momento de buscar. La caminata usa distancia geodésica y no equivale a una ruta peatonal ni a guía de navegación.
- La API oficial publica `/buses/busstops/{busstopId}/upcomingbuses` para buses próximos/ETA y exige seleccionar líneas; su modelo visible no aclara los campos numéricos del ETA. El proxy reenvía `/api/busstops/{id}/upcomingbuses`, pero la app aún usa ETA local proyectando buses sobre el shape (velocidad reportada si es ≥ 8 km/h, si no 18 km/h) junto a `upcomingDepartures`. Integrar el endpoint oficial queda condicionado a verificar su payload autorizado. [Documentación oficial](https://api.montevideo.gub.uy/apidocs/publictransport).
- Se aprobó el seguimiento de ubicación solo durante un viaje activo que la persona inicia explícitamente, para actualizar el progreso y notificación local. Debe procesarse en el dispositivo, detenerse al finalizar/cancelar y nunca enviar la ubicación a un servidor. La implementación debe solicitar autorización específica, usar los modos de segundo plano requeridos por cada SO y no mantener seguimiento fuera del viaje; Android puede mostrar servicio/notificación persistente y iOS puede limitar la persistencia visible.
- Los parámetros del planificador viven en `PlannerConfig`: factor de rodeo 1,3, caminata 4,8 km/h, caminata máxima 800 m (opciones 400/800/1200 m), transbordo peatonal hasta 150 m en línea recta, tiempo mínimo de transbordo 3 min, hasta 1 transbordo, espera máxima 45 min y 5 resultados. La caminata estimada de cada tramo es la distancia geodésica × 1,3; la velocidad se convierte desde km/h. El máximo de caminata se compara contra la suma estimada de los tramos de un itinerario con transporte.
- La opción «Caminar» se genera cuando la separación en línea recta entre origen y destino es menor que la caminata máxima configurada (800 m por defecto). Es la única regla que usa la distancia recta, tal como se pidió; el tiempo y la distancia mostrados sí incluyen el factor de rodeo, por lo que una caminata de 700 m rectos puede informar más de 800 m estimados. No se genera si el origen y el destino coinciden.
- El transbordo entre paradas distintas se habilita cuando la separación recta es de hasta 150 m. El tramo peatonal usa el factor de rodeo y se suma al tiempo y a la caminata total. La conexión debe dejar al menos el tiempo mínimo de transbordo entre la llegada del primer viaje y la salida del segundo, y ese intervalo también respeta la espera máxima. Si no se cumple, se descarta.
- Antes de devolver resultados se deduplican por recorrido y hora de salida, se descartan los itinerarios dominados (otro llega antes o igual, con no más transbordos y no más caminata) y se aplica el límite de 5. La pantalla puede reordenar localmente sin volver a buscar: «Más rápido» (hora de llegada), «Menos caminata» y «Menos transbordos», todos con desempate por llegada. Cambiar la caminata máxima vuelve a ejecutar la búsqueda.
- Medición del planificador: un caso sintético de 500 viajes × 30 paradas, con 3 paradas de origen, 3 de destino, salida a las 12:00 y un solo día de servicio, tardó 5.573 ms en este equipo (WSL sobre Windows). Supera el umbral de 2 s, por lo que la búsqueda en memoria se ejecuta en un `Isolate` en Android/iOS/escritorio; en web se usa el fallback sincrónico porque no hay isolates. El número corresponde a ese escenario y a este equipo, no a un feed oficial ni a un dispositivo móvil; la carga desde SQLite ocurre fuera del isolate.
- La tarjeta de resultado muestra salida–llegada, duración total, un `LineChip` por línea de transporte en orden, minutos de caminata (suma de tramos peatonales redondeada hacia arriba), cantidad de transbordos y la leyenda «Horarios programados». Cada tarjeta expone una etiqueta semántica única que resume el viaje para lectores de pantalla.
- El detalle usa una línea de tiempo vertical y omite los tramos de espera: salida → caminata → abordaje → bajada → llegada. Solo la hora de salida se muestra como programada; caminata, abordaje, bajada y llegada llevan «· estimado». El texto aclara que la caminata es aproximada y en línea recta, y que no hay ETA en vivo.
- En el mapa, los tramos de transporte se dibujan continuos con `deepBlue` (token `rumbo`), los peatonales punteados con `dashArray`, el origen con un marcador `ink` y el destino con uno `lime`. Mientras hay un plan seleccionado se ocultan los marcadores de buses en vivo para no mezclar el itinerario con datos de tiempo real.
- El estado vacío ofrece dos acciones: «Ampliar caminata» avanza al siguiente valor de `PlannerConfig.walkingOptionsMeters` y vuelve a buscar; «Cambiar hora» pasa de salir ahora a salir a una hora, abre el selector y relanza la búsqueda. Los estados de carga y error tienen indicador y botón de reintento respectivamente.
- Favoritos se modela con `Favorite` (tipos `stop`, `line` y `place`) y una lista JSON local en `shared_preferences` (`favorites_v1`), sin red ni SDK nuevo. Casa y Trabajo son ranuras fijas con ids estables (`place-home` y `place-work`): volver a definirlas reemplaza el lugar en vez de duplicarlo, y el nombre visible es el del lugar elegido. Una entrada dañada se descarta al cargar sin invalidar el resto; si el JSON completo es inválido, se trata como lista vacía.
- La pantalla de Favoritos agrupa Lugares, Paradas y Líneas. Tocar un lugar abre el planificador con ese destino, una línea se selecciona y dibuja en el mapa, y una parada abre su hoja de detalle. Deslizar elimina con «Deshacer» y mantener presionado renombra solo el nombre visible. El modelo admite lugares sin ranura, pero la interfaz todavía no ofrece agregarlos.
- Los atajos Casa/Trabajo del mapa aparecen solo cuando la ranura tiene coordenadas; se ubican debajo de la búsqueda, dentro del área segura y con objetivos de al menos 48 dp, sin tapar los controles ni la atribución. Los favoritos se alternan desde el detalle de parada y desde la expansión de línea, sin confirmaciones emergentes.
- Para desacoplar Favoritos del mapa se usa `mapActionProvider` con acciones selladas (`ShowRouteOnMap` y `PlanTripToPlace`). Favoritos deja la acción pendiente y navega a `/map`; el mapa la consume una vez y la limpia. Así la pantalla no depende de detalles de implementación del mapa y se puede probar de forma aislada.
- Limitaciones conocidas: Favoritos vive solo en el dispositivo, no se sincroniza y se pierde al desinstalar; no hay favoritos de viajes ni de lugares personalizados adicionales. La persistencia se probó con `shared_preferences` simulado y con un repositorio falso, no en un emulador ni con almacenamiento real del sistema.

## Fase 3: variantes oficiales y arribos oficiales

- Diagnóstico de variante: el proxy expone `GET /api/linevariants` y `GET /api/linevariants/{lineVariantId}`; los objetos documentados contienen `lineVariantId`, `lineId`, `line`, `origin`, `destination` y `subline`. La respuesta documentada de buses contiene `lineVariantId`, pero no se documenta una clave de cruce entre esos campos y cada `trip_id`/`shape_id` del ZIP GTFS; tampoco hay fixture oficial de ambas fuentes. No se puede generar `variant_id` ni `variant_map.csv` fiable sin verificar ese mapeo. Se mantienen `externalVariantId` nulos cuando el GTFS no lo trae; no se infiere por nombre de línea/destino.
- Arribos: la documentación oficial describe `/buses/busstops/{busstopId}/upcomingbuses`, filtros requeridos y respuesta de buses próximos, pero el modelo publicado no identifica el campo ni la unidad del ETA. El proxy reenvía la ruta y la app no interpreta aún esa respuesta; mantiene el ETA local por shape como aproximación y horarios GTFS como programados. Falta una respuesta oficial autorizada/fixture para fijar el parser sin adivinar.
- No se consumieron fuentes reales ni credenciales en esta fase. El diagnóstico se limita a la documentación versionada y al enrutamiento/validación del proxy local.

## Privacidad y búsqueda de destinos
- La pantalla de privacidad centraliza controles y avisos de geocodificación y de posiciones de ómnibus; el permiso para búsqueda remota se conserva desactivado por defecto.
- El texto de un destino se transmite al geocodificador después de habilitar la búsqueda y aceptar el consentimiento inicial; la ubicación GPS no se incluye en esa consulta.
- Desactivar posiciones en vivo detiene el polling, limpia ubicaciones de buses en memoria y descarta respuestas que concluyan después de apagar el control.
- Limpiar datos locales elimina favoritos, búsquedas recientes y caché ambiente de teselas; conserva el tema y permisos de preferencias.
- La búsqueda de lugares presenta el campo `name` del proveedor cuando existe, y usa `display_name` como fallback, para que los POIs no aparezcan como una dirección extensa.

## Viaje activo en segundo plano
- El botón de seguimiento solo aparece para planes que tienen una variante y parada final identificadas. La persona lo inicia explícitamente; se requiere ubicación «Permitir siempre» y permiso de notificaciones.
- `geolocator` usa en Android `AndroidSettings` con servicio foreground, actualización cada 5 s y filtro de 20 m; la notificación persistente acompaña al servicio y el aviso local se actualiza con las paradas restantes.
- En iOS se usan `AppleSettings.allowBackgroundLocationUpdates`, modo `UIBackgroundModes=location` y texto de autorización dedicado. iOS no ofrece un aviso persistente equivalente al servicio Android; se publican avisos locales al cambiar el contador y al acercarse.
- La ubicación se procesa en el teléfono y no se envía a servidores. El criterio de bajada combina distancia recta ≤300 m con progreso ≤2 paradas en la secuencia GTFS, y evita duplicar el aviso.
- «Finalizar viaje», cambiar el plan o cerrar el detalle cancela la suscripción y notificaciones. Sin dependencias nuevas: se reutilizan `geolocator` y `flutter_local_notifications`; no se incorpora SDK de tracking.

## Importación inicial de GTFS
- El parser procesa `stop_times.txt` en streaming y deduplica patrones por `pattern_id`; SQLite recibe cada patrón una vez aunque varios viajes compartan el mismo recorrido.
- La importación usa patrones compactos en vez de crear y recorrer JSONL de cada horario; reporta avance y desactiva journal/synchronous solo en el archivo temporal desechable, sin tocar la base vigente antes del cambio atómico.
- El planificador espera el `Future` inicial del feed también cuando Riverpod aún no publicó datos; errores de red/importación mantienen el diagnóstico para evitar el falso estado “GTFS no disponible”.
