# Rumbo

App móvil de transporte público para Montevideo, Uruguay. La V1 prioriza una
experiencia mobile-first, sin anuncios ni rastreadores, con ubicación procesada
en el dispositivo.

## Requisitos

- Flutter SDK estable y Dart incluidos con Flutter.
- Android Studio o un Android SDK para ejecutar en Android.
- macOS con Xcode para compilar o ejecutar en iOS.

## Instalar dependencias

```sh
flutter pub get
```

La interfaz usa español de Uruguay (`es-UY`) y tipografía Inter guardada en
`assets/fonts/`; no descarga fuentes durante la ejecución.

## Ejecutar

Con un emulador iniciado o un dispositivo conectado:

```sh
flutter run
```

Para depurar la interfaz en Chrome:

```sh
flutter run -d chrome
```

Para compilar un APK de depuración:

```sh
flutter build apk --debug
```

## Análisis y pruebas

```sh
dart format .
flutter analyze
flutter test
```

## Base actual

La navegación tiene las pestañas Mapa, Favoritos y Ajustes. Mapa muestra
OpenFreeMap en Montevideo, atribución, el estado de conexión y controles de
ubicación bajo demanda. Cuando se configura el proxy local, consulta las
posiciones de la flota STM cada 10 segundos y filtra en el dispositivo las
unidades a 2 km del centro actual; no dibuja la flota como puntos sobre el mapa.
El panel puede listar hasta ocho unidades cercanas con destino, línea, velocidad
y hora de recepción; no es una ETA ni un horario de llegada a parada. También
lista las paradas cercanas y sus líneas GTFS; al expandir una línea se pueden
ver sus destinos y dibujar la geometría del recorrido elegido. El selector de
tema claro, oscuro o del sistema persiste localmente.

Favoritos permite guardar paradas y líneas, definir Casa y Trabajo con el
buscador existente y abrirlas desde la pestaña o desde los atajos del mapa.
Tocar un lugar lo usa como destino del planificador, una línea se dibuja en el
mapa y una parada abre su detalle. La lista se guarda como JSON en
`shared_preferences`, solo en el dispositivo: no se envía a ningún servidor.
Deslizar un favorito lo elimina y ofrece «Deshacer»; mantener presionado
permite renombrarlo.

Las dos variantes de estilo, la atribución y el centro/zoom se cambian en
`lib/core/config/map_config.dart`. OpenFreeMap no requiere clave, pero ofrece el
servicio sin SLA; revisar sus términos y capacidad antes de un lanzamiento con
tráfico significativo. La ubicación precisa no se guarda ni se envía desde
Rumbo; las peticiones de teselas pueden revelar al proveedor la zona aproximada
que se visualiza.

En Android, declarar los permisos ya incluidos en `android/app/src/main/` y
aceptar las licencias del SDK local si Flutter lo solicita. En iOS, abrir el
proyecto en Xcode para resolver Swift Package Manager antes de ejecutar.

Las features del proyecto están en `lib/features/`. El parser GTFS, los modelos
de transporte y la base SQLite están en `stops_and_lines`. `trip_planner`
contiene el motor Dart puro para alternativas directas y con un transbordo,
incluidos calendarios GTFS y horarios posteriores a medianoche. El buscador de
viajes está conectado: permite elegir una parada o buscar un lugar/dirección y
planifica usando sus coordenadas y el GTFS local.

## Datos de transporte

La URL, el nombre de fuente, la atribución y el intervalo mínimo se declaran en
`lib/core/config/transit_config.dart`. En debug Android, la URL apunta por
defecto al host del emulador `10.0.2.2:8765`; en Chrome y otras plataformas usa
`127.0.0.1:8765`. Iniciá el proxy antes de abrir la app. En un teléfono físico
conectado por USB, usá `adb reverse tcp:8765 tcp:8765` y configurá
`--dart-define=RUMBO_API_BASE_URL=http://127.0.0.1:8765`. Si el proxy no está
disponible, Rumbo muestra el estado de conexión y no sustituye los datos reales
con recorridos inventados.

El GTFS oficial aporta paradas, recorridos, variantes y horarios; Android/iOS
lo guardan en SQLite. En Chrome se consulta el mismo feed, se indexan sus
patrones en memoria y se usan para paradas, recorridos y planificación, ya que
SQLite no está disponible allí. Los buses y las consultas de arribos son otra
parte: se obtienen por la API STM a través del proxy. Las credenciales nunca se
incluyen en Flutter ni en el APK.

La muestra sintética se usa solo cuando se pide explícitamente para revisar la
interfaz: `flutter run -d chrome --dart-define=RUMBO_DEMO_MODE=true`. No
representa servicios, paradas ni horarios reales del STM.

El buscador de destinos (`lib/features/search/`) es un motor híbrido inteligente
diseñado para movilidad urbana en Montevideo:
- **Búsqueda local:** Consulta paradas y líneas del GTFS oficial, en SQLite en
  Android/iOS y desde el índice compacto en memoria en Chrome.
- **Geocodificador remoto con gateway y caché:** Consulta direcciones completas con
  número de puerta, esquinas e intersecciones (`18 de Julio y Ejido`), POIs (facultades,
  hospitales, terminales) y barrios mediante un gateway configurable (`/geocode`).
  La búsqueda combina resultados de STM y lugares en línea automáticamente al
  escribir cuando está habilitada. La primera búsqueda de lugares solicita
  consentimiento, sin un botón aparte. Dispone de debounce y descarta consultas
  obsoletas.
- **Normalizador montevideano:** Parser puro (`MontevideoQueryParser`) con expansión de
  abreviaturas rioplatenses (`Av.`, `Bvar.`, `Cno.`, `Gral.`, `Dr.`), plegado de tildes
  y detección de intención (`stopCode`, `intersection`, `addressWithNumber`, `routeCode`).
- **Ranking multicriterio y deduplicación:** Puntuación ponderada que favorece coincidencias
  textuales exactas, códigos oficiales del STM, precisión cadastral y cercanía solo si
  el usuario concedió permisos. Deduplica paradas y direcciones idénticas a menos de 25 m.
- **Privacidad estricta:** La ubicación precisa se procesa únicamente en el dispositivo
  para desempatar resultados; nunca se envía a los servidores de geocodificación.
- **Resiliencia sin conexión:** En modo avión o sin red, la interfaz notifica el estado
  offline y responde de inmediato con las paradas y líneas almacenadas localmente.

### Objetivo de tiempo de planificación

La ruta de planificación no debe esperar una actualización del feed: en Android e
iOS usa la última base GTFS oficial válida guardada en SQLite, y la actualización
se ejecuta en segundo plano. La búsqueda y el planificador reutilizan la misma
conexión SQLite durante la sesión para evitar reaperturas y consultas de
inicialización innecesarias; el cálculo de rutas se ejecuta fuera del hilo de UI.

Esto permite que los arranques posteriores y las búsquedas con caché local sean
inmediatos. En una instalación sin una base oficial previa, la primera descarga e
importación depende del tamaño del ZIP y no puede garantizar menos de 10 segundos.
Para garantizar ese objetivo también en el primer arranque, el pipeline de release
debe generar y distribuir un snapshot SQLite oficial versionado junto con la
aplicación, sustituyéndolo mediante actualización en segundo plano cuando cambie
el feed. No se incluye un snapshot inventado ni una URL oficial no confirmada.

Al elegir cualquier lugar/dirección el planificador usa sus coordenadas para
encontrar paradas de acceso y propone alternativas con hasta un transbordo. La
muestra incluida es sintética y no debe usarse para orientar viajes reales.
Cada resultado resume salida, llegada, duración, líneas, caminata y transbordos
con horarios programados. Al elegir una alternativa, el mapa conserva el
recorrido y muestra una línea de tiempo de salida, caminata, abordaje, bajada y
llegada, con las horas estimadas rotuladas. En el mapa, los tramos de ómnibus
son continuos y los peatonales punteados. Las distancias a pie son
aproximaciones en línea recta y el trazo del ómnibus une paradas de forma
esquemática; los horarios son programados, no posiciones ni ETA en vivo. La app
no brinda guía paso a paso; el viaje activo avisa cuándo acercarse a la parada de bajada.

Para regenerar el ZIP pequeño y el fixture GeoJSON sintético, ejecuta
`python tool/generate_sample_gtfs.py`. El archivo identifica el feed como prueba;
ningún nombre de parada, recorrido, código de variante ni posición representa
servicio real. Los puntos de ejemplo se generan cerca del centro del mapa de
Montevideo configurado en Rumbo.

Los códigos `externalVariantId` se leen de `variant_id` opcional en `trips.txt`;
si falta, el importador busca `variant_map.csv` con `trip_id` o `shape_id` y
`external_variant_id`. Si no hay código se conserva la variante y se anota una
advertencia, pero no se asocia con un vehículo. En tests se usa un código fake.

El cliente de tiempo real consume `GET /api/buses?format=geojson` a través del
proxy local (que reenvía a `/buses` del upstream); no usa `/buses/geo`, marcado
como obsoleto en el manual de la API.
El parser asigna la hora local de recepción y conserva `frecuencia`/`version`
como campos raw sin interpretar. El mapa dibuja hasta 60 marcadores de buses visibles de la API; con GTFS cargado prioriza las líneas de las paradas del área. El filtrado de zona ocurre localmente en el dispositivo.

### Viaje activo y avisos de bajada

Al abrir un plan con tramos de ómnibus, toca **Iniciar viaje con avisos**. Rumbo
solicita el permiso de ubicación en segundo plano y notificaciones en ese momento.
En Android, la notificación persistente muestra las paradas restantes; en iOS,
Rumbo actualiza avisos locales y usa el indicador del sistema para ubicación en
segundo plano. La posición se procesa localmente; el seguimiento termina al
finalizar el viaje, cambiar el plan o cerrar el detalle.

### Verificar acceso de desarrollador a Montevideo API

Para probar credenciales sin incorporarlas al APK, guardá `CLIENT_ID` y
`CLIENT_SECRET` de la aplicación del portal en el `.env` local. El `.env` está
excluido de Git. No compartas esos valores ni los agregues a código Flutter.

Desde PowerShell, ejecutá `python tool/test_montevideo_api.py`. El script usa
OAuth Client Credentials, realiza una única consulta a la línea 522 (ejemplo
del manual de Montevideo API) y nunca imprime el access token. Para otra línea,
usá `python tool/test_montevideo_api.py --line NUMERO`. Si la consulta responde,
podés compartir el status y el JSON, revisando igualmente que no haya datos
sensibles.

La integración móvil aún necesita un backend intermediario que mantenga las
credenciales fuera del APK y aplique un límite global. El límite inicial
propuesto para la app es como máximo una consulta de refresco cada 10 segundos;
no debe confundirse con un límite oficial publicado por la Intendencia.

### Probar GTFS oficial y buses en vivo en un Android conectado por USB

El proxy de desarrollo escucha solo en `127.0.0.1:8765`. La búsqueda de lugares
puede usarse sin credenciales STM. Para GTFS y buses, lee `CLIENT_ID` y
`CLIENT_SECRET` del `.env`, obtiene y renueva el token OAuth sin imprimirlo, y
descarga/cacha el GTFS por 24 horas. Para la flota en vivo impone un máximo
global de una consulta cada 10 segundos y limita los parámetros/endpoints
permitidos. No es un backend de producción ni debe exponerse a la red.

En PowerShell, con el teléfono conectado y depuración USB habilitada:

```powershell
python tool/montevideo_api_proxy.py
```

En otra terminal:

```powershell
adb devices -l
adb reverse tcp:8765 tcp:8765
flutter run -d <ID-del-dispositivo> --dart-define=RUMBO_API_BASE_URL=http://127.0.0.1:8765
```

En el emulador Android alcanza con `flutter run -d emulator-5554`; la app usa
`10.0.2.2` para llegar al proxy del host. La primera actualización descarga el ZIP GTFS oficial y lo importa a SQLite; el proceso muestra el avance y puede demorar según el teléfono. En una prueba de depuración del emulador tardó alrededor de 3 minutos para 4.930 paradas y 2.221.437 horarios. Las siguientes aperturas reutilizan la base local. Permití ubicación desde el botón del mapa para
centrarlo. Los buses se descargan sin enviar coordenadas y se filtran en el
teléfono alrededor de esa posición. Si el panel informa que no hay unidades,
puede que no haya buses reportando en ese instante; la API también puede
devolver `[]` sin que sea un error de autenticación. En debug se habilita HTTP
solo para este proxy local; una compilación de producción debe usar un backend
HTTPS propio y revisar antes las condiciones de uso del feed y de la API.

La prueba aislada midió menos de un segundo para parsear desde disco e importar a SQLite el
ZIP sintético de 2.202 bytes (18 paradas, 3 líneas, 6 variantes y 48 horarios)
en este equipo. No representa un feed real.
En el emulador Android de prueba se importó el feed oficial servido por el
proxy: 4.930 paradas, 325 líneas, 37.451 viajes, 2.221.437 horarios y 332.505
puntos de shape. La base resultante ocupó 198 MB y el proceso completo tardó
alrededor de 3 minutos en la versión anterior de depuración; la revisión actual
evita patrones duplicados y escrituras temporales redundantes. El cambio final
de journaling aún no se midió con una instalación limpia.
En Android/iOS la descarga estática se escribe a disco; un isolate descomprime
`stop_times.txt` a un archivo temporal y la procesa en bloques de 64 KiB. El
parser conserva patrones de horario deduplicados, que SQLite importa en lotes
de 500 dentro de una transacción, sin crear otra copia de millones de horarios.
Las tablas GTFS restantes sí se parsean en memoria. El tiempo en un teléfono
físico todavía no se midió.
