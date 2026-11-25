# 🚌 Rumbo

<p align="center">
  <strong>El transporte público de Montevideo, en un solo lugar.</strong>
  <br>
  Una alternativa abierta, mobile-first y pensada para moverse por la ciudad.
</p>

<p align="center">
  <a href="https://github.com/mewnite/RumboAPP/releases/latest">
    <img src="https://img.shields.io/github/v/release/mewnite/RumboAPP?style=for-the-badge&label=Versi%C3%B3n" alt="Última versión">
  </a>
  <a href="https://github.com/mewnite/RumboAPP/actions/workflows/build_release_apk.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/mewnite/RumboAPP/build_release_apk.yml?style=for-the-badge&label=Build" alt="Estado del build">
  </a>
  <img src="https://img.shields.io/badge/Android-Disponible-3DDC84?style=for-the-badge&logo=android&logoColor=white" alt="Android">
  <img src="https://img.shields.io/badge/Flutter-Dart-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Publicidad-Ninguna-2E8B57?style=for-the-badge" alt="Sin publicidad">
</p>

---

## 📱 ¿Qué es Rumbo?

Rumbo es una aplicación móvil de transporte público desarrollada para **Montevideo, Uruguay**.

Su objetivo es reunir en una sola aplicación las herramientas necesarias para desplazarse en ómnibus: consultar paradas, explorar líneas, buscar destinos y planificar viajes.

A diferencia de muchas aplicaciones de movilidad, Rumbo busca ofrecer una experiencia sin anuncios, sin rastreadores publicitarios y con un enfoque fuerte en la privacidad.

**Rumbo es un proyecto de código abierto, desarrollado con Flutter y conectado a los datos públicos del transporte de Montevideo.**

## ⬇️ Descargar Rumbo

<p align="center">
  <a href="https://github.com/mewnite/RumboAPP/releases/latest">
    <img src="https://img.shields.io/badge/DESCARGAR-Última%20versión-102B49?style=for-the-badge&logo=android&logoColor=white" alt="Descargar Rumbo">
  </a>
</p>

La forma más sencilla de instalar Rumbo es descargar una APK desde GitHub.

**Enlaces de descarga:**

- [🚀 Descargar última versión](https://github.com/mewnite/RumboAPP/releases/latest)
- [📦 Descargar Rumbo v1.0.2 APK](https://github.com/mewnite/RumboAPP/releases/download/v1.0.2/app-release.apk)
- [📋 Ver todas las versiones](https://github.com/mewnite/RumboAPP/releases)

### Cómo instalar

1. Entrá a la página de [Releases](https://github.com/mewnite/RumboAPP/releases/latest).
2. Descargá el APK correspondiente a tu dispositivo.
3. Para la mayoría de los teléfonos Android actuales, elegí `arm64-v8a`.
4. Abrí el archivo desde Descargas o Archivos.
5. Si Android lo solicita, autorizá temporalmente la instalación desde esa fuente.
6. Abrí Rumbo y concedé únicamente los permisos que quieras utilizar.

No necesitás ADB, Android Studio ni conectar el teléfono a una computadora.

> **Nota:** las APK se distribuyen desde el repositorio oficial de GitHub. Verificá siempre que el archivo provenga de `github.com/mewnite/RumboAPP` antes de instalarlo.

Los archivos de las releases incluyen una base inicial de transporte y una red peatonal empaquetadas. La búsqueda remota de lugares y los datos dinámicos necesitan conexión a Internet.

---

## ✨ ¿Qué podés hacer con Rumbo?

### 🗺️ Explorar Montevideo

Consultá el mapa de la ciudad, visualizá las paradas cercanas y explorá las líneas de transporte.

- Mapa basado en OpenStreetMap y OpenFreeMap.
- Ubicación del usuario bajo demanda.
- Paradas y líneas de transporte.
- Recorridos y variantes disponibles.
- Información de la flota que transmite posiciones a STM.

### 🔎 Buscar lugares y paradas

Encontrá destinos sin necesidad de conocer el nombre exacto de una parada.

Rumbo combina información local del transporte con búsqueda geográfica online.

Podés buscar:

- Paradas por nombre o código.
- Líneas de ómnibus.
- Direcciones con número de puerta.
- Intersecciones de calles.
- Barrios.
- Lugares de interés, como hospitales, facultades, terminales y otros puntos de referencia.

La búsqueda online se activa cuando el usuario la solicita y acepta el aviso correspondiente.

### 🚌 Consultar líneas y recorridos

Explorá las líneas disponibles y sus variantes.

- Identificá los destinos de cada línea.
- Consultá las paradas asociadas.
- Visualizá la geometría de los recorridos cuando esté disponible.
- Diferenciá variantes de una misma línea.

### 📍 Consultar ómnibus en vivo

Rumbo puede consultar las posiciones de los vehículos que transmiten información GPS a STM.

La disponibilidad depende de la transmisión de cada vehículo y de la API oficial.

Es importante distinguir entre una ubicación GPS reciente, una posición antigua y una estimación de llegada: no todos los ómnibus transmiten información en todo momento.

### 🧭 Planificar viajes

Ingresá un origen y un destino para obtener alternativas de transporte.

El planificador utiliza la información GTFS almacenada localmente y contempla:

- Alternativas directas.
- Viajes con hasta un transbordo.
- Horarios programados.
- Paradas de acceso y descenso.
- Distancias caminando.
- Geometría de los recorridos cuando está disponible.

Los resultados incluyen información sobre duración, caminatas, líneas y transbordos.

### 🚶 Calcular caminatas

Rumbo incorpora una red peatonal derivada de OpenStreetMap.

Utiliza un grafo local para calcular conexiones a pie entre lugares y paradas.

Cuando no es posible encontrar una conexión suficientemente confiable, puede mostrar un tramo aproximado, identificado como tal.

### ⭐ Guardar favoritos

Guardá tus lugares y accesos habituales.

- Paradas favoritas.
- Líneas favoritas.
- Casa.
- Trabajo.
- Accesos rápidos desde el mapa.

Los favoritos se almacenan localmente en el dispositivo.

### 🔔 Viaje activo y avisos

Podés iniciar un viaje con avisos de bajada.

Rumbo utiliza los permisos correspondientes para mantener el seguimiento del viaje y actualizar las notificaciones locales mientras está activo.

El usuario puede finalizar el seguimiento cuando quiera.

### 🎨 Personalizar la aplicación

Elegí cómo querés utilizar Rumbo:

- Tema claro.
- Tema oscuro.
- Tema del sistema.

La preferencia se guarda localmente.

---

## 🔐 Privacidad y transparencia

La privacidad es uno de los principios centrales de Rumbo.

| Característica | Comportamiento |
|---|---|
| Publicidad | No incluye anuncios |
| Rastreadores publicitarios | No incluye SDKs publicitarios ni trackers de terceros |
| Ubicación precisa | Se procesa en el dispositivo |
| Favoritos | Se guardan localmente |
| Credenciales STM | Permanecen en el backend |
| Búsquedas online | Se realizan tras consentimiento |
| Datos de transporte | Se consultan mediante el backend |

### ¿Cómo se utiliza tu ubicación?

La ubicación precisa se utiliza en el dispositivo para funciones como centrar el mapa, filtrar vehículos cercanos y contextualizar resultados.

Rumbo no envía tus coordenadas precisas al servicio de geocodificación.

Hay dos aspectos que conviene conocer:

- Las solicitudes de teselas del mapa pueden revelar al proveedor la zona geográfica que estás visualizando.
- Las búsquedas geográficas online envían el texto consultado al gateway y al proveedor correspondiente, una vez aceptado el consentimiento.

Los permisos de ubicación y notificaciones se solicitan cuando una funcionalidad los necesita, no como requisito para explorar toda la aplicación.

### ¿Qué ocurre sin conexión?

Rumbo puede consultar información de transporte almacenada localmente, incluyendo paradas, líneas y horarios que ya estén disponibles en su base de datos.

Las búsquedas geográficas online y los datos dinámicos de STM requieren conexión a Internet.

---

## 🧩 ¿De dónde salen los datos?

Rumbo combina diferentes fuentes para ofrecer información de transporte y geografía.

| Fuente | Utilización |
|---|---|
| STM / Intendencia de Montevideo | Posiciones de vehículos e información de transporte |
| GTFS oficial | Paradas, líneas, recorridos, variantes y horarios |
| OpenStreetMap | Datos geográficos y red peatonal |
| OpenFreeMap | Teselas del mapa |
| Photon | Búsqueda geográfica mediante el backend |

### Información importante sobre los datos

Los horarios GTFS son horarios programados. No representan necesariamente la posición real de un ómnibus ni su tiempo efectivo de llegada.

Las posiciones GPS dependen de que el vehículo esté transmitiendo información a STM.

La cobertura, precisión y disponibilidad de los datos pueden variar.

Rumbo intenta identificar el origen y la precisión de la información para no presentar una estimación como si fuera un dato confirmado.

---

## ⚙️ Tecnologías utilizadas

Rumbo está construido con tecnologías abiertas y herramientas orientadas al desarrollo móvil.

| Tecnología | Uso |
|---|---|
| Flutter / Dart | Aplicación móvil |
| SQLite | Base de datos local de transporte |
| GTFS | Datos estáticos del transporte |
| Python | Proxy y herramientas de datos |
| Render | Backend |
| API STM | Información oficial del transporte |
| Photon | Geocodificación |
| OpenStreetMap | Datos geográficos |
| OpenFreeMap | Visualización del mapa |
| GitHub Actions | Integración y compilación automatizada |

### Arquitectura general

```text
                  ┌───────────────────┐
                  │    Rumbo Flutter  │
                  │                   │
                  │  Mapa / Búsqueda  │
                  │  Planificación    │
                  │  Favoritos        │
                  └─────────┬─────────┘
                            │
              ┌─────────────┴─────────────┐
              │                           │
      ┌───────▼────────┐        ┌─────────▼────────┐
      │ Datos locales  │        │  Backend Render  │
      │                │        │                  │
      │ SQLite / GTFS  │        │ Proxy geográfico │
      │ Red peatonal   │        │ Proxy STM        │
      └────────────────┘        └─────────┬────────┘
                                          │
                              ┌───────────┴──────────┐
                              │                      │
                       ┌──────▼──────┐       ┌───────▼──────┐
                       │ API oficial │       │   Photon     │
                       │ STM / IM    │       │ Geocoding    │
                       └─────────────┘       └──────────────┘
```

---

# 👩‍💻 Desarrollo

¿Querés ejecutar Rumbo, revisar el código o contribuir al proyecto?

Esta sección contiene la información necesaria para configurar el entorno.

## Requisitos

- Flutter SDK estable.
- Dart, incluido con Flutter.
- Android Studio o Android SDK para Android.
- Xcode para compilar o ejecutar en iOS.
- Git.

## Instalar el proyecto

Cloná el repositorio:

```bash
git clone https://github.com/mewnite/RumboAPP.git
cd RumboAPP
```

Instalá las dependencias:

```bash
flutter pub get
```

## Ejecutar Rumbo

Con un emulador iniciado o un dispositivo conectado:

```bash
flutter run
```

Para ejecutar en Chrome:

```bash
flutter run -d chrome
```

Para listar los dispositivos:

```bash
flutter devices
```

## Compilar APK

APK de depuración:

```bash
flutter build apk --debug
```

APK de producción, optimizado y separado por arquitectura:

```bash
flutter build apk --release --split-per-abi \
  --obfuscate \
  --split-debug-info=build/symbols
```

Los archivos se generan en:

```text
build/app/outputs/flutter-apk/
```

## 🧪 Análisis y pruebas

Antes de enviar cambios, ejecutá:

```bash
dart format .
flutter analyze
flutter test
```

El proyecto también dispone de pruebas específicas para el backend:

```bash
python -m unittest tool.test_montevideo_api_proxy_test
```

Las pruebas automatizadas no reemplazan la validación visual y funcional en un emulador o teléfono físico.

---

## 🔌 Datos de transporte y backend

Los builds normales utilizan por defecto el backend HTTPS:

```text
https://rumboapp.onrender.com
```

La configuración del cliente se encuentra en:

```text
lib/core/config/transit_config.dart
```

Para desarrollo es posible reemplazar la URL mediante:

```text
RUMBO_API_BASE_URL
```

### API oficial de STM

La comunicación con STM se realiza a través de un backend intermediario.

Las credenciales OAuth:

```text
CLIENT_ID
CLIENT_SECRET
```

Deben permanecer en el servidor y nunca incluirse en Flutter, APK ni repositorios públicos.

### Ejecutar el proxy local

Para probar la integración con credenciales de desarrollador:

1. Creá un archivo `.env` con `CLIENT_ID` y `CLIENT_SECRET`.
2. Confirmá que `.env` esté excluido de Git.
3. Ejecutá:

```bash
python tool/montevideo_api_proxy.py
```

El proxy local escucha en `127.0.0.1:8765`.

Para un emulador Android, el host se alcanza mediante `10.0.2.2`.

Para un teléfono conectado por USB se puede utilizar:

```bash
adb reverse tcp:8765 tcp:8765
```

La configuración de la URL local debe realizarse mediante `RUMBO_API_BASE_URL`.

El proxy de desarrollo no debe exponerse a Internet ni utilizarse como backend de producción.

### Despliegue en Render

El servicio se configura mediante:

```text
render.yaml
```

Las variables privadas necesarias deben configurarse desde el dashboard de Render.

Después del despliegue, comprobá:

```text
https://rumboapp.onrender.com/health
```

El backend centraliza la comunicación con STM, mantiene las credenciales fuera del cliente y aplica límites de consumo y caché.

---

## 🗃️ Bases de datos y seeds

Las releases incluyen datos iniciales para evitar depender de una descarga y una importación completas durante el primer arranque.

### Seed de transporte

Se construye a partir del GTFS configurado.

Generación local:

```bash
dart run tool/build_seed_db.dart
```

La base se instala en SQLite y almacena la información necesaria para consultar paradas, líneas, horarios y variantes.

### Seed peatonal

La red peatonal se genera a partir de un extracto de OpenStreetMap.

Requiere Python y `osmium-tool` 1.16:

```powershell
python tool/fetch_seeds/fetch_seeds.py

Copy-Item build/seeds/walk_graph_seed.bin `
  assets/walk_graph/walk_graph_seed.bin -Force
```

Documentación:

- [Manifiesto de la seed peatonal](./docs/walk_graph_seed_manifest.json)
- [Proceso de generación](./docs/walk_graph_seed.md)

Los binarios generados localmente no deben agregarse al repositorio.

---

## 🚀 Publicar una nueva versión

Rumbo utiliza GitHub Actions para generar y publicar APK automáticamente.

Workflow:

[Build release APK](./.github/workflows/build_release_apk.yml)

Para crear una nueva versión:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

GitHub Actions se encarga de:

1. Generar las seeds necesarias.
2. Validar la vigencia del GTFS.
3. Ejecutar análisis y pruebas.
4. Compilar APK separados por arquitectura.
5. Publicar los archivos en GitHub Releases.

También es posible iniciar el workflow manualmente desde:

**GitHub → Actions → Build release APK → Run workflow**

La seed GTFS debe tener al menos siete días completos de vigencia al momento de la compilación.

---

## 🧰 Herramientas adicionales

### Datos de demostración

Para revisar la interfaz con información sintética:

```bash
flutter run -d chrome \
  --dart-define=RUMBO_DEMO_MODE=true
```

La información de demostración no representa servicios, horarios ni posiciones reales de STM.

### Verificar acceso a la API de Montevideo

Con las credenciales de desarrollador configuradas en `.env`:

```bash
python tool/test_montevideo_api.py
```

Para probar otra línea:

```bash
python tool/test_montevideo_api.py --line NUMERO
```

El script utiliza OAuth Client Credentials y no imprime el token de acceso.

---

## ⚠️ Limitaciones conocidas

Rumbo está en desarrollo y depende de la disponibilidad y calidad de distintas fuentes de datos.

Algunos puntos importantes:

- No todos los ómnibus transmiten posiciones GPS.
- Las estimaciones de llegada no siempre están disponibles.
- Los horarios programados no equivalen a información GPS en vivo.
- La precisión de las direcciones depende de los datos geográficos disponibles.
- Algunos recorridos pueden no tener una correspondencia completa entre GTFS y las variantes de STM.
- Los tramos peatonales alternativos se identifican como aproximados cuando no existe una conexión suficientemente confiable.
- OpenFreeMap ofrece el servicio de mapas sin un SLA garantizado.

El objetivo es comunicar estas limitaciones de manera transparente, sin mostrar información aproximada como si fuera confirmada.

---

## 🌎 Atribuciones y licencias de datos

Rumbo utiliza datos de OpenStreetMap y servicios de terceros.

La seed peatonal derivada de OpenStreetMap se distribuye bajo los términos de ODbL 1.0.

Atribuciones:

- [© OpenStreetMap contributors](https://www.openstreetmap.org/copyright)
- [OpenFreeMap](https://openfreemap.org/)
- [OpenMapTiles](https://openmaptiles.org/)

La procedencia de los datos y sus condiciones de uso deben respetarse al generar y distribuir nuevas versiones.

---

## 🤝 Contribuir

Rumbo es un proyecto abierto y las contribuciones son bienvenidas.

Podés ayudar mediante:

- Reporte de errores.
- Sugerencias de funcionalidades.
- Mejoras de rendimiento.
- Correcciones de datos.
- Mejoras de accesibilidad.
- Contribuciones al código.

Para reportar un problema, abrí un [Issue en GitHub](https://github.com/mewnite/RumboAPP/issues) e incluí, cuando sea posible:

- Versión de Rumbo.
- Modelo de dispositivo.
- Versión de Android.
- Pasos para reproducir el problema.
- Capturas o registros relevantes, sin credenciales ni información privada.

Repositorio:

[github.com/mewnite/RumboAPP](https://github.com/mewnite/RumboAPP)

---

<p align="center">
  <strong>🚌 Rumbo</strong>
  <br>
  <em>Una forma más abierta de moverse por Montevideo.</em>
  <br><br>
  Hecho con Flutter en Uruguay 🇺🇾
</p>
