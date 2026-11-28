# Búsqueda remota de direcciones

## Arquitectura híbrida implementada

La búsqueda clasifica primero el texto en dirección con puerta,
intersección, POI, barrio, calle, área geográfica o consulta desconocida.
El backend conserva nombres oficiales y alias verificables en un catálogo
local de Montevideo, normaliza abreviaturas y expande alias antes de consultar
Photon. El catálogo no contiene coordenadas propias: toda coordenada mostrada
debe provenir de la respuesta geográfica confirmada por el proveedor.

Fuentes incorporadas actualmente:

- **OpenStreetMap**: datos geográficos y objetos indexados por Photon.
- **Photon**: proveedor externo principal configurable mediante
  `RUMBO_GEOCODING_URL`.
- **Proxy de Render**: caché y normalización del contrato Rumbo.

Fuentes investigadas y su estado:

| Fuente | URL oficial | Estado actual | Licencia / límites |
|---|---|---|---|
| Photon | https://photon.komoot.io/ | Provider configurable; predeterminado del proxy | Usa datos OSM; API pública sujeta a uso justo y limitación de carga |
| OpenStreetMap | https://www.openstreetmap.org/copyright | Procedencia de los objetos devueltos por Photon | ODbL para los datos y atribución obligatoria |
| Catálogo Nacional de Datos Abiertos | https://catalogodatos.gub.uy/ | Catálogo investigado; sin endpoint geográfico confirmado e incorporado | Depende de la licencia de cada conjunto |
| Datos de Montevideo / IDE | Requieren una URL oficial verificable por dataset | No incorporados como proveedor automático | No se asumió disponibilidad ni licencia |

Los alias locales se mantienen en el catálogo del backend y el normalizador del
cliente. Incluyen nombres oficiales, alias y categorías, pero no contienen
coordenadas inventadas. La coordinación actual cubre SODRE/Auditorio Nacional
Adela Reta, Nuevo Centro Shopping, Catedral Metropolitana, Teatro Solís,
Estadio Centenario y Shopping Punta Carretas. Si un proveedor no devuelve el
objeto verificado, el alias no crea un resultado ficticio.

No se incorporó una base municipal de numeración ni geometrías oficiales de
calles porque no se verificó un endpoint distribuible y estable en esta
implementación. Tampoco se añadieron endpoints de datos oficiales sin URL,
licencia o formato comprobados.

Los alias conocidos resuelven variantes como SODRE, Nuevo Centro, Catedral
Metropolitana y Teatro Solís, pero el resultado se crea únicamente si Photon
devuelve un objeto que coincida con la entidad. Las consultas de intersección
siguen exigiendo un cruce, junction o representación que contenga ambas calles.

## Seguimiento de ómnibus en el mapa

El mapa selecciona marcadores reales de la API STM y mantiene visible una
tarjeta compacta con línea, destino, empresa, variante, vehículo y transmisión
GPS. Los datos se actualizan desde el mismo snapshot compartido del controlador
de ómnibus; no se genera una solicitud independiente al seleccionar o seguir
un vehículo.

El seguimiento activa una reorientación suave de la cámara hacia la posición
reciente. Una posición con más de 60 segundos se identifica como antigua y no
permite activar el seguimiento. El movimiento manual suspende el seguimiento
automático hasta que el usuario lo reactive. Las estimaciones de llegada no se
calculan ni se presentan si el STM no entrega una ETA verificable.

## Consentimiento y flujo

`remote_place_search_enabled` se guarda en `SharedPreferences`. Una instalación
sin preferencia se inicializa en `false`; por eso una instalación limpia no
llama automáticamente a `/geocode`. La pantalla de búsqueda ofrece
“Activar búsqueda en línea” y explica que hay que habilitarla para buscar
direcciones y lugares. El primer intento abre el aviso de consentimiento; al
aceptarlo se persiste `true`. Se puede revocar desde Ajustes → Privacidad.

La ausencia previa de `geocode_ms` no demostraba que el servidor hubiera
respondido vacío: la llamada remota se omitía con el consentimiento apagado.
Además, el cliente emitía su medición con `developer.log`, no con
`debugPrint`. Ahora registra `[performance] geocode_ms=... status=...` para
respuestas HTTP, timeout, cancelación y errores de red, sin incluir el texto
de búsqueda.

## Diagnóstico del endpoint configurado

Dos solicitudes de diagnóstico anteriores (una por consulta) reportaron HTTP
502 y no expusieron el cuerpo. No se repitieron. En una solicitud posterior,
única para `faramiñán 801`, el endpoint respondió HTTP 200 con este cuerpo:

```json
[{"place_id":18229245,"osm_type":"way","osm_id":78114932,"lat":"-34.8412159","lon":"-56.2374153","category":"highway","type":"residential","name":"Faramiñán","display_name":"Faramiñán, Nuevo París, Montevideo, 11900, Uruguay","address":{"road":"Faramiñán","suburb":"Nuevo París","city":"Montevideo","state":"Montevideo","postcode":"11900","country":"Uruguay","country_code":"uy"}}]
```

La respuesta encuentra la calle, pero no contiene `house_number`: no confirma
el número 801. La UI conserva el texto consultado y muestra «Número no
confirmado · ubicación aproximada»; el destino también se marca como
aproximado para el planificador.

La única llamada posterior para `shopping nuevocentro` respondió HTTP 200
(Render request ID `0861718f-ddd0-40f4`) y devolvió dos lugares:

| Nombre | Categoría | Tipo | Ubicación |
|---|---|---|---|
| Nuevocentro Shopping | `shop` | `mall` | Jacinto Vera, Montevideo |
| Géant | `shop` | `supermarket` | Jacinto Vera, Montevideo |

El primer resultado es el centro comercial buscado. No se tuvo acceso a los
logs privados del servicio de Render, por lo que no se pudo inspeccionar su log
upstream ni verificar qué IP o `User-Agent` recibió Nominatim. La respuesta
200 de cada consulta indica que esas solicitudes no fueron rechazadas, pero no
permite concluir que no haya rechazos intermitentes.
El proxy Python configura un `User-Agent` identificable
(`RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)`) y caché en memoria de
24 horas. Para esta verificación se hizo exactamente una llamada nueva para
`shopping nuevocentro`; no se repitió ninguna consulta anterior.

El endpoint público de la app sigue recibiendo únicamente `q`. El código del
proxy consulta Photon (`https://photon.komoot.io/api/`) por defecto y convierte
su GeoJSON al contrato enriquecido que consume Flutter. Esto describe la
configuración del proxy en el repositorio, no confirma qué proveedor está
desplegado en Render. Para priorizar
Montevideo envía una ubicación fija de sesgo en
`lat=-34.9037&lon=-56.1882`; nunca envía la ubicación GPS de la persona.
Limita las búsquedas a Uruguay con `bbox=-58.5,-35.2,-53.0,-30.0`.

El proxy normaliza acentos, marcas de número como `n°`, abreviaturas locales
(por ejemplo, `Av.` y `Gral.`) y el alias `nuevocentro`. Las direcciones con
puerta conservan el número confirmado por Photon; las demás se marcan como
`unconfirmedDoorNumber`. Las intersecciones solo se devuelven si el resultado
contiene las dos calles o identifica explícitamente un cruce.

En Render se puede configurar `RUMBO_GEOCODING_URL` con un servicio compatible.
El predeterminado es Photon y no requiere API key. Se conserva compatibilidad
con una URL de Nominatim configurada explícitamente. Las respuestas se
cachean 24 horas y la caché obsoleta se reutiliza si el proveedor falla.

Los fixtures de Photon bajo `tool/test_fixtures/` son sintéticos y solo sirven
para pruebas automatizadas; sus IDs y coordenadas no son datos oficiales.
Render debe volver a verificarse tras desplegar antes de afirmar que Photon
está activo allí.

## Errores, espera y caché

Las búsquedas remotas se disparan tras debounce, las solicitudes anteriores
se abortan al cambiar el texto y las respuestas obsoletas no reemplazan la
búsqueda actual. Se cachean hasta 20 consultas en memoria y los destinos
seleccionados se guardan en búsquedas recientes locales. HTTP 429 y timeout
se propagan a la interfaz como error explícito; ya no se degradan
silenciosamente a una lista vacía.

## Validación final en Android

Se instaló el APK debug en `emulator-5554`, se habilitó la búsqueda en línea
mediante el consentimiento de la app y se ejecutaron las once consultas
solicitadas. Las respuestas HTTP de esta ronda fueron 200. La tabla refleja
las tarjetas visibles en Flutter, no solo el resultado HTTP.

| Consulta | Resultado observado en el emulador |
|---|---|
| `18 de Julio 1234` | Una tarjeta con ese texto; «Número no confirmado · ubicación aproximada», en Centro. No se confirmó la puerta. |
| `Avenida Italia 2450` | Cuatro tarjetas aproximadas con el mismo título, en Malvín Nuevo, La Blanqueada, Malvín y Carrasco Norte. Ninguna confirma el número. |
| `Bulevar Artigas 1500` | Cuatro tarjetas aproximadas, en Parque Rodó, Bella Vista, Atahualpa y Jacinto Vera. Ninguna confirma el número. |
| `18 de Julio y Ejido` | Sin resultado remoto visible; no se mostró una esquina confirmada. |
| `Rivera esquina Soca` | Sin resultado remoto visible; no se mostró una esquina confirmada. |
| `Bulevar Artigas & Garibaldi` | Sin resultado remoto visible; no se mostró una esquina confirmada. |
| `Palacio Legislativo` | Una tarjeta titulada «Palacio Legislativo», categoría Punto de interés, con Avenida de las Leyes y Aguada. |
| `SODRE` | Sin resultado visible. |
| `Estadio Centenario` | Una tarjeta titulada «Estadio Centenario», categoría Punto de interés, con Avenida Doctor Américo Ricaldoni y Parque Batlle. |
| `Terminal Tres Cruces` | En la versión final: una tarjeta Punto de interés para la terminal y otra «Parada de ómnibus». Se descartó el cajero que el proveedor también nombraba «Terminal Tres Cruces». |
| `Parque Rodo` | Una tarjeta del parque y una del barrio. Se eliminó una representación duplicada del mismo barrio; el parque y el barrio se conservaron como objetos distintos. |

Se seleccionó «Parque Rodó» y quedó como destino en el campo «Hasta» del
planificador. La búsqueda local de paradas seguía disponible. En las
intersecciones sin resultado no se fabricaron coordenadas.

Los cuatro candidatos aproximados para Avenida Italia y Bulevar Artigas
siguen siendo una limitación: el proveedor devuelve ubicaciones distintas
para una puerta que no confirma. Se identifican como aproximadas, pero la
persona debe elegir entre barrios alejados; no se deben presentar como cuatro
direcciones exactas ni colapsarlas únicamente por cercanía.

La respuesta pública de Render continúa usando campos del formato Nominatim
(`place_id`, `osm_type`, `osm_id`, `display_name` y `address`). Esto no prueba
qué upstream atendió la solicitud; Photon **no se pudo confirmar como
desplegado**. La prueba Android valida la experiencia contra el endpoint
público actual, no el contrato Photon del proxy local.

## Segunda ronda Photon en Android (2026-11-25)

Se volvió a probar el endpoint público desde la app instalada en
`emulator-5554`, con consentimiento de búsqueda online habilitado. Se probaron
26 consultas en la interfaz (incluyendo la consulta inicial a Palacio
Legislativo); las consultas finales tuvieron respuesta HTTP 200. El endpoint
ahora devuelve el contrato normalizado de Rumbo (`id`, `kind`, `title`,
`precision`, `category` y `source`), a diferencia de la respuesta Nominatim
observada en la ronda anterior. No se inspeccionaron los ajustes ni logs
privados de Render.

| Consulta | Resultado visible en Android |
|---|---|
| `Palacio Legislativo` | Correcto: POI con nombre y Avenida de las Leyes, Aguada. |
| `Estadio Centenario` | Correcto: POI con nombre y Avenida Doctor Américo Ricaldoni, Parque Batlle. |
| `Terminal Tres Cruces` | Terminal como POI y parada STM por separado. |
| `Parque Rodo` | Antes del ajuste: dos tarjetas POI con el mismo título, además del barrio. |
| `SODRE` | Sin resultados. El endpoint respondió HTTP 200 vacío. |
| `Mercado Agricola de Montevideo` | POI con nombre Mercado Agrícola de Montevideo y José L. Terra 2220. |
| `Teatro Solis` | Antes del ajuste: el teatro y una estación de alquiler de bicis aparecían con el mismo nombre. |
| `Hospital de Clinicas` | POI Hospital de Clínicas “Doctor Manuel Quintela”, en La Blanqueada. |
| `Shopping Punta Carretas` | Antes del ajuste: dos tarjetas con el mismo nombre, una de parking y otra del shopping. |
| `Aeropuerto Carrasco` | POI Aeropuerto Internacional de Carrasco; el contexto señala Colonia Nicolich. |
| `18 de Julio 1234` | Avenida 18 de Julio 1234, marcada como dirección exacta. |
| `Avenida Italia 2450` | Sin resultados. HTTP 200 vacío; `Italia 2450` devuelve solo un elemento sin número confirmado, no una dirección exacta utilizable. |
| `Bulevar Artigas 1500` | Cuatro candidatos visibles, todos con «Número no confirmado · ubicación aproximada» y barrios distintos. |
| `Colonia 1234` | Dirección exacta en Centro. |
| `Rivera 3245` | Antes del ajuste: tres tarjetas duplicadas de Avenida General Rivera 3245, todas marcadas exactas. |
| `18 de Julio y Ejido` | No confirmó la esquina; la interfaz lo indicó explícitamente. |
| `Rivera esquina Soca` | No confirmó la esquina; la interfaz lo indicó explícitamente. |
| `Bulevar Artigas y Garibaldi` | No confirmó la esquina; la interfaz lo indicó explícitamente. |
| `Ejido y Colonia` | No confirmó la esquina; la interfaz lo indicó explícitamente. |
| `Parque Batlle` | Parque y barrio aparecen como entidades distintas. |
| `Rambla de Montevideo` | La API devolvió dos segmentos de rambla no relacionados (Punta Gorda y Pajas Blancas); Flutter no mostró resultados. |
| `Ciudad Vieja` | Barrio correcto, pero también apareció un café cuyo nombre incluye Ciudad Vieja y una línea STM local. |
| `Nuevo Centro Shopping` | Sin resultado útil. La API devolvió Naranjita Nuevo Centro (guardería), que Flutter descartó. |
| `Plaza Independencia` | Plaza correcta primero; además aparecieron candidatos débiles, incluida otra plaza en Tres Cruces y una parada. |
| `Catedral Metropolitana de Montevideo` | Sin resultados; HTTP 200 vacío. |
| `Palacio Salvo` | POI correcto, en Plaza Independencia / Ciudad Vieja. |

### Ajustes realizados y reprobados

En la app local se corrigió la interpretación de `boundary:neighborhood`
como barrio y su precisión como área aproximada. También se excluyen alquileres
de bicicletas, parkings y cajeros cuando la consulta no pide ese servicio.
Para direcciones con número confirmado, se deduplican registros con el mismo
título normalizado y localidad, sin fusionar puertas distintas.

Después de compilar e instalar el APK actualizado, se repitieron cuatro casos:

- `Parque Rodo`: ya no hay dos POI iguales; parque y barrio permanecen
  diferenciados. También puede aparecer Lago o Canteras del Parque Rodó.
- `Teatro Solis`: queda una tarjeta del teatro; la estación de bicicletas
  homónima desapareció.
- `Shopping Punta Carretas`: queda una tarjeta del shopping; el parking
  homónimo desapareció.
- `Rivera 3245`: queda una sola tarjeta de dirección exacta.

El proxy local ahora expande `SODRE` al nombre conocido del Auditorio Nacional
Adela Reta y agrega el alias al resultado solo si el nombre del POI coincide.
La consulta pública por `Auditorio Nacional Adela Reta` sí devolvió ese POI,
lo que confirma que el objeto está indexado aunque el alias de búsqueda no lo
esté.
La respuesta pública de Render para `SODRE` sigue vacía: **este ajuste aún no
está desplegado ni se validó en producción**.

### Pendientes de datos / proveedor

No se deben “arreglar” los cuatro cruces con coordenadas inferidas: Photon no
devolvió una geometría que confirmara ambas calles. Para `Avenida Italia
2450`, los resultados disponibles no confirman la puerta; para `Bulevar
Artigas 1500` solo hay aproximaciones en barrios diferentes. `Rambla de
Montevideo` produce coincidencias parciales en otras zonas. `Nuevo Centro
Shopping`, `Catedral Metropolitana` y `SODRE` no tienen resultado útil en la
respuesta pública actual. Son pendientes para revisar la configuración,
índice y cobertura del proveedor; el alias SODRE requiere desplegar el cambio
del proxy.

El APK de esta ronda se compiló e instaló en el emulador. Las correcciones del
cliente se verificaron contra el endpoint público. No se desplegó ningún
cambio a Render; por lo tanto, los arreglos del proxy local no deben
considerarse activos allí.
