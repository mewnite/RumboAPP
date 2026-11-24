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
| Pocitos–Portones | 9.372 | 221 |
| Cordón–Buceo | 6.736 | 65 |
| Centro–Punta Carretas | 7.304 | 207 |
| Tres Cruces–Buceo | 5.800 | 364 |
| Centro–Cordón | 9.218 | 206 |
| Aguada–Barrio Sur | 8.362 | 158 |
| Parque Rodó | 4.276 | 316 |
| Unión–Manga | 978 | 170 |
| Cerro–Centro | 6.524 | 169 |
| Malvín–Nueva Palma (sin servicio) | 0 | 0 |

Todas las búsquedas con servicio quedaron debajo de 1 s en escritorio. El
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
08:27:16. Para los diez pares del fixture sin grafo, ningún mejor plan RAPTOR
llega después del mejor baseline; cinco pares con servicio devuelven menos de
tres opciones. Al permitir dos transbordos el tiempo de escritorio subió en
ocho de nueve pares con servicio en la ejecución única, pero quedó por debajo
de 1 s en todos.

## Comparación completa ESCRITORIO / TELÉFONO

Cinco ejecuciones del mismo planificador, mismo recorrido Pocitos–Portones,
fecha fija y dos transbordos; incluyen SQLite, carga de horarios, búsqueda y
grafo peatonal:

| Métrica | ESCRITORIO (Windows) | MEDIDO EN TELÉFONO (SM-A346M, PROFILE) |
|---|---:|---:|
| `trip.plan`, mediana (rango) | 1.034 ms (968–1.187) | 2.727 ms (2.664–3.488) |
| `trip.stage_schedule_stops`, mediana (rango) | 812 ms (721–831) | 2.339 ms (2.187–2.908) |
| `trip.stage_transit_search`, mediana (rango) | 171 ms (158–279) | 332 ms (267–438) |

La lentitud completa teléfono/escritorio es 2,64× por medianas. El isolate
transit-only es 1,94×; el tiempo dominante restante es cargar horarios SQLite,
no RAPTOR. Las cinco búsquedas PROFILE cumplieron el objetivo de menos de 5 s.
`trip.stage_search`/`trip.stage_transit_search` corren en el worker isolate
peatonal, no en el hilo de UI.

## Comando de diagnóstico

El test de escritorio emite contadores para el fixture:

```powershell
flutter test test/transit_search_debug_test.dart
```

Para cinco mediciones PROFILE en el teléfono conectado, sin interacción manual:

```powershell
flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/transit_search_profile_test.dart -d R5CW915LYXH
```

El recorrido fijo es Pocitos–Portones; instala la seed local si la base no está
presente y prepara el worker de `WalkGraph` antes de cronometrar. Emite
`[performance] device.fixed_search` con las cinco duraciones, el top 3 y los
contadores por búsqueda. El teléfono debe estar autorizado en ADB.

## Fixture de equivalencia

`test/fixtures/transit_route_baseline.json` congela el mejor plan y el top 3
de 10 pares del seed de prueba de Montevideo a las 08:00 del 24/11/2026.
`test/transit_route_fixture_test.dart` contrasta el mejor resultado y emite el
top 3 actual; no implica que los datos sintéticos sean servicio oficial.
