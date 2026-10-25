# AGENTS.md

## Proyecto
Rumbo (nombre provisional): app móvil de transporte público para Montevideo, Uruguay. Similar en propósito a Moovit, pero sin publicidad, sin trackers y mobile-first. Esta es la V1 (MVP).

## Stack
- Flutter (Dart), iOS y Android desde un solo código base.
- Navegación: go_router. Estado: Riverpod.
- Mapa: MapLibre con teselas de OpenStreetMap. Sin SDKs que requieran claves de pago.
- Datos: GTFS estático del STM / datos abiertos de la Intendencia de Montevideo.
- Almacenamiento local: SQLite (drift) o equivalente; favoritos y cachés van acá.

## Arquitectura
- Estructura por feature: `lib/features/<feature>/{data,domain,presentation}`.
- Código compartido en `lib/core/` (tema, red, utilidades, errores).
- La UI nunca accede a datos directamente: siempre a través de repositorios y casos de uso.
- Toda la lógica de negocio (en especial el planificador de rutas) debe ser Dart puro y testeable sin UI.

## Reglas innegociables
- Prohibido agregar SDKs de publicidad, analíticas de terceros, Firebase Analytics, Crashlytics u otro tracker. Antes de sumar cualquier dependencia nueva, justificarla en el mensaje del commit o en la descripción del PR.
- Prohibido usar identificadores publicitarios.
- La ubicación se procesa en el dispositivo. No se envía a ningún servidor.
- No copiar nombre, logo, paleta ni assets de Moovit ni de otras apps existentes.

## UX y accesibilidad
- Acciones principales en la mitad inferior de la pantalla (uso con una mano).
- Objetivos táctiles de al menos 48 dp, contraste AA, soporte de escala de fuente del sistema, etiquetas semánticas para TalkBack/VoiceOver.
- Toda pantalla debe tener estados de carga, vacío, error y sin conexión.
- Tema claro y oscuro desde el inicio. Español (es-UY) por defecto; todos los textos en archivos de localización, nunca hardcodeados.

## Comandos
- Instalar dependencias: `flutter pub get`
- Análisis estático: `flutter analyze`
- Formato: `dart format .`
- Tests: `flutter test`

## Definición de terminado
Una tarea está terminada solo si:
1. `flutter analyze` no reporta errores ni warnings.
2. `flutter test` pasa.
3. El código está formateado con `dart format`.
4. Se agregaron tests para la lógica nueva.
5. Se actualizó el README o `docs/` si cambió algo relevante.

## Estilo de trabajo
- Cambios pequeños y enfocados; un commit por tarea lógica.
- Si falta información (por ejemplo, la URL del GTFS), no inventes datos: dejá una constante configurable, documentala y avisá en el resumen final.
- Al terminar, resumí qué hiciste, qué quedó pendiente y qué decisiones tomaste.

## Identidad visual
Referencia visual en `docs/identidad/`. Nombre: Rumbo (wordmark en minúsculas: "rumbo").
Eslogan: "Tu ciudad. Tu camino." Mensaje de privacidad: "Sin anuncios. Sin rastreadores."

### Paleta
| Token | Hex | Uso |
|---|---|---|
| `ink` | `#0A122A` | Texto principal, isotipo, fondo del modo oscuro |
| `ivory` | `#FBFBF6` | Fondo en modo claro |
| `rumbo` | `#1B658D` | Color primario de acción (botones, líneas de ruta, chips) |
| `lime` | `#D4E257` | Acento: destino, tramo destacado, indicadores |

Propuesta (a validar):
- Superficie en modo claro: blanco `#FFFFFF` sobre fondo `ivory`.
- Modo oscuro: fondo `#0A122A`, superficie `#121C38`, superficie elevada `#1B2848`, texto principal `#FBFBF6`, texto secundario `#A9B3C7`, acción primaria `#5FA8D3` (versión aclarada de `rumbo` para contraste).
- Texto secundario en modo claro: `#4A5568`.
- Error / aviso de bajada: `#C62828` (claro), `#FF8A80` (oscuro).
- Opcional, pendiente de confirmar: un verde oliva (`~#8DAA5A`) visible en la paleta de referencia, sin hex confiable. No usar hasta definirlo.

### Reglas de color
- `lime` NO se usa como texto ni como ícono sobre `ivory` o blanco (contraste insuficiente). Se usa para indicadores, rellenos y detalles. El texto sobre `lime` es siempre `ink`.
- El texto sobre `rumbo` es blanco. El texto sobre `ink` es `ivory`.
- Todos los pares texto/fondo deben cumplir AA (4.5:1 texto normal, 3:1 texto grande e íconos).
- Todos los colores viven en un único archivo de tokens (`lib/core/theme/`). Prohibido usar hex sueltos en los widgets.

### Tipografía
- UI: Inter (licencia OFL) como asset local. No usar `google_fonts` en runtime (descargaría la fuente desde servidores externos).
- El wordmark "rumbo" NO es una fuente: es un asset vectorial. No intentar recrearlo con texto.
- Títulos: Semibold. Cuerpo: Regular. Etiquetas: Medium. Números (horarios, minutos): cifras tabulares.

### Marca
- Isotipo: letra R gruesa con doble contorno (calle en planta) y curva con punta de flecha en la panza.
- Tres variantes: completa (con línea interior), simplificada (sin línea interior fina, para tamaños menores a 32 px) y monocromática.
- Siempre en SVG. Si el SVG definitivo no está disponible, usar el placeholder `RumboLogo` y avisarlo en el resumen final.
- No copiar elementos visuales de Moovit ni de otras apps.

### Iconografía
- Líneas redondeadas, trazo uniforme. Favoritos: corazón. Lugares guardados: marcador.
- Íconos necesarios: ubicación actual, parada, línea, caminata, transbordo, favoritos, búsqueda, guardar, tiempo real, sin conexión, dirección, aviso de bajada.

### Mapa
- Estilo claro y de baja saturación para que las rutas destaquen. Ruta en `rumbo`, destino en `lime`. Paradas con marcador cuadrado redondeado.
- La ubicación precisa se procesa en el dispositivo: Rumbo no la persiste ni la envía a un servidor. Las solicitudes de teselas pueden revelar al proveedor el área aproximada visible; explicarlo junto a la atribución.
- Las URLs de estilo/teselas, atribución y centro/zoom predeterminados se configuran únicamente en `lib/core/config/map_config.dart`.
- No descargar áreas de teselas de forma masiva. Se permite solicitar ubicación en segundo plano únicamente para un viaje activo iniciado explícitamente por la persona; procesarla en el dispositivo, mostrar el estado/servicio del sistema, detenerla al finalizar o cancelar el viaje y nunca enviarla a un servidor.

### Textos
- Todo el copy en español (es-UY) y en archivos .arb. Las imágenes de referencia tienen textos rotos: son solo guía de layout.
### Datos de transporte
- No inventar URLs, endpoints, paradas ni datos presentados como oficiales; la fuente estática y cualquier endpoint futuro se configuran únicamente en `lib/core/config/transit_config.dart`.
- El dominio de transporte no depende de GTFS; el parser GTFS es solo un adaptador de importación.
- Los datos incluidos para probar siempre se identifican como sintéticos y no oficiales.
- No implementar cliente de red del tiempo real hasta confirmar endpoint oficial y condiciones de uso.
