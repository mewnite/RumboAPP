# Rendimiento de la búsqueda de rutas

## Diagnóstico

Una búsqueda medida en el SM-A346M pasó 142712 ms en
`TransitRouteSearch.findPlans` (etapa posterior a SQLite y armada del payload).
Los contadores nuevos separan el trabajo interno:

- pares origen-destino evaluados;
- patrones e instancias de viaje recorridos;
- filas de `stop_times` examinadas;
- candidatos generados y planes devueltos;
- transbordos evaluados.

La complejidad dominante era la combinación de hasta 15 paradas origen,
15 destino, instancias de viaje ordenadas por salida y hasta varios puntos de
transbordo cercanos. El bucle principal enumeraba alight-stop, primera
conexión, destinos cercanos y segunda conexión: crecimiento aproximadamente
cuadrático en endpoints y lineal en viajes antes del desempate. Además,
recalculaba rutas peatonales repetidas para pares de coordenadas iguales.

## Cambios y medición de escritorio

La búsqueda fue rediseñada por rondas RAPTOR. Indexa patrones y viajes una vez
por consulta, restringe viajes a la ventana horaria, poda etiquetas dominadas
y estima caminatas de transbordo en línea recta durante la búsqueda. El grafo
peatonal se consulta para los pocos planes finales. Android ejecuta el cálculo
en el worker residente de `walk_graph_worker_io.dart`; sin ese worker usa
`plan_search_isolate_io.dart`.

Medición ESCRITORIO del `findPlans` síncrono con la seed local. Los tiempos
incluyen una sola ejecución por variante y son orientativos; `9db99a9` es el
baseline instrumentado y “RAPTOR, 2 transbordos” es el código actual:

| Par | Baseline (ms) | RAPTOR (ms) |
|---|---:|---:|
| Pocitos–Portones | 9.372 | 697 |
| Cordón–Buceo | 6.736 | 122 |
| Centro–Punta Carretas | 7.304 | 549 |
| Tres Cruces–Buceo | 5.800 | 820 |
| Centro–Cordón | 9.218 | 393 |
| Aguada–Barrio Sur | 8.362 | 293 |
| Parque Rodó | 4.276 | 543 |
| Unión–Manga | 978 | 303 |
| Cerro–Centro | 6.524 | 361 |
| Malvín–Nueva Palma (sin servicio) | 0 | 0 |

Tiempos de una ejecución reciente del fixture; todas las búsquedas con servicio
quedaron debajo de 1 s en escritorio. El
baseline hacía hasta 189.309 cálculos de caminata por consulta; con RAPTOR se
registraron 2–10 caminatas finales calculadas y 285–6.850 estimaciones de
caminata por línea recta. El fixture de `findPlans` no carga el grafo peatonal
(`walk_graph_searches=0`); el test end-to-end con el worker sí lo carga y, para
Pocitos–Portones, hizo 7 búsquedas del grafo y 10 cálculos finales.

El límite de transbordos forma parte de la dominancia: un plan con dos
transbordos no elimina automáticamente una alternativa más directa solo por
tener menos caminata. El test real con `WalkGraph` compara el top 3 de
Pocitos–Portones y mantiene tres opciones. El primer plan del fixture legacy se
refina a 837 m, excediendo el máximo de 800 m; su siguiente alternativa válida
llega a las 08:24:51 con 795 m. La nueva primera opción llega a las 08:23:51
con 579 m y dos transbordos; las otras dos opciones llegan a las 08:24:51 y
08:27:16. Al comparar `maximumTransfers=2` con `1`, el mejor horario no empeora
en ninguno de los nueve pares con servicio y mejora Cerro–Centro de 08:53:03 a
08:49:03. Cinco pares devuelven menos de tres opciones; cuatro de ellos tienen
tres planes en el baseline:

| Par | Alternativas del baseline ausentes con 2 transbordos | ¿Había directo? |
|---|---|---|
| Tres Cruces–Buceo | 08:39:19, `47802219 → 4000952`; las dos primeras opciones conservan llegada y caminata, pero cambia el primer bus | No; las tres son de 1 transbordo |
| Centro–Cordón | 08:38:02, `9800331 → 701062` | Sí; ambos directos del baseline siguen presentes |
| Parque Rodó | 08:56:57 `44301060 → 5900960` y 08:58:57 `12801052 → 2201134` | Sí; el directo 08:50:46 sigue presente. Aparece además una alternativa de 2 transbordos que llega a la misma hora |
| Cerro–Centro | 09:16:13 `48002294 → 2702399` y 09:23:13 `48002294 → 3201106` | No; las alternativas del baseline tienen 1 transbordo. La búsqueda de 2 transbordos agrega una opción que llega 4 min antes |

Unión–Manga también devuelve solo dos alternativas, pero su baseline contiene
una sola; no se pierde ninguna de sus alternativas congeladas. La suite
contrasta el mejor horario, no garantiza igualdad del top 3.

## Comparación completa ESCRITORIO / TELÉFONO

Cinco ejecuciones del mismo planificador, mismo recorrido Pocitos–Portones,
fecha fija y dos transbordos; incluyen SQLite, carga de horarios, búsqueda y
grafo peatonal:

| Métrica | ESCRITORIO (Windows) | MEDIDO EN TELÉFONO (SM-A346M, PROFILE) |
|---|---:|---:|
| `trip.plan`, mediana (rango) | 1.034 ms (968–1.187) | 2.674 ms (2.629–3.499) |
| `trip.stage_schedule_stops`, mediana (rango) | 812 ms (721–831) | 2.299 ms (2.223–2.944) |
| `trip.stage_transit_search`, mediana (rango) | 171 ms (158–279) | 283 ms (246–428) |

El cociente completo teléfono/escritorio es 2,59× por medianas. El isolate
transit-only es 1,65×; la etapa dominante sigue siendo cargar horarios SQLite,
no RAPTOR. Las cinco búsquedas PROFILE cumplieron el objetivo de menos de 5 s.
`trip.stage_search`/`trip.stage_transit_search` corren en el worker isolate
peatonal, no en el hilo de UI.

## Corridas adicionales PROFILE en el teléfono

Se repitieron cinco búsquedas por par con el mismo día y hora (24/11/2026,
08:00), incluyendo SQLite, carga de horarios, planificación y refinamiento del
grafo. El log de la app verificó `source="GTFS oficial STM (API de Montevideo)"`,
`synthetic=false`, 4.920 paradas, 37.445 viajes y 2.221.182 stop-times. La
licencia de distribución sigue sin estar confirmada; este dato valida la
procedencia declarada por la seed, no la autorización legal de publicación.

| Par (puntos fijos) | `trip.plan` mediana (rango) | `schedule_stops` mediana (rango) | `transit_search` mediana (rango) | planes |
|---|---:|---:|---:|---:|
| Pocitos–Portones | 2.674 ms (2.629–3.499) | 2.299 ms (2.223–2.944) | 283 ms (246–428) | 3 |
| Cerro–Centro | 2.496 ms (2.349–2.880) | 2.048 ms (1.993–2.372) | 278 ms (247–517) | 1 |
| Tres Cruces–Buceo | 1.939 ms (1.821–2.123) | 1.546 ms (1.487–1.738) | 313 ms (282–335) | 1 |
| Parque Rodó–Carrasco | 1.596 ms (1.505–1.849) | 1.223 ms (1.163–1.454) | 326 ms (223–327) | 2 |

El punto de Buceo usado fue la parada de la seed `Av. Gral. Rivera - Nicolás
Piaggio` (-34.899849, -56.129917); los demás puntos corresponden a los centros
fijos del fixture o paradas cercanas identificadas en esa misma seed.

### Propuesta para reducir `schedule_stops` (sin implementar)

La consulta actual ya tiene índices `pattern_stops(stop_id)`,
`trips(pattern_id, service_id, start_secs)`, `stops(lat,lon)` y excepciones por
servicio/fecha/tipo. Por eso no conviene agregar índices a ciegas:

1. Medir `EXPLAIN QUERY PLAN` y filas por subconsulta en el dispositivo.
   Probar un índice cubriente `(stop_id, pattern_id)` para evitar búsquedas de
   fila en `pattern_stops`; conservarlo solo si reduce el tiempo real.
2. Evaluar calendarios activos para la fecha una vez, en vez de repetir las
   cláusulas de calendario por parada y día. Comparar un índice
   `(service_id, start_secs, pattern_id)` con el existente según el plan SQL.
3. Evitar materializar una copia de todas las paradas por cada viaje: cargar
   una secuencia por patrón y los viajes/salidas del intervalo, y aplicar los
   offsets del patrón al vuelo. Validar medianoche y calendarios antes de
   aceptar este cambio semántico/estructural.
4. Cachear horarios ya normalizados en el worker persistente por fecha,
   ventana y versión de feed; invalidar al reemplazar la base. Esto ayuda a
   búsquedas repetidas, pero no al primer recorrido.

Priorizaría (3) y (1) después de un `EXPLAIN`, porque la consulta de horarios
gasta 1,2–2,3 s mientras RAPTOR gasta 0,25–0,52 s en estas corridas.

## Comando de diagnóstico

El test de escritorio emite contadores para el fixture:

```powershell
flutter test test/transit_search_debug_test.dart
```

Para cinco mediciones PROFILE en el teléfono conectado, sin interacción manual:

```powershell
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/transit_search_profile_test.dart -d R5CW915LYXH
```

Ejecuta cinco corridas por cada uno de cuatro pares y prepara el worker de
`WalkGraph` antes de cronometrar. Si la base es sintética o no tiene metadata,
instala la seed empaquetada. Emite `[performance] device.feed` y
`[performance] device.fixed_search` con procedencia, duración, top 3 y
contadores por búsqueda. El teléfono debe estar autorizado en ADB.

## Fixture de equivalencia

`test/fixtures/transit_route_baseline.json` congela el mejor plan y el top 3
de 10 pares a las 08:00 del 24/11/2026. La seed empaquetada declara el origen
GTFS oficial STM y `synthetic=0`; la licencia de uso real/distribución consta
como pendiente en `docs/public_data_licenses.md`. `test/transit_route_fixture_test.dart`
contrasta el mejor resultado y emite el top 3 actual; no garantiza igualdad
del top 3.
