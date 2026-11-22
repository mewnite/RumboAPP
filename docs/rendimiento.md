# Rendimiento

## Fase 1: desacople del arranque y caché de respaldo

Fecha de ejecución: 2026-11-21.

### Cambios medidos por código y pruebas

| Operación | Resultado después | Estado |
|---|---|---|
| Inicio de la app | Ya no ejecuta una consulta `/buses` ni solicita `/health` antes de `runApp` | implementado; falta capturar un dispositivo release |
| Búsqueda de dirección | El buscador integrado se crea en Android/iOS sin esperar al feed | implementado y cubierto por la suite existente |
| Planificación | Sigue usando exclusivamente GTFS/SQLite; no lee posiciones GPS para calcular alternativas | implementado y cubierto por pruebas del planificador |
| Caché de lugares | El proxy conserva el último resultado ante una falla del proveedor | implementado y probado |
| Datos estáticos de referencia | Líneas y paradas conservan la última respuesta válida ante fallos | implementado y probado |
| GTFS | Conserva el último ZIP válido ante OAuth/red/HTTP y una actualización inválida | implementado y probado con archivo local |
| Geocodificación distribuida | Cloudflare normaliza y reutiliza una clave de caché por consulta | implementado; falta medir una instancia desplegada |

### Verificaciones realizadas

- `flutter analyze`: cero errores y warnings.
- `flutter test`: la suite completa terminó con código 0 antes del ajuste final de lint.
- `python -m unittest tool/test_montevideo_api_proxy_test.py tool/test_montevideo_api_test.py`: 16 pruebas pasaron.
- `node --check cloudflare/worker.js`: sintaxis válida.
- No se declara cumplimiento del objetivo de 5 segundos hasta ejecutar mediciones reales de interfaz, red Render y dispositivos.

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

### Estado visual tras las fases 2–5

- Se reemplazaron `deepBlue`, `mint`, `surfaceGray` y `white` por los tokens
  `rumbo`, `lime`, `ivory` y `surface`; `app_colors.dart` concentra las
  constantes de color, espacio, radio y sombra.
- Las pantallas usan el `ColorScheme` y los temas compartidos de componentes.
  Los únicos colores de línea que se calculan fuera del tema proceden de los
  datos GTFS; los colores de paradas, buses, rutas y estados usan tokens.
- El análisis estático confirma que no hay `Colors.*` ni hexadecimales fuera
  del archivo de tokens.
- No se encontró `docs/identidad/identidad.png` en el repositorio.
- No se pudo revisar la aplicación en un dispositivo con ambos temas y escala
  de texto al 130 %; se agregaron pruebas de widgets para esa escala, pero la
  suite de Flutter no se pudo ejecutar.

## Fase 1: búsqueda y datos más rápidos

Implementado sin agregar dependencias:

- Índice local normalizado, construido una vez por feed mediante `compute`,
  reutilizado por SQLite y web, con coincidencia por código, prefijo, palabra
  y contenido, máximo 20 resultados y orden estable.
- El índice incluye nombres y códigos de paradas, nombres de líneas, destinos
  de variantes y lugares guardados. La normalización quita acentos y signos.
- La búsqueda local espera 200 ms y requiere 2 caracteres. Los resultados
  viejos se descartan con un identificador de petición.
- La geocodificación remota requiere tocar “Buscar lugares en línea”; el envío
  tiene timeout de 8 s, se cancela al cambiar la consulta y conserva hasta 20
  consultas recientes en memoria.
- La planificación limita cada extremo a 15 paradas, reutiliza consultas
  cercanas repetidas y puede detener el isolate anterior cuando cambian los
  datos de entrada. El estado de búsqueda muestra progreso.
- La base se reabre en modo solo lectura después de crear o migrar el esquema.
  El mapeo de los resultados de horarios se ejecuta en un isolate.
- Se agregó una prueba con `EXPLAIN QUERY PLAN` para paradas cercanas, arribos
  y detalle de parada, y otra para comprobar el modo de solo lectura. No se
  ejecutaron porque el comando de pruebas de Flutter no terminó.

Los presupuestos de Fase 1 siguen **no medidos** en un dispositivo Android
profile con el feed oficial: no se pudo iniciar una sesión profile utilizable
con el proxy activo.

## Fase 6: comparación antes y después

No se obtuvieron mediciones nuevas: el emulador no inició una sesión profile y
el intento de `flutter test` quedó sin salida por más de un minuto y se detuvo.
No se estiman tiempos ni tamaños.

| Medición | Antes | Después | Estado o causa |
|---|---:|---:|---|
| APK `armeabi-v7a` release split | 27,9 MB | 26,3 MB | medido; -5,7 % |
| APK `arm64-v8a` release split | 32,9 MB | 31,5 MB | medido; -4,3 % |
| APK `x86_64` release split | 34,6 MB | 33,3 MB | medido; -3,8 % |
| Consulta `105` | no medido | no medido | no se pudo iniciar la app profile |
| Consulta `pocit` | no medido | no medido | faltó una sesión profile y el proxy local |
| Consulta `plaza` | no medido | no medido | faltó una sesión profile y el proxy local |
| Consulta `tres cruces` | no medido | no medido | faltó una sesión profile y el proxy local |
| Detalle de parada | no medido | no medido | no se pudo iniciar la app profile |
| `nearbyStops` | no medido | no medido | no se pudo iniciar la app profile |
| Planificación típica | no medido | no medido | no se pudo iniciar la app profile |
| Arranque en frío | no medido | no medido | no se pudo iniciar la app profile |
| Tamaño de base | no medido | no medido | no se accedió a la base del dispositivo |
| Memoria aproximada | no medido | no medido | no se pudo capturar una sesión profile |

## Línea base de optimización

Fecha de ejecución: 2026-10-29. El comando solicitado con
`--split-per-abi --analyze-size` no es aceptado por la versión instalada de
Flutter; el análisis se ejecutó por separado para `android-arm64` y la
compilación split se ejecutó para las tres ABI.

| Medición | Resultado | Estado |
|---|---:|---|
| APK `armeabi-v7a` release split | 27,9 MB | medido |
| APK `arm64-v8a` release split | 32,9 MB | medido |
| APK `x86_64` release split | 34,6 MB | medido |
| Análisis `android-arm64` | `lib` 48,45 MB; `classes.dex` 1,00 MB; assets 0,96 MB; recursos 0,64 MB | medido |
| Código Dart/native dentro de `lib` | 48,45 MB | medido; el reporte no separa Dart de bibliotecas nativas |
| Fuentes en assets | Inter 783,6 KB; Material Symbols Rounded 65,2 KB | medido |
| Datos de ejemplo en assets | `sample_gtfs.zip` 1,7 KB | medido |
| Base GTFS importada | no medido | no se accedió a una base del dispositivo |
| Arranque en frío | no medido | no hubo sesión Android profile/release conectada |
| Memoria con mapa y buses | no medido | no hubo sesión conectada |
| Fotogramas perdidos y reconstrucciones | no medido | no hubo sesión DevTools conectada |
| Búsquedas, detalle y planificación | no medido | no hubo sesión profile conectada |
| Datos móviles en 5 minutos | no medido | no se ejecutó una sesión de red controlada |

El build informó que Material Symbols Outlined y Sharp fueron tree-shaken a
aproximadamente 2,4 KB cada una, y Rounded a 135,3 KB antes de compresión;
por tanto la fuente de iconos ya está siendo recortada y no se reemplaza en
esta fase.

### Fase 1: medición posterior a R8

Fecha de ejecución: 2026-11-01. Se ejecutó
`flutter build apk --release --split-per-abi --obfuscate
--split-debug-info=build/symbols` con R8 y `shrinkResources` activos.
El comando combinado con `--analyze-size` no es aceptado por esta versión de
Flutter; el análisis arm64 se ejecutó por separado sin
`--split-debug-info`.

| Medición | Línea base | Después | Estado |
|---|---:|---:|---|
| APK `armeabi-v7a` release split | 27,9 MB | 26,3 MB | medido, -5,7 % |
| APK `arm64-v8a` release split | 32,9 MB | 31,5 MB | medido, -4,3 % |
| APK `x86_64` release split | 34,6 MB | 33,3 MB | medido, -3,8 % |
| Análisis arm64 total comprimido | no separado | 51 MB universal de análisis | medido |
| `flutter_assets` | 0,96 MB | 981 KB | medido |
| `classes.dex` | 1,00 MB | 1 MB + `classes2.dex` 78 KB | medido |
| `lib/arm64-v8a` | 48,45 MB en el análisis previo | 30 MB | medido en el análisis |
| Símbolos Dart AOT | no separado | 8 MB descomprimido | medido |
| Código Dart principal | no separado | `package:rumbo` 562 KB | medido |
| Fuentes/íconos | Inter 783,6 KB; Rounded tree-shaken 135,3 KB | mismo orden de magnitud; Rounded 135,3 KB | medido |
| Base GTFS importada | no medido | no medido | no hubo base de dispositivo accesible |

El objetivo orientativo de -25 % no se alcanza: la mayor parte del APK sigue
siendo la biblioteca nativa de MapLibre (`lib/arm64-v8a`, 30 MB en el análisis),
que R8 no puede reducir. El build release optimizado terminó correctamente y
los 184 tests pasaron; no se verificó el arranque, el mapa ni la búsqueda en un
dispositivo Android release.

### Verificación Android en `emulator-5554`

Fecha de ejecución: 2026-11-02. Se instaló y ejecutó la app debug actual en el
emulador Android API 37 (`sdk gphone64 x86 64`). Después del cambio que difiere
la carga del feed hasta el primer frame, se ejecutó hot restart mediante DTD y
se consultaron los logs de Android.

| Medición | Antes en emulador | Después en emulador | Estado |
|---|---:|---:|---|
| Primer fotograma útil | 9.165 s | 2.938 s | medido |
| Feed cacheado disponible | 17.289 s | 1.005 s | medido |
| Memoria RSS inicial | 583.8 MB | 717.5 MB | medido; empeora y requiere una fase específica |
| Memoria RSS después de feed | 635.9 MB | 723.8 MB | medido; supera la meta de 300 MB |
| Cuadros omitidos durante arranque | 612 y 154 | 30 | medido; aún no es fluido |
| Buses en vivo | no medido | no disponible | el proxy `10.0.2.2:8765` no respondió/configuró datos en esta sesión |

El primer frame y la disponibilidad del feed mejoraron, pero el mapa nativo y
la base GTFS de 198 MB mantienen el consumo de memoria por encima del objetivo.
La medición de buses en vivo queda pendiente hasta iniciar el proxy oficial de
desarrollo; no se inventan posiciones ni tiempos.

## Fase 2: auditoría profunda y optimizaciones medibles

Fecha de ejecución: 2026-11-21.

### Diagnóstico probado

- RSS distingue la memoria residente del proceso de memoria Dart y nativa:
  la medición existente registra RSS con `ProcessInfo.currentRss`.
- En las pruebas FFI, RSS quedó en 175-176 MB para una base sintética; no se
  compara con el RSS Android histórico de 717,5 MB porque los entornos son
  distintos.
- MapLibre mantiene su caché nativa de teselas y puede estar fuera del heap
  Dart. La caché ambiental se limita a 256 MB y debe configurarse al crear el
  mapa; no se encontró una copia de GTFS cargada completa en memoria durante
  consultas normales.
- La base vive en una sola conexión readonly reutilizada. Abrir el archivo
  como escribible y dejarlo abierto no era parte del camino normal.
- El planificador ya limita endpoints a 15 paradas, consulta solo viajes
  relevantes y ejecuta la construcción de índices fuera del isolate principal.
- Se encontraron tres índices compuestos sin crear: viajes por variante y hora,
  viajes por servicio y excepciones de calendario por servicio/fecha/tipo.
- La carga de salidas de una variante todavía debía limitarse antes de
  calcular el conjunto final de horarios.
- Las búsquedas locales repetidas compartían el mismo índice, pero no tenían
  caché acotada ni un índice de candidatos por bigramas.
- Las formas cargadas para planes anteriores podían permanecer en memoria hasta
  reemplazar toda la pantalla. Ahora se podan al cargar un nuevo plan.
- Las respuestas simultáneas de buses podían aplicar una respuesta antigua
  sobre una consulta nueva. Se agregó invalidación por generación.

### Optimizaciones implementadas

| Área | Cambio | Evidencia |
|---|---|---|
| SQLite | Versión de esquema 7 e índices compuestos para variantes, servicios y excepciones | Cubierto por `EXPLAIN QUERY PLAN` |
| SQLite | Las próximas salidas de una variante consultan como máximo 40 o 4 veces el límite solicitado | Evita materializar viajes innecesarios |
| Búsqueda | Índice de candidatos normalizados por bigramas construido una vez | Escanea menos entradas antes del ranking |
| Búsqueda | Caché in-memory limitada a 32 consultas y consultas por 20 resultados | Evita trabajo repetido en la misma sesión |
| Planificador | Conserva límite de 15 candidatos y aislamiento del cálculo puro | Sin cambios de GPS ni datos simulados |
| Mapa | Poda las formas de viaje que dejan de pertenecer al plan seleccionado | Reduce retención de geometrías |
| Mapa | Las respuestas de live buses obsoletas se descartan por generación | Evita estado tardío y políticas duplicadas |

### Mediciones verificadas

| Medición | Antes | Después | Entorno |
|---|---:|---:|---|
| Importación GTFS sintético | 356 ms | 268 ms | Linux/Dart en el equipo; 2202 bytes y 48 stop_times |
| RSS prueba SQLite sintética | 226,5 MB | 175,4 MB | FFI local; no Android |
| Plan típico del test | 54 ms | 59 ms | Flutter test local; datos sintéticos |
| Base sintética con esquemas previos | 106496 bytes | 118784 bytes | FFI local; el crecimiento incluye índices adicionales |
| Caché de búsqueda repetida | no medido antes | prueba `< 100 ms` | Flutter test local |

Estas cifras son reproducibles en pruebas locales, no sustituyen mediciones
Android release. No se declara cumplimiento de la meta RSS de 300 MB ni de los
objetivos de primer frame hasta capturar un dispositivo físico o un emulador
documentado por separado.

### Consultas lentas y planes

`transit_query_plan_test.dart` verifica con FFI que:

- `nearbyStops` usa `stops_lat_lon`.
- las llegadas usan `pattern_stops_stop_id` y
  `trips_pattern_service_start`.
- el detalle de parada usa el índice de clave primaria.
- las salidas por variante usan `trips_variant_start`.
- las excepciones usan `calendar_exceptions_service_date_type`.
- la base abierta en modo lectura rechaza escrituras.

### Archivos modificados

- [`transit_database.dart`](../lib/features/stops_and_lines/data/transit_database.dart):
  migración de esquema e índices.
- [`sqflite_transit_repository.dart`](../lib/features/stops_and_lines/data/sqflite_transit_repository.dart):
  límite de materialización de salidas.
- [`transit_search_index.dart`](../lib/features/search/data/transit_search_index.dart):
  candidatos por bigramas y caché acotada.
- [`map_screen.dart`](../lib/features/map/presentation/map_screen.dart):
  poda de formas y cachés al desmontar.
- [`live_buses_controller.dart`](../lib/features/map/presentation/live_buses_controller.dart):
  invalidación de consultas obsoletas.
- [`transit_query_plan_test.dart`](../test/transit_query_plan_test.dart) y
  [`transit_search_index_test.dart`](../test/search/transit_search_index_test.dart):
  pruebas del plan SQL y caché.

### Pruebas ejecutadas

- `flutter analyze`: cero errores ni warnings.
- Suite focalizada: 25 pruebas superadas.
- `flutter test`: suite completa superada.
- `flutter build apk --release`: APK generado en
  `build/app/outputs/flutter-apk/app-release.apk`, tamaño 89,9 MB.

### Problemas pendientes

- Falta capturar RSS Dart, RSS nativo, heap Dart y tiles MapLibre en Android
  debug/profile/release.
- Falta una base GTFS oficial real: los tamaños y tiempos sintéticos no pueden
  estimar 198 MB ni la distribución real de recorridos.
- Falta medir búsquedas remotas, primera tesela, marcos omitidos y posición GPS
  en dispositivos físicos separados de emuladores.
- La primera y segunda fase no deben declarar éxito de memoria sin esa
  medición.

### Recomendación siguiente

Antes de cambiar el motor, algoritmo o estructura GTFS:

1. Capturar Android release con la base real y una matriz debug/profile/release.
2. Registrar heap Dart, RSS, memoria nativa/gráfica y tamaños por tabla/índice.
3. Medir resultados por consulta SQL con `EXPLAIN QUERY PLAN` y datos reales.
4. Comparar RAPTOR solo si las mediciones muestran que el planificador puro ya
   consume una fracción relevante del presupuesto.

## Red peatonal: generación, carga y consulta (2026-11-22)

La seed binaria se genera fuera de la app desde el extracto OSM recortado y
fechado; la app no depende de que Render/Overpass responda. En escritorio
Windows, para 13.595.566 bytes de JSON normalizado:

| Operación | Tiempo medido |
|---|---:|
| `jsonDecode` | 395 ms |
| Construcción del grafo | 1.252 ms |
| Codificación binaria | 188 ms |
| Tamaño de seed `RWB1` | 6.441.436 bytes (6,14 MiB) |
| Arranque del worker persistente, incluyendo carga/índice | 485–702 ms |
| Ruta directa (923,88 m, 17 puntos), 5 iteraciones | 2,98–18,01 ms |
| Misma ruta, roundtrip del worker, 5 iteraciones | 3,35–7,77 ms |

El worker recibe el binario una vez con `TransferableTypedData`, retiene el
grafo CSR inmutable y sus índices de componente y espaciales, y recibe por
mensajes cada búsqueda/refinamiento. No copia los 108 mil vértices ni
reconstruye el índice por consulta. La prueba de integración ejecuta estos
mensajes con `tester.runAsync`.

La consulta había tardado 6,1–7,9 s por un error en la escala de longitud: se
clampaba el producto de metros por grado, en vez del coseno. Eso generaba una
ventana de 75° y 6.000.008 celdas por snap. Corregido el orden del `clamp`, el
mismo punto inspecciona 72 celdas y la ruta volvió a decenas de milisegundos.
Las cifras anteriores son de escritorio; el rendimiento en Android y el
objetivo de cinco segundos siguen pendientes de validar en un teléfono con
`flutter run --profile` y logs `[performance]`.

La equivalencia con el grafo mutable histórico se evaluó con 25 pares
determinísticos de paradas GTFS, con la misma entrada normalizada para ambos:
27.328 vías, SHA-256
`c5a78c84a070a2468e4617afd6bfac64a709471fab9439593b752bb143a3f10a`. Ambos
construyeron 107.885 vértices y 128.666 aristas. Tolerancia:
`max(15 m, 2% de la distancia histórica)`. 12/25 pares quedaron dentro;
diferencia absoluta media 30,71 m, mediana 30,24 m, máximo 75,85 m. La
equivalencia sigue sin resolverse. El diagnóstico encontró diferencias de
snapping: el histórico priorizaba un vértice cercano sobre una proyección más
cercana y su proyección de respaldo mezclaba grados con metros al cuadrado.
Una referencia independiente en Python coincidió con el grafo actual a menos
de 0,01 m en cuatro pares, pero usa la misma CSR de la seed; no valida una
fuente externa ni rutas reales. Los pares, resultados y límites de esta
verificación están en [`walk_graph_seed.md`](walk_graph_seed.md).

## APK multiplataforma generado al solicitar arm64 (2026-11-22)

`flutter build apk --release --target-platform android-arm64` generó
`app-release.apk` con 76.248.671 bytes: **76,25 MB decimales = 72,72 MiB**
(1 MiB = 1.048.576 bytes). Aunque se solicitó arm64, este APK no era
arm64-only: plugins incluyeron también bibliotecas x86_64 y armeabi-v7a.
Entradas más pesadas por tamaño comprimido dentro del APK:

| Entrada | Bytes comprimidos | MiB |
|---|---:|---:|
| `assets/flutter_assets/assets/transit_db/rumbo_transit_seed.db` | 22.255.691 | 21,22 |
| `lib/arm64-v8a/libflutter.so` | 11.763.360 | 11,22 |
| `lib/x86_64/libmaplibre.so` | 11.208.016 | 10,69 |
| `lib/arm64-v8a/libmaplibre.so` | 10.847.024 | 10,34 |
| `lib/arm64-v8a/libapp.so` | 8.848.264 | 8,44 |
| `lib/armeabi-v7a/libmaplibre.so` | 7.916.144 | 7,55 |

Aunque se pidió plataforma arm64, el APK también contiene `libmaplibre.so` y
`libdartjni.so` para x86_64 y armeabi-v7a. Esas cuatro bibliotecas extra suman
19.322.552 bytes (18,43 MiB), casi todo el aumento informado desde 54,2 MiB
(+18,52 MiB). La seed ocupa 63.467.520 bytes al descomprimirse y 22.255.691
bytes en el APK. El APK anterior no está disponible en este checkout, por lo
que la atribución del cambio es una comparación de tamaños y entradas actuales,
no una comparación binaria entre ambos artefactos.

## APK arm64 split

En una compilación limpia de validación, `flutter build apk --release
--split-per-abi --target-platform=android-arm64` produjo
`app-arm64-v8a-release.apk` de 59.686.223 bytes (**59,69 MB decimales =
56,91 MiB**). El APK contiene únicamente `arm64-v8a`. En otra medición, el APK
multiplataforma de comparación, construido junto al split, midió 79.085.894
bytes (79,09 MB = 75,42 MiB), una diferencia de 19.399.671 bytes (18,50 MiB).
Ese APK de comparación no es el build anterior de 76.248.671 bytes descrito
arriba; son mediciones de builds distintos.

Entradas comprimidas más pesadas del split arm64:

| Entrada | Bytes comprimidos |
|---|---:|
| `assets/flutter_assets/assets/transit_db/rumbo_transit_seed.db` | 22.255.691 |
| `lib/arm64-v8a/libflutter.so` | 11.763.360 |
| `lib/arm64-v8a/libmaplibre.so` | 10.847.024 |
| `lib/arm64-v8a/libapp.so` | 8.848.264 |
| `assets/flutter_assets/assets/walk_graph/walk_graph_seed.bin` | 2.836.686 |

El tamaño informado por Flutter como MB está expresado en MiB en estos logs;
se muestran ambas unidades para evitar confusión. Son resultados de build en
Windows, no una medición de descarga o instalación en un teléfono.

## Filtro explícito de ABI para build arm64 (2026-11-22)

Se verificó `flutter build apk --release --target-platform android-arm64
--android-project-arg=rumboAndroidAbis=arm64-v8a` con ambos seeds instalados
temporalmente en `assets/`. El artefacto resultante fue 59.686.223 bytes:
**59,69 MB decimales = 56,91 MiB**. Esta es la medición arm64-only reportada
para el proyecto. El ZIP contiene únicamente bibliotecas `arm64-v8a`. Sin el
filtro, el APK multiplataforma medido incluyó también `x86_64` y `armeabi-v7a`
y midió 79.085.894 bytes (75,42 MiB), una reducción medida de 19.399.671 bytes
(18,50 MiB). La compilación de distribución continúa usando
`--split-per-abi` para publicar un APK por arquitectura; el binario usado para
medir no se dejó en el árbol de trabajo.
