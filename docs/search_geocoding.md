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

## Pruebas contra el endpoint configurado

Se hicieron exactamente dos solicitudes, una por consulta, a
`https://rumboapp.onrender.com/geocode`:

| Texto enviado | Resultado observado |
|---|---|
| `faramiñán 801` | HTTP 502 desde la herramienta de consulta; no entregó cuerpo |
| `shopping nuevocentro` | HTTP 502 desde la herramienta de consulta; no entregó cuerpo |

No se reintentaron. Por ese 502 no se pudo observar una lista de resultados ni
afirmar si Nominatim devuelve esos lugares. El endpoint de la app envía
únicamente `q`; el proxy añade contexto “Montevideo, Uruguay” y configura
`countrycodes=uy`, `format=jsonv2`, `addressdetails=1` y `limit=5`.

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
