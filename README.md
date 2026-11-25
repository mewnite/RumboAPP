# Rumbo

App móvil de transporte público para Montevideo, Uruguay. La V1 prioriza una
experiencia mobile-first, sin anuncios ni rastreadores, con ubicación procesada
en el dispositivo.

[![Build release APK](https://github.com/mewnite/RumboAPP/actions/workflows/build_release_apk.yml/badge.svg)](https://github.com/mewnite/RumboAPP/actions/workflows/build_release_apk.yml)

## Descargar Rumbo para Android

La forma más sencilla de probar Rumbo es instalar una versión publicada:

- **[Abrir la última release](https://github.com/mewnite/RumboAPP/releases/latest)**
- **[Descargar Rumbo v1.0.2 APK](https://github.com/mewnite/RumboAPP/releases/download/v1.0.2/app-release.apk)** 
- En la página de release, descargá el archivo cuyo nombre termine en
  `-arm64-v8a-release.apk` para teléfonos Android actuales; elegí
  `-armeabi-v7a-release.apk` o `-x86_64-release.apk` solo si tu dispositivo lo
  requiere.
- Transferilo al teléfono si hace falta y abrilo desde Archivos/Descargas.
- Android puede solicitar autorización para instalar aplicaciones de fuentes
  desconocidas. Después abrí **Rumbo** y concedé solo los permisos que quieras
  usar.

Las APK no requieren ADB ni Android Studio. El release incluye una seed GTFS y
una seed binaria peatonal generadas en CI, por lo que la planificación inicial
no depende de descargar ni parsear esos datasets. Las búsquedas remotas y los
datos en vivo sí requieren conexión. Verificá siempre el origen del archivo
antes de instalarlo.

> Las releases se generan automáticamente desde etiquetas `v*`. El APK actual
> puede cambiar hasta que se configure una clave de firma de producción.

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

### Pruebas asistidas en Android

El proyecto puede ejecutarse en un AVD de Android Studio y conectarse al
Flutter VM Service. Esto permite repetir escenarios reales de la app, hacer
hot reload/hot restart, consultar errores runtime, revisar logs de Android y
medir el arranque o la memoria sin incluir credenciales en el APK.

1. Iniciá un AVD desde Android Studio o listá los disponibles:

   ```powershell
   flutter emulators
   flutter emulators --launch Medium_Phone_API_37.0
   ```

2. Confirmá que Flutter y ADB lo detecten:

   ```powershell
   flutter devices
   adb devices -l
   ```

3. Ejecutá Rumbo en modo debug:

   ```powershell
   flutter run -d emulator-5554
   ```

   Si se usa un teléfono físico con el proxy local, agregá el `adb reverse`
   y el `--dart-define` indicados en [Datos de transporte](#datos-de-transporte).

4. Mientras `flutter run` está activo, VS Code o las herramientas de Dart
   pueden conectarse al VM Service para hot reload, inspección y errores
   runtime. También se pueden recoger logs sin secretos:

   ```powershell
   adb logcat -s flutter ActivityManager AndroidRuntime
   ```

Escenarios recomendados: primer arranque y mapa, búsqueda local+online,
consentimiento de geocodificación, tema claro/oscuro, ubicación y permisos,
planificación, shapes de recorridos, buses en vivo y viaje activo. Las
interacciones visuales, permisos del sistema, notificaciones y comportamiento
de batería deben marcarse como verificados solo después de observarlos en el
emulador o en un dispositivo físico. El emulador no reemplaza la validación
de GPS real, sensores, rendimiento térmico ni permisos «Siempre».

Para compilar un APK de depuración:

```sh
flutter build apk --debug
```

Para un APK release optimizado, separado por ABI y con símbolos de depuración
fuera del paquete:

```sh
flutter build apk --release --split-per-abi \
  --obfuscate --split-debug-info=build/symbols
```

R8 y la eliminación de recursos están activados para el tipo `release` de
Android. El archivo `android/app/proguard-rules.pro` queda disponible para
reglas específicas si una biblioteca nativa las requiere.

### Publicar una release descargable

El workflow [Build release APK](./.github/workflows/build_release_apk.yml)
genera y valida seeds GTFS/peatonal, ejecuta análisis y pruebas y publica APK
separados por ABI al publicar una etiqueta:

```powershell
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions crea o actualiza una release y adjunta, por ejemplo,
`Rumbo-v1.0.0-arm64-v8a-release.apk` en **Releases**. El job exige que el
`feed_end_date` del GTFS deje al menos siete días completos de vigencia. Las
seeds se comparten solo entre jobs del mismo workflow run (retención del
artifact: 7 días); no se dependen de artifacts de ejecuciones anteriores.
También puede iniciarse a mano desde **Actions → Build release APK → Run
workflow**, indicando la etiqueta deseada.
Hasta configurar una firma de producción, el APK usa el entorno de firma
configurado actualmente por el proyecto; no es necesario editar credenciales
en Flutter ni incorporar secretos al repositorio.

### Obtener las seeds en local

La seed peatonal no está versionada. Para generarla desde el extracto de OSM
fijado en el manifiesto (requiere Python y `osmium-tool` 1.16):

```powershell
python tool/fetch_seeds/fetch_seeds.py
Copy-Item build/seeds/walk_graph_seed.bin assets/walk_graph/walk_graph_seed.bin -Force
```

El comando verifica el SHA-256 del extracto y deja el binario y su manifiesto
en `build/seeds/`. Para generar también la seed GTFS hace falta que
`transitConfig.url` apunte al proxy/feed autorizado; luego se ejecuta
`dart run tool/build_seed_db.dart`. El generador rechaza feeds vencidos o con
menos de siete días de vigencia. No se deben commitear los binarios generados.

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
tema claro, oscuro o del sistema persiste localmente; texto e íconos usan los
colores de contraste del tema activo.

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
que se visualiza. La explicación previa al primer uso se recuerda localmente;
las coordenadas siguen solo en memoria mientras se usa la app.

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
`lib/core/config/transit_config.dart`. Los builds normales usan por defecto el
backend HTTPS público `https://rumboapp.onrender.com`, tanto en debug como en
release. Por eso un APK instalado manualmente en un teléfono con conexión a
Internet no necesita proxy local, `adb` ni Android Studio durante el uso.
`RUMBO_API_BASE_URL` permite reemplazarlo explícitamente para desarrollo.

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
  La búsqueda local responde al escribir. La búsqueda de direcciones y lugares
  en línea empieza al tocar un botón y aceptar el aviso; esa preferencia se guarda
  para las siguientes búsquedas. Las consultas se contextualizan en Montevideo y
  admiten cruces como `18 de Julio y Ejido`. Los números de puerta y los cruces
  que el proveedor no confirma se muestran como aproximados. Dispone de debounce
  y descarta consultas obsoletas.
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

El workflow de release genera una seed SQLite desde el feed configurado y la
empaqueta con la app. El job falla si falta `feed_end_date` o quedan menos de
siete días de vigencia. Así el primer plan no espera la descarga ni el parseo
del GTFS; actualizaciones posteriores siguen según la política de conexión de la
app.

Al elegir cualquier lugar/dirección el planificador usa sus coordenadas para
encontrar paradas de acceso y propone alternativas con hasta un transbordo. La
muestra incluida es sintética y no debe usarse para orientar viajes reales.
Cada resultado resume salida, llegada, duración, líneas, caminata y transbordos
con horarios programados. Al elegir una alternativa, el mapa conserva el
recorrido y muestra una línea de tiempo de salida, caminata, abordaje, bajada y
llegada, con las horas estimadas rotuladas. En los releases, la red peatonal se
empaqueta como seed binaria derivada de un extracto Geofabrik fechado; la app
no depende de Overpass ni descarga un JSON vial al planificar. Dijkstra consulta
una base CSR inmutable y usa un overlay por consulta. Si la seed falta o un snap
no encuentra una conexión, se muestra un tramo recto punteado marcado como
aproximado y se estima su distancia con un factor de desvío 1,3. Los horarios
son programados, no posiciones ni ETA en vivo. Cada
tramo peatonal indica desde dónde caminar, hacia qué parada o dirección y la
distancia aproximada; no ofrece giros por calles. La API pública STM no publica
un endpoint de geometría ni planificación A→B: el trazo usa shapes GTFS y las
posiciones en vivo se dibujan aparte. Por eso el trazado no se puede prometer
como 100 % confiable; depende de la cobertura y del cruce entre variante STM y
GTFS.

La seed derivada de OpenStreetMap está bajo ODbL 1.0. El mapa muestra
«© OpenStreetMap contributors» con enlace a
https://www.openstreetmap.org/copyright y también atribuye a OpenFreeMap y
OpenMapTiles. El extracto y su hash se registran en
[docs/walk_graph_seed_manifest.json](./docs/walk_graph_seed_manifest.json).
La generación reproducible está documentada en
[docs/walk_graph_seed.md](./docs/walk_graph_seed.md).

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
solicita ubicación y notificaciones en ese momento. En Android usa el servicio
de ubicación en primer plano con su notificación persistente; en iOS requiere
acceso de ubicación «Siempre» para continuar con la app cerrada. La notificación
local inicial muestra cuántas paradas quedan y se actualiza durante el viaje.
Rumbo guarda en el dispositivo la secuencia pública de paradas elegida y el
avance para recuperar el mismo viaje al volver a abrir la app; no guarda la
ubicación precisa. En iOS,
Rumbo actualiza avisos locales y usa el indicador del sistema para ubicación en
segundo plano. La posición se procesa localmente; el seguimiento termina al
finalizarlo explícitamente o al elegir cambiar de plan.

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
flutter build apk --release --dart-define=RUMBO_API_BASE_URL=https://rumboapp.onrender.com
```

Si se configura explícitamente el proxy local, en el emulador Android alcanza
con `flutter run -d emulator-5554`; la app usa `10.0.2.2` para llegar al proxy
del host. La primera actualización descarga el ZIP GTFS oficial y lo importa a
SQLite; el proceso muestra el avance y puede demorar según el teléfono. En una
prueba de depuración del emulador tardó alrededor de 3 minutos para 4.930
paradas y 2.221.437 horarios. Las siguientes aperturas reutilizan la base
local. Permití ubicación desde el botón del mapa para
centrarlo. Los buses se descargan sin enviar coordenadas y se filtran en el
teléfono alrededor de esa posición. Si el panel informa que no hay unidades,
puede que no haya buses reportando en ese instante; la API también puede
devolver `[]` sin que sea un error de autenticación. En debug se habilita HTTP
solo para este proxy local; una compilación de producción debe usar un backend
HTTPS propio y revisar antes las condiciones de uso del feed y de la API.

### Probar un APK real sin proxy local ni ADB

Esta es la opción recomendada para probar Rumbo en un teléfono físico sin
dejar una computadora encendida:

1. Compilá un APK release universal desde la raíz del proyecto. No agregues
   `RUMBO_API_BASE_URL` si querés usar Render:

   ```powershell
   flutter build apk --release `
     --obfuscate --split-debug-info=build/symbols
   ```

   El archivo queda en
   `build\app\outputs\flutter-apk\app-release.apk`. También podés generar
   APK más pequeños separados por arquitectura con
   `--split-per-abi`; en ese caso elegí el ABI compatible con tu teléfono.

2. Transferí `app-release.apk` al teléfono por Drive, correo, cable, tarjeta
   SD u otro medio. No hace falta habilitar depuración USB ni ejecutar
   `adb reverse`.

3. Abrí el APK desde el teléfono y autorizá la instalación de fuentes
   desconocidas si Android lo solicita. Luego abrí Rumbo con Wi-Fi o datos
   móviles activos.

4. En la primera apertura, la app descargará el GTFS oficial desde Render y lo
   importará localmente. Esa importación puede demorar y ocupar espacio; las
   siguientes aperturas reutilizan la base local. Los buses en vivo y la
   búsqueda de direcciones usan también `https://rumboapp.onrender.com`.

5. Si el APK muestra error de red, verificá primero
   `https://rumboapp.onrender.com/health` desde el navegador del teléfono.
   Render puede dormir después de un período sin tráfico y tardar en despertar.
   No incluyas credenciales STM en `--dart-define`, el APK ni el repositorio.

Este flujo prueba el binario y la red como una persona usuaria real. No permite
hot reload, logs de Flutter ni inspección de errores desde la computadora; para
eso se necesita `flutter run` con un emulador/dispositivo conectado. La
ubicación, notificaciones, rendimiento, batería y permisos de segundo plano
deben validarse en el teléfono físico porque el emulador no los representa por
completo.

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

### Publicar el proxy en Render

Para compartir buses en vivo, el proxy se puede desplegar como Web Service en
Render usando el [render.yaml](./render.yaml). Configurá `CLIENT_ID` y
`CLIENT_SECRET` como variables privadas; nunca los agregues al repositorio ni
al APK. Render proporciona `PORT` automáticamente y el proxy lo usa para
escuchar en todas las interfaces.

Después del despliegue, verificá `https://<servicio>.onrender.com/health` y
compilá el APK con:

```powershell
flutter build apk --release `
  --dart-define=RUMBO_API_BASE_URL=https://<servicio>.onrender.com
```

El plan gratuito puede suspender el servicio tras 15 minutos sin tráfico y
tardar alrededor de un minuto en reactivarlo. El proxy aplica una caché de 10
segundos para las posiciones.
