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
