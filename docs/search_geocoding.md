# Búsqueda remota de direcciones

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
