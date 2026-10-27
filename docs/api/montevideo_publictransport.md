# API pública de transporte de Montevideo

Este documento describe la integración que Rumbo usa y documenta en el repositorio para desarrollo local. No es un contrato oficial publicado por la Intendencia ni una garantía de disponibilidad del servicio; es la capa de integración que el proyecto ha adoptado para pruebas y validación.

## 1. Alcance

La [documentación oficial de Transporte Público](https://api.montevideo.gub.uy/apidocs/publictransport) indica que la API ofrece posiciones de buses y cálculo de tiempo estimado de arribo (ETA). El acceso requiere una cuenta gratuita y la Intendencia asigna un número razonable de consultas por segundo; no publica aquí un valor numérico fijo. Este repo no guarda credenciales ni asume autorización de producción.

La app separa claramente tres tipos de datos:

- GTFS estático: paradas, rutas, variantes, horarios, calendarios y shapes.
- Tiempo real: posiciones de la flota STM.
- Geocodificación: búsqueda de direcciones y lugares.

La implementación en código mantiene todos los datos fuera del APK salvo que se configure un proxy local de desarrollo. La app no guarda ni envía la ubicación precisa del usuario a un backend propio sin una acción explícita del usuario.

## 2. Autenticación

El acceso a la API oficial de la Intendencia se realiza con OAuth Client Credentials. El repositorio recomienda guardar `CLIENT_ID` y `CLIENT_SECRET` en un archivo `.env` local, excluido de Git, y no incorporarlos a la app ni al APK.

Flujo recomendado:

- El proxy local de desarrollo lee `CLIENT_ID` y `CLIENT_SECRET` desde configuración local.
- El proxy obtiene un access token fuera del cliente móvil.
- La app solo consume el proxy local y no conoce secretos.
- El proxy puede iniciarse sin esas variables para servir únicamente búsqueda de lugares; las rutas GTFS y STM responden que falta autenticación hasta configurarlas.

No se imprime ni se persiste el token. El mismo patrón aplica al feed GTFS y al tiempo real.

## 3. Proxy local de desarrollo

El proxy de desarrollo escucha en `127.0.0.1:8765` y se usa desde Flutter con el valor de `RUMBO_API_BASE_URL` o con el host local según plataforma:

- Android emulador: `http://10.0.2.2:8765`
- Android/iOS físico con USB: `http://127.0.0.1:8765` y `adb reverse tcp:8765 tcp:8765`
- Otros entornos: `http://127.0.0.1:8765`

En debug, el proyecto usa ese proxy si no existe una URL explícita. En release, la app no configura la API ni incluye credenciales.

## 4. Endpoints documentados por el proyecto

### 4.1 GTFS estático

Ruta del proxy:

- `GET /gtfs/latest`

Uso:

- Descarga el feed GTFS actual.
- Se cachea localmente por un período configurable.
- Si no hay proxy o no se configura la URL, la app muestra el estado sin datos oficiales; el feed sintético solo se carga en modo demo explícito (`RUMBO_DEMO_MODE=true`).

Notas:

- El feed oficial se habilita solo para desarrollo.
- El feed de prueba es sintético y no representa servicios ni horarios reales del STM.
- El cache de GTFS se evita en release salvo que se configure explícitamente.

### 4.2 Tiempo real: posiciones de buses

Ruta del proxy:

- `GET /api/buses?format=geojson`

Uso:

- Retorna un GeoJSON de `FeatureCollection` con la flota.
- La app valida las coordenadas, descarta fuera de Uruguay y deduplica por `properties.id`.
- El parser mantiene `frecuencia` y `version` como campos raw para no interpretarlos.

Notas:

- No se usa `/buses/geo`, marcado como obsoleto en el manual de referencia.
- El proxy aplica límites globales de frecuencia para evitar consultas masivas.
- Los datos de flota se filtran localmente en el dispositivo por zona visible y líneas relevantes.

La documentación oficial describe en cada bus `id`, `timestamp` UTC, ubicación, línea, variante, origen y destino, entre otros atributos. El parser Flutter debe conservar la hora reportada y no confundirla con una ETA.

### 4.3 Arribos estimados por parada

La API oficial documenta `GET /buses/busstops/{busstopId}/upcomingbuses`; requiere informar las líneas a consultar (`lines` o `lineVariantIds`) y admite `amountperline` y `format`. La descripción oficial dice que retorna buses próximos a una parada y que la API calcula ETA. Sin embargo, el modelo de respuesta publicado para este recurso solo ejemplifica metadatos de línea/variante y no deja identificados los campos de segundos/minutos, hora estimada ni timestamp de cálculo. Por eso la app no interpreta todavía esa respuesta ni reemplaza el ETA local hasta obtener una respuesta oficial autorizada que cierre el contrato.

### 4.4 Geocodificación / búsqueda de direcciones

Ruta del proxy:

- `GET /geocode` (o gateway configurable con la misma intención)

Uso:

- Búsqueda de direcciones completas, intersecciones, barrios, POIs y otras ubicaciones.
- El proyecto la usa como capa remota opcional para el buscador de destinos.

Notas:

- Si el usuario no habilita la búsqueda remota en ajustes, la app usa solo datos locales.
- La ubicación precisa del usuario solo se usa en el dispositivo para desempatar resultados y no se envía al backend.
- La geocodificación solo se habilita si está documentada y configurada en la app.

### 4.5 Planificación de rutas

La app implementa un motor local de planificación basado en GTFS; la documentación consultada no publica un endpoint oficial de planificación A→B.

No se documenta un endpoint de planificación real en este repositorio. La capa de planificación se resuelve localmente dentro del dispositivo para:

- caminar desde origen / hacia destino,
- rutas con hasta dos transbordos,
- horarios programados,
- prioridad por llegada y por menor cantidad de transferencias.

Si se habilita un servicio oficial de planificación en el futuro, debe tener un switch explícito en ajustes y una advertencia clara de que origen y destino se envían a servidores externos.

## 5. Límite y comportamiento de red

El proyecto exige un comportamiento responsable con la fuente:

- intervalos mínimos configurables,
- backoff ante errores,
- cancelación al salir de pantalla o pasar a segundo plano,
- no consultas recurrentes sin límite,
- desacopleo de credenciales del cliente móvil.

Para la flota en vivo, el flujo del repositorio propone un máximo global de una consulta cada 10 segundos, como política de desarrollo, no como límite oficial de la Intendencia.

## 6. Privacidad y límites de datos

Rumbo procesa la ubicación en el dispositivo. La app no persiste ni envía la ubicación precisa a un backend propio. Lo que sí puede revelarse al proveedor de teselas o al servicio remoto es la zona aproximada visible, y la UI lo informa junto a la atribución del mapa.

La app no usa SDKs de anuncios, analítica de terceros ni trackers. No se instala publicidad ni identificadores publicitarios.

## 7. Qué no está garantizado

Este documento no cubre ni garantiza:

- la continuidad de la API pública de la Intendencia,
- el acceso continuo a una URL oficial,
- la disponibilidad de un endpoint geocodificante o de planificación,
- la estabilidad del contrato si la fuente cambia sin aviso.

En el repo, los valores de configuración se mantienen en `lib/core/config/transit_config.dart` y se conciben para que puedan cambiarse sin tocar lógica de negocio.

## 8. Resumen operativo

La integración que Rumbo documenta y soporta en desarrollo es:

- OAuth Client Credentials fuera del cliente móvil.
- Proxy local con `127.0.0.1:8765`.
- GTFS estático vía `/gtfs/latest`.
- Posiciones en vivo vía `/api/buses?format=geojson`.
- Geocodificación opcional vía `/geocode`.
- Motor de planificación local, sin depender de un servicio UPSTREAM para la lógica principal.

Esto permite una experiencia móvil funcional sin conexión, con datos sintéticos o cacheados, y una capa de producción controlada solo cuando exista un backend intermediario documentado y con límites claros.
