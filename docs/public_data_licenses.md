# Licencias de los datos (estado: BLOQUEANTE para publicar)

Fecha: 24-11-2026

- **Seed GTFS (`assets/transit_db/rumbo_transit_seed.db`)**: ajustes dicen que los
  datos de tránsito no tienen licencia para uso real. Bloqueante para publicar.
  A resolver antes de cualquier publicación (App Store / Play Store).
- **Seed peatonal (`assets/walk_graph/walk_graph_seed.bin`)**: estado pendiente de
  verificar licencia (Geofabrik extract + Grafana? consultar).
- **Datos de prueba**: identificados como sintéticos y no oficiales (AGENTS.md).

Flujo para regenerar la seed antes de 2026-12-10 (vencimiento 2026-12-17, luego
plantar hoy): workflow de release o asset de Release, sin depender de un artefacto
viejo (30 días).

Lectura obligatoria antes de publicar v1.0.1+: este archivo.
