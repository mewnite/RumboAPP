# Datos de transporte (GTFS) y BD semilla

## Origen de los datos

- Fuente estática del feed: endpoint público del proxy local
  [`https://rumboapp.onrender.com/gtfs/latest`](https://rumboapp.onrender.com/gtfs/latest)
  (configurable vía `RUMBO_API_BASE_URL` en
  [`lib/core/config/transit_config.dart`](../lib/core/config/transit_config.dart)).
  Este proxy remotiza `api.montevideo.gub.uy` (STM / Intendencia de Montevideo).

**Licencia (pendiente de verificación):** no he verificado formalmente los
términos de uso de STM / Intendencia de Montevideo. El proxy y la app asumen
que los datos estáticos pueden usarse como fuente local de la app. Antes de
usarlos como fuente oficial en producción (APK en Play Store), verificar
licencia, condiciones de uso y atribución oficial.

## Feed integrado en la seed

La seed empaquetada `assets/transit_db/rumbo_transit_seed.db` contiene
`feed_version=1.1`, `feed_start_date=20261116`,
`feed_end_date=20261217` y publisher
`Sistema de Transporte Metropolitano - MONTEVIDEO`. SQLite registra
`downloaded_at=2026-11-21T21:16:09.235211`; corresponde a la versión 1.1
observada en el feed `/gtfs/latest` del 22/11/2026.
La seed no guarda el SHA-256 del ZIP de origen, así que los metadatos
confirman versión, fechas y publisher, pero no permiten probar identidad
byte por byte con una descarga histórica concreta.

El vencimiento del campo GTFS `feed_end_date` es inclusivo hasta el final de
esa fecha. La app muestra un aviso cuando el feed instalado está vencido o
vence en menos de siete días, y fuerza un chequeo de actualización prioritario.
La descarga automática completa sigue restringida a Wi-Fi/Ethernet; la acción
explícita «Actualizar ahora» puede iniciarla manualmente.
La seed versionada actualmente tiene límite `20261217`: debe regenerarse antes
del 17/12/2026. El workflow de release rechaza feeds con menos de siete días
completos de vigencia.

El workflow [`feed_history.yml`](../.github/workflows/feed_history.yml)
registra cada chequeo, aunque el hash no cambie, junto con SHA-256, bytes,
versión, fechas, publisher, `Last-Modified` y `ETag`. En la respuesta
consultada el 22/11/2026, el proxy no expuso los dos últimos encabezados.

## Base del grafo peatonal y ODbL

La seed binaria del grafo peatonal deriva de OpenStreetMap y es una base
derivada bajo ODbL 1.0. Su fuente, hash SHA-256, bbox y conteos se registran en
[`walk_graph_seed_manifest.json`](./walk_graph_seed_manifest.json); el formato
y el flujo reproducible están en
[`walk_graph_seed.md`](./walk_graph_seed.md). El PBF y el binario se generan en
CI y no se commitean. Si se publica o distribuye la seed, conservar la
atribución «© OpenStreetMap contributors» y cumplir las obligaciones
aplicables de la licencia, incluida la puesta a disposición de la base
derivada cuando corresponda. La atribución del mapa también identifica
OpenMapTiles y OpenFreeMap; estos proveedores no sustituyen la atribución de
los datos OSM.

## Esquema y tamaño de la BD

- DB en SQLite: `assets/transit_db/rumbo_transit_seed.db` (semilla incluida en el bundle).
- Tamaño de la semilla: **63,467,520 bytes (~60.5 MB)**.
- Datos medidos del feed real (proxy):
  - 4,920 paradas; 324 rutas; 37,445 viajes; 1,086 variantes;
  - 8,792 patrones; 593,717 filas de `pattern_stops`; 331,294 puntos de `shapes`;
  - 2,221,182 filas de `stop_times`.
- Estimado de tamaño de la BD (schema replicado + datos reales, mejor espacio
  SQLite por fila con ids TEXT): **186,1 MB**.

## Versión del esquema

- `user_version = 7` (`TransitDatabase._databaseVersion`).
- `TransitDatabase.open()` valida `PRAGMA user_version`; si no coincide, cierra
  y migra vía `onUpgrade` (flujo actual).

## Shrink del esquema: ids de patrones surrogate (`a` -> mejor tamaño)

Esquema anterior (ids textuales): `trips.pattern_id`, `pattern_stops.pattern_id`
y `trip_patterns.pattern_id` eran cadenas SHA-256 de 64 caracteres.

- Nuevo: `trips.pattern_id INTEGER`, `pattern_stops.pattern_id INTEGER`,
  `trip_patterns(id INTEGER PRIMARY KEY AUTOINCREMENT)`.
- `Trips` a nivel de app queda con `patternId` String (opaco) —
  `SqfliteTransitRepository` lo lee vía `row['pattern_id']?.toString()` y
  `stopsForVariant` compara con `ps.pattern_id` (afinidad INTEGER — funciona).
- Estimado medido: **-67% del tamaño de la BD** (~186 MB -> ~61.5 MB).

Opciones descartadas/opcionales:

- Shapes codificadas como blobs por shape (`shapes(shape_id TEXT PRIMARY KEY,
  points_blob BLOB)`): ahorro estimado ~10-15 MB adicionales; cambia
  `shapeForVariant` (decodificar JSON).
- Índices innecesarios: `variants_external_id` se usa (`variantByExternalId`).

## Semilla (seed): generación y uso

- Builder: `dart run tool/build_seed_db.dart` — builder puro en Dart
  (`gtfs_parser` + `sqlite3` — sin Flutter), replicando `TransitDatabase.replaceFeed()`
  con el esquema surrogate.
- CI: `.github/workflows/build_release_apk.yml` descarga y genera la seed
  dentro del mismo workflow de release; falla si no existe `feed_end_date` o
  quedan menos de siete días completos de vigencia. El artifact de seeds se
  retiene 7 días para transferirlo entre jobs del mismo run. El APK publicado
  como asset de GitHub Release no depende de la retención del artifact.
- `.github/workflows/build_seed_db.yml` sigue siendo el chequeo diario
  independiente para observar el feed.
- Instalación: `FeedUpdateController._loadData()` → si la DB está vacía o
  insusable: `TransitDatabase.installSeed()` (copia atómica temp+rename,
  progreso visible) → `open()` → `hasUsableFeed` → marca
  `transit_last_check_ms` (evita re-descarga inmediata del zip).
- Segundo arranque: DB cacheada usable → sin refresh (24 h).

## Actualizaciones posteriores

- `_checkForUpdate()` no inicia el refresh del GTFS si solo hay datos móviles
  (o sin conexión) — se reintenta al siguiente arranque.
- El refresh conectado (24 h): `GtfsZipSource.download()` + `replaceFeed()` —
  el esquema nuevo asigna surrogates desde cero — los ids textuales del feed
  parser se pierden (internos de la BD) — aplicación compatible.

## Referencias de medición

- Parse del feed real: `parseGtfsZipFileToFile` = 9,271 ms / 9,595 ms
  (Dart 3.13.7, Windows 11, 2 runs) — 2.2M `stop_times`.
- Estimado `replaceFeed` (import): ~1-3 s (estimado — requiere app/emulador).
- Descarga proxy (frio, Render asleep): 38.47 s (medido); `/health`: 16.35 s.
- Nominatim (upstream del proxy `/geocode`): 1.105 s (query real, limit=5).
- Emulador (docs/rendimiento.md): feed cacheado disponible = 1.005 s.

## Apéndice: tabla de tiempos antes/después (opt. (a) — seed)

| Métrica | Antes (est.) | Después (medido) | Δ |
|---|---|---|---|
| Tamaño DB | ~186 MB | 60.5 MB | -67% (~125 MB) |
| First install: descarga GTFS (proxy) | 38.5 s (medido) | 0 (seed en bundle) | -38.5 s |
| First install: parse GTFS | 9.6 s (medido) | 0 (seed preconstruido) | -9.6 s |
| First install: buscador tappable | ~0.2-0.5 s | ~0.3 s (open de DB) | similar |
| First install: sugerencias de direcciones | vacías hasta fin de import (est.) | con paradas/líneas (DB usable) | resuelto |
| First install: planificar ruta (`findPlans`) | bloqueado ~40-55 s est. | ~1-2 s (DB usable) | -40-53 s |
| Segundo arranque: feed disponible | ~1.0 s (emulador) | ~0.3 s (est.) | -0.7 s |
| APK arm64 | 32.9 MB (docs, pre-R8 del usuario) | 54.1 MB | +21.2 MB |

La cifra de 54,1 MB es histórica. La medición posterior del APK arm64-only es
59.686.223 bytes (59,69 MB decimales = 56,91 MiB); el APK multiplataforma de
76.248.671 bytes (76,25 MB = 72,72 MiB) incluye además bibliotecas x86_64 y
armeabi-v7a. Ver los detalles y entradas pesadas en
[`rendimiento.md`](rendimiento.md).
