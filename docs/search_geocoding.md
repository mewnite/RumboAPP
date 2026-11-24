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

El endpoint de la app envía únicamente `q`; el proxy añade contexto
“Montevideo, Uruguay” y configura `countrycodes=uy`, `format=jsonv2`,
`addressdetails=1` y `limit=5`.

El proxy ahora agrega `viewbox=-56.4048,-34.7167,-55.9955,-34.9271` y
`bounded=1` para priorizar y acotar al área de Montevideo cubierta por la seed
de transporte. Normaliza acentos, marcas de número como `n°`, abreviaturas
locales (por ejemplo, `Av.` y `Gral.`) y el alias `nuevocentro`. Los cambios
están en el proxy Python y en el Worker de Cloudflare; se verificaron con
pruebas locales simuladas, no con nuevas llamadas a Render.

## Errores, espera y caché

Las búsquedas remotas se disparan tras debounce, las solicitudes anteriores
se abortan al cambiar el texto y las respuestas obsoletas no reemplazan la
búsqueda actual. Se cachean hasta 20 consultas en memoria y los destinos
seleccionados se guardan en búsquedas recientes locales. HTTP 429 y timeout
se propagan a la interfaz como error explícito; ya no se degradan
silenciosamente a una lista vacía.
