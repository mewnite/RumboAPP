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

## Cambios aplicados

- Se conservan las 15 paradas endpoint para preservar equivalencia.
- Los puntos de transbordo se limitan a los 6 más cercanos, ordenados por
  distancia, dentro del radio configurado.
- `WalkGraph` cachea rutas peatonales por coordenadas redondeadas.
- La búsqueda Android sigue ejecutándose en isolate: el flujo usa
  `walk_graph_worker_io.dart` y, si no hay worker disponible,
  `plan_search_isolate_io.dart`.

## Comando de diagnóstico

Ejecutar en debug/profile:

```powershell
flutter test test/transit_search_debug_test.dart --plain-name "debug fixed Montevideo route emits performance counters"
```

El recorrido fijo usa Centro hacia Punta Carretas y emite líneas
`[performance] trip.search_counts` y `trip.stage_transit_search`.

## Fixture de equivalencia

`test/fixtures/transit_route_baseline.json` congela el mejor plan y el top 3
de 10 pares reales del seed de Montevideo a las 08:00 del 24/11/2026.
`test/transit_route_fixture_test.dart` verifica que el mejor resultado de la
versión optimizada llegue antes o a la misma hora.
