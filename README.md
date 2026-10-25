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

La URL, el nombre de fuente, la atribución, la licencia y el intervalo mínimo
se declaran en `lib/core/config/transit_config.dart`. En debug Android, la URL
apunta por defecto al host del emulador `10.0.2.2:8765`; en otras plataformas
usa `127.0.0.1:8765`. El proxy debe estar ejecutándose. En un teléfono físico
conectado por USB, usá `adb reverse tcp:8765 tcp:8765` y configurá
`--dart-define=RUMBO_API_BASE_URL=http://127.0.0.1:8765`. En release no se
configura una API ni se incluyen credenciales. Sin proxy
configurado, la app carga `assets/sample_gtfs/sample_gtfs.zip`, un feed
sintético de demostración que no representa los servicios, paradas u horarios
reales del STM. El feed oficial y el tiempo real se habilitan solo para
desarrollo mediante el proxy local; las credenciales nunca se incluyen en
Flutter ni en el APK.

El buscador de destinos (`lib/features/search/`) es un motor híbrido inteligente
diseñado para movilidad urbana en Montevideo:
- **Búsqueda local instantánea:** Consulta la base SQLite de paradas y líneas GTFS
  en <10 ms por código de parada (ej. `4021`), nombre de parada o línea (`522`, `G`).
- **Geocodificador remoto con gateway y caché:** Consulta direcciones completas con
  número de puerta, esquinas e intersecciones (`18 de Julio y Ejido`), POIs (facultades,
  hospitales, terminales) y barrios mediante un gateway configurable (`/geocode`).
  Dispone de debounce de 200 ms, cancelación de consultas obsoletas para evitar carreras
  y caché LRU en memoria.
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
todavía no brinda guía paso a paso ni seguimiento de navegación en tiempo real.

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
como campos raw sin interpretar. El mapa dibuja hasta 60 marcadores de la
línea o parada seleccionada, filtrados por la zona visible en el dispositivo.

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

El proxy de desarrollo escucha solo en `127.0.0.1:8765`. Lee `CLIENT_ID` y
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
`10.0.2.2` para llegar al proxy del host. La primera actualización descarga el ZIP GTFS oficial y lo importa a SQLite;
puede tardar según el teléfono. Permití ubicación desde el botón del mapa para
centrarlo. Los buses se descargan sin enviar coordenadas y se filtran en el
teléfono alrededor de esa posición. Si el panel informa que no hay unidades,
puede que no haya buses reportando en ese instante; la API también puede
devolver `[]` sin que sea un error de autenticación. En debug se habilita HTTP
solo para este proxy local; una compilación de producción debe usar un backend
HTTPS propio y revisar antes las condiciones de uso del feed y de la API.

La prueba aislada midió 325 ms para parsear desde disco e importar a SQLite el
ZIP sintético de 2.202 bytes (18 paradas, 3 líneas, 6 variantes y 48 horarios)
en este equipo. No representa un feed real.
En Android/iOS la descarga estática se escribe a disco; un isolate descomprime
`stop_times.txt` a un archivo temporal, lo lee en bloques de 64 KiB y emite
filas JSONL. SQLite las importa en lotes de 500 dentro de una transacción. El ZIP
y la tabla completa de horarios no se retienen en memoria, pero las tablas GTFS
restantes sí se parsean en memoria. No se midió un feed oficial ni un archivo con
millones de horarios, por lo que su tiempo total y memoria siguen pendientes de
medición con una fuente confirmada.
