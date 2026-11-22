# Seed binaria de la red peatonal

## Fuente reproducible

La seed se genera en CI a partir del extracto recortado y fechado publicado en
la release indicada en [`tool/fetch_seeds/manifest.json`](../tool/fetch_seeds/manifest.json),
no desde `latest` ni desde Overpass:

- Extracto: `montevideo-261121.osm.pbf`, fecha 21/11/2026; publicado como asset
  de la release [v1.0.0](https://github.com/mewnite/RumboAPP/releases/tag/v1.0.0).
- Tamaño: 14.358.148 bytes. SHA-256:
  `a9fa9f6368ab79708ae2640672ebe4799a5569b291d2f253ec81c7a1af3266b2`.
- Procede del extracto `uruguay-261121.osm.pbf` de Geofabrik, SHA-256
  `3f123c0872aaa1b463738ec645d64d55a61fd209dd54ce04cc2e140448eb2b28`.
- Bbox del recorte de Montevideo: oeste `-56.4548`, sur `-34.9771`, este
  `-55.9455`, norte `-34.6667`.
- La fecha, hashes, bbox, conteos del grafo y hash del binario quedan registrados
  en [`walk_graph_seed_manifest.json`](walk_graph_seed_manifest.json), generado
  por el workflow de release. El PBF y el binario no se commitean.

`tool/fetch_seeds/fetch_seeds.py` descarga el PBF solo si no existe en la caché
local, verifica el hash, ejecuta `osmium extract` con `complete_ways`, filtra
objetos con `highway`, y usa `osmium export` para producir GeoJSON. El adaptador
normaliza sus `LineString` al formato de entrada del parser Dart existente.
El parser incluye vías peatonales permitidas; excluye `foot=no`,
`access=private`, barreras `wall`/`fence`, `construction` y `proposed`.
`motorway`, `motorway_link`, `trunk` y `trunk_link` solo se incluyen con
`foot=yes`. No usa `motor_vehicle` como restricción peatonal.

## Formato `RWB1`

La cabecera little-endian identifica la versión, fecha y SHA-256 del extracto,
bbox, conteos, offsets y longitudes de cada sección. El payload serializa:

1. coordenadas de vértices como pares `Int32` en microgrados;
2. extremos de cada arista como índices `Int32`;
3. longitud de arista como `Float32` en metros;
4. offsets CSR de geometría por arista;
5. coordenadas de la geometría como pares `Int32` en microgrados;
6. offsets CSR de adyacencia por vértice;
7. IDs de arista adyacentes como `Int32`;
8. SHA-256 del archivo para detectar truncamiento o corrupción.

El índice espacial y el componente conectado principal no se serializan: se
reconstruyen al cargar la seed. El grafo base no se muta. Cada búsqueda crea un
overlay local para los puntos proyectados sobre las aristas; no vuelve a copiar
ni a modificar el grafo base durante Dijkstra.

La app no consulta Overpass ni descarga un JSON vial en tiempo de ejecución.
El workflow de release genera las dos seeds juntas, las transfiere entre jobs
del mismo run con un artifact de 7 días y las instala antes de compilar el APK.
El artifact de APK retiene 90 días; el APK publicado como asset de GitHub
Release queda disponible hasta que se elimine esa release. Builds locales sin
`walk_graph_seed.bin` registran el asset ausente y usan los tramos aproximados.

## Isolates y medición

En iOS/Android, un worker isolate persistente recibe la seed binaria una sola vez mediante
`TransferableTypedData`; mantiene el grafo CSR inmutable, el componente conexo
principal y el índice espacial. Búsquedas, cálculo de caminatas y
`refreshWalkingSegments` se envían como mensajes y construyen un overlay local
por consulta. No se copian los 108 mil vértices ni se reconstruye el índice en
cada plan. La carga puede completarse después del primer plan: mientras tanto,
se muestra el recorrido aproximado y luego se refinan los tramos. La prueba de
integración del worker usa `tester.runAsync`. La plataforma web usa un stub sin
isolate; la seed de release se genera para Android/iOS y no se incluye en el
checkout normal.

La app mide localmente y sin telemetría:

- `[performance] walk_seed_transfer_prepare`: copias de los arrays en el hilo
  que inicia la búsqueda;
- `[performance] walk_graph_worker_ready`: inicio del worker y carga inicial
  de la seed/index;
- `[performance] walk_graph_worker_search` y
  `[performance] walk_graph_worker_refresh`: operaciones por mensaje;
- `[performance] walk_graph_path`: búsqueda local dentro del worker;
- `[performance] walk_seed_json_decode`: `jsonDecode` separado durante la
  generación del binario.

Los valores medidos por el generador y el tamaño/conteos reales de la seed se
guardan en el manifiesto enlazado arriba. Para medir en un teléfono, ejecutar
`flutter run --profile` y revisar esos logs; el tiempo de escritorio no se
presenta como rendimiento de Android.

En esta estación de desarrollo Windows, la regeneración más reciente midió
`jsonDecode` del JSON normalizado de 13.595.566 bytes en 395 ms por separado,
construcción del grafo en 1.252 ms y codificación binaria en 188 ms. La seed
mide 6.441.436 bytes (6,14 MiB). El inicio del worker midió 485–702 ms en las
ejecuciones recientes. Para un recorrido de referencia de 923,88 m (17
puntos), cinco búsquedas directas midieron 2,98–18,01 ms y cinco roundtrips
por worker 3,35–7,77 ms; el ping caliente midió 0,16–1,47 ms (la primera
muestra de cada worker puede incluir inicialización de reloj/puerto). Son
mediciones de escritorio, no de teléfono ni una garantía para rutas de
cualquier tamaño.

La medición previa de 6,1–7,9 s por esa consulta se debió a un error en la
conversión de 75 m a grados de longitud: se aplicaba el `clamp` a los metros
por grado, creando una ventana de 75 grados y examinando 6.000.008 celdas por
snap. Ahora se limita el coseno antes de multiplicar por 111.320 m/grado; el
mismo punto examina 72 celdas por snap. La medición histórica de reconstruir
componente e índice en cada búsqueda fue 321–670 ms (mediana 534 ms); con el
worker esa reconstrucción ocurre una sola vez al inicio. Falta medir todo en
un teléfono con `flutter run --profile` y revisar los logs `[performance]`.

Comparación determinística de 25 pares distintos de paradas GTFS de Montevideo
con el grafo mutable histórico (`bf50fa1`) y el actual, alimentados con la misma
entrada peatonal normalizada: 27.328 vías, SHA-256
`c5a78c84a070a2468e4617afd6bfac64a709471fab9439593b752bb143a3f10a`.
Ambos construyeron 107.885 vértices y 128.666 aristas. Se creó una instancia
histórica fresca para cada par. Con tolerancia
`max(15 m, 2% de la distancia histórica)`, 12/25 quedaron dentro; diferencia
absoluta media 30,71 m, mediana 30,24 m y máxima 75,85 m. La equivalencia sigue
sin resolverse.

El diagnóstico apunta al snapping, no a una diferencia de datos: el algoritmo
histórico aceptaba un vértice cercano antes de comparar la proyección sobre una
arista; además, su proyección de respaldo dividía diferencias en grados por
una distancia en metros al cuadrado. El algoritmo actual compara los vértices
y las proyecciones. Por ejemplo, en `3477→3233`, las distancias de snap
históricas suman 45,10 m y las proyecciones actuales 12,37 m; esto explica unos
32,73 m de los 75,85 m de diferencia, por lo que el snap por sí solo no explica
el resto.

Como referencia algorítmica independiente, un script Python hizo un barrido
completo para encontrar snaps y ejecutó Dijkstra con `heapq` sobre la CSR de la
seed. Coincidió con el grafo actual a menos de 0,01 m en estos cuatro pares:

| Par | Histórico (m) | Actual (m) | Python independiente (m) |
|---|---:|---:|---:|
| 3477→3233 | 1.262,49 | 1.186,63 | 1.186,63 |
| 3866→3944 | 1.447,49 | 1.519,32 | 1.519,32 |
| 1482→3724 | 906,95 | 966,80 | 966,80 |
| 3121→3452 | 707,82 | 734,99 | 734,99 |

Esta comprobación comparte la red CSR de la seed; valida independientemente
el snapping y Dijkstra actuales, pero no es una segunda fuente de calles ni
una comparación con navegación externa o recorridos reales. La diferencia
máxima de 75,85 m supera ligeramente la tolerancia de snap de 75 m y no queda
explicada solo por ella. Se agregó una regresión que verifica que una proyección
cercana se prefiera a vértices distantes. La equivalencia global y la validación
en teléfono siguen pendientes.

## Licencia y atribución

La seed es una base derivada de OpenStreetMap bajo ODbL 1.0. La atribución del
mapa debe mostrar «© OpenStreetMap contributors» con enlace a
https://www.openstreetmap.org/copyright y, además, mencionar OpenFreeMap y
OpenMapTiles. Cumplir las obligaciones ODbL aplicables a la distribución de
una base derivada; conservar juntos la fecha, el extracto y su hash para
identificar la procedencia.

## Caché del endpoint de respaldo

El proxy mantiene caché en memoria y en `RUMBO_CACHE_DIR`, sirve contenido
obsoleto si fallan el Overpass primario y el mirror configurable
`RUMBO_OVERPASS_MIRROR_URL`, y reintenta como máximo una vez por minuto tras
una falla. En Render Free el filesystem es efímero; el archivo no sobrevive
necesariamente reinicios. La app no depende de este endpoint porque usa la
seed incluida en el APK. El mirror configurado es una instancia pública
documentada, pero su disponibilidad actual no se confirmó; las pruebas cubren
el orden de fallback y stale-if-error con respuestas simuladas, no un upstream
en producción.
