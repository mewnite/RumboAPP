#!/usr/bin/env python3
"""Verifica el ETA oficial de arribos por parada a través del proxy.

Dado un stopId y una línea, consulta el endpoint del proxy
(`GET /api/busstops/{stopId}/upcomingbuses`) y registra, junto con la
posición del bus y la hora de la respuesta, el ETA extraído — para
contrastar más tarde con la llegada real y así fijar la unidad del ETA
oficial.

Requiere CLIENT_ID/CLIENT_SECRET en `.env` (autentica el proxy) o
`RUMBO_PROXY_BASE_URL` para apuntar a otro proxy
(default: http://127.0.0.1:8765).

Uso:
    python tool/verify_official_eta.py --stop 1234 --line 522 [--amount 5]

Salida: registra un registro JSONL en `official_eta_log.jsonl` (raíz del
repo) y imprime un resumen a stdout.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

LOG_FILE = Path("official_eta_log.jsonl")


def _as_number(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def extract_eta_minutes(body):
    """Extrae el ETA en minutos — campos conocidos, defensivo (contrato sin verificar)."""
    if not isinstance(body, dict):
        return None
    for key in ("eta_minutes", "minutes", "eta", "estimated_minutes", "arrival_minutes"):
        value = _as_number(body.get(key))
        if value is not None:
            return int(value)
    for key in ("eta_seconds", "arrival_seconds", "seconds", "estimated_arrival_seconds"):
        value = _as_number(body.get(key))
        if value is not None:
            return math.ceil(value / 60)
    return None


def extract_bus_position(body):
    """Extrae la posición del bus (lat/lon) defensivamente."""
    if not isinstance(body, dict):
        return None
    for key in ("vehicle", "bus", "position", "location", "point", "data"):
        value = body.get(key)
        if isinstance(value, dict):
            lat = _as_number(value.get("latitude") or value.get("lat"))
            lon = _as_number(value.get("longitude") or value.get("lon"))
            if lat is not None and lon is not None:
                return {"latitude": lat, "longitude": lon}
    lat = _as_number(body.get("latitude") or body.get("lat"))
    lon = _as_number(body.get("longitude") or body.get("lon"))
    if lat is not None and lon is not None:
        return {"latitude": lat, "longitude": lon}
    return None


def fetch(stop_id: str, line: str, amount: int, base_url: str):
    url = (
        f"{base_url}/api/busstops/{stop_id}/upcomingbuses"
        f"?lines={line}&amountperline={amount}"
    )
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": "Rumbo verify-eta/1.0"},
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            status = response.status
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        status = error.code
        try:
            body = json.loads(error.read().decode("utf-8"))
        except Exception:
            body = None
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        print(f"ERROR: no se pudo consultar la API: {error}", file=sys.stderr)
        return status=None, body=None, error=str(error)
    return status, body, None


def log_record(record):
    with LOG_FILE.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    return LOG_FILE


def main() -> int:
    parser = argparse.ArgumentParser(description="Verifica el ETA oficial de arribos por parada.")
    parser.add_argument("--stop", required=True, help="ID de la parada (stopId).")
    parser.add_argument("--line", required=True, help="Línea a consultar (filtro lines).")
    parser.add_argument(
        "--amount", type=int, default=5, choices=range(1, 6),
        help="amountperline (1-5).",
    )
    args = parser.parse_args()

    if not (1 <= args.amount <= 5):
        print("ERROR: amountperline debe estar entre 1 y 5.", file=sys.stderr)
        return 2
    if not args.stop.isdigit():
        print("ERROR: --stop debe ser el stopId numérico de la parada.", file=sys.stderr)
        return 2

    base_url = os.environ.get("RUMBO_PROXY_BASE_URL", "http://127.0.0.1:8765")
    status, body, error = fetch(args.stop, args.line, args.amount, base_url)

    record = {
        "ts": time.time(),
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "stop_id": args.stop,
        "line": args.line,
        "amountperline": args.amount,
        "status": status,
        "eta_minutes": extract_eta_minutes(body) if status == 200 else None,
        "bus": extract_bus_position(body),
        "raw": body,
    }
    path = log_record(record)
    print(f"Registrado en {path}")
    print(json.dumps(record, ensure_ascii=False, indent=2))
    return 0 if status is not None and status == 200 else 1


if __name__ == "__main__":
    raise SystemExit(main())
