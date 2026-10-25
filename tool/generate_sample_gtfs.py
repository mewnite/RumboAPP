"""Create the tiny synthetic GTFS and STM GeoJSON fixtures used by tests.

All routes, units and stops are fictional. Coordinates are sample points around
Rumbo's configured Montevideo map center and do not identify actual bus stops.
"""
import csv
import io
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_ZIP = ROOT / "assets/sample_gtfs/sample_gtfs.zip"
STM_SAMPLE = ROOT / "test/fixtures/stm_online_sample.json"
CENTER_LAT, CENTER_LON = -34.9058, -56.1991


def csv_bytes(rows):
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode("utf-8")


def make_gtfs():
    tables = {
        "agency.txt": [{"agency_id": "DEMO", "agency_name": "Rumbo - datos sintéticos de prueba", "agency_timezone": "America/Montevideo", "agency_lang": "es"}],
        "stops.txt": [],
        "routes.txt": [
            {"route_id": "DEMO1", "route_short_name": "R1", "route_long_name": "Circuito ficticio Centro", "route_type": 3, "route_color": "1B658D", "route_text_color": "FFFFFF"},
            {"route_id": "DEMO2", "route_short_name": "R2", "route_long_name": "Circuito ficticio Rambla", "route_type": 3, "route_color": "D4E257", "route_text_color": "0A122A"},
            {"route_id": "DEMO3", "route_short_name": "R3", "route_long_name": "Circuito ficticio Nocturno", "route_type": 3, "route_color": "5FA8D3", "route_text_color": "0A122A"},
        ],
        "trips.txt": [], "stop_times.txt": [], "shapes.txt": [],
        "calendar.txt": [
            {"service_id": "WEEK", "monday": 1, "tuesday": 1, "wednesday": 1, "thursday": 1, "friday": 1, "saturday": 0, "sunday": 0, "start_date": "20260101", "end_date": "20271231"},
            {"service_id": "SAT", "monday": 0, "tuesday": 0, "wednesday": 0, "thursday": 0, "friday": 0, "saturday": 1, "sunday": 0, "start_date": "20260101", "end_date": "20271231"},
            {"service_id": "SUN", "monday": 0, "tuesday": 0, "wednesday": 0, "thursday": 0, "friday": 0, "saturday": 0, "sunday": 1, "start_date": "20260101", "end_date": "20271231"},
        ],
        "feed_info.txt": [{"feed_publisher_name": "Rumbo - datos sintéticos de prueba, no oficiales", "feed_publisher_url": "", "feed_lang": "es", "feed_start_date": "20260101", "feed_end_date": "20271231", "feed_version": "demo-1"}],
    }
    for index in range(18):
        tables["stops.txt"].append({"stop_id": f"D{index + 1:02}", "stop_name": f"Parada ficticia {index + 1:02}", "stop_lat": f"{CENTER_LAT + ((index % 6) - 3) * .003:.6f}", "stop_lon": f"{CENTER_LON + ((index // 6) - 1) * .004:.6f}"})
    external_id = 101
    for route_index, route_id in enumerate(("DEMO1", "DEMO2", "DEMO3")):
        for direction in ("0", "1"):
            trip_id = f"{route_id}_{direction}"
            shape_id = f"S{route_index + 1}{direction}"
            tables["trips.txt"].append({"route_id": route_id, "service_id": ("WEEK", "SAT", "SUN")[route_index], "trip_id": trip_id, "trip_headsign": f"Destino ficticio {direction}", "direction_id": direction, "shape_id": shape_id, "variant_id": external_id})
            for sequence in range(1, 9):
                stop_number = (sequence - 1 + route_index * 5 + (0 if direction == "0" else 9)) % 18 + 1
                hour = 23 if route_index == 2 and sequence == 7 else 25 if route_index == 2 and sequence == 8 else 6 + route_index * 2 + (direction == "1")
                time = f"{hour:02}:00:00"
                tables["stop_times.txt"].append({"trip_id": trip_id, "arrival_time": time, "departure_time": time, "stop_id": f"D{stop_number:02}", "stop_sequence": sequence})
                tables["shapes.txt"].append({"shape_id": shape_id, "shape_pt_lat": tables["stops.txt"][stop_number - 1]["stop_lat"], "shape_pt_lon": tables["stops.txt"][stop_number - 1]["stop_lon"], "shape_pt_sequence": sequence})
            external_id += 1
    SAMPLE_ZIP.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(SAMPLE_ZIP, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, rows in tables.items():
            archive.writestr(name, csv_bytes(rows))


def feature(source_id, variant, *, line="R1", speed=32, coordinates=(-56.1991, -34.9058), company=1, bus=1):
    return {"type": "Feature", "geometry": {"type": "Point", "coordinates": list(coordinates)}, "properties": {"id": source_id, "codigoEmpresa": company, "codigoBus": bus, "variante": variant, "linea": line, "sublinea": "Sintética", "tipoLinea": 1, "tipoLineaDesc": "Prueba", "destino": 12, "destinoDesc": "Destino sintético", "subsistema": 1, "subsistemaDesc": "Prueba", "version": "demo", "velocidad": speed, "frecuencia": 65535}}


def make_stm_fixture():
    features = [
        feature("unit-a", 101),
        feature("unit-b", 102, speed=0, bus=2),
        feature("bad-coordinate", 103, coordinates=(-258.02588, -258.02588), bus=3),
        feature("outside-uruguay", 104, coordinates=(-60, -36), bus=4),
        feature("unit-c", 105, line="14AB", bus=1),
        feature("repeat-id", 106, bus=5),
        feature("repeat-id", 107, line="R3", speed=8, bus=5),
        {"type": "Feature", "geometry": None, "properties": {"id": "no-geometry"}},
    ]
    missing = feature("missing-field", 109, bus=9)
    del missing["properties"]["velocidad"]
    features.append(missing)
    features.append(feature("unknown-variant", 999999, bus=10))
    STM_SAMPLE.parent.mkdir(parents=True, exist_ok=True)
    STM_SAMPLE.write_text(json.dumps({"type": "FeatureCollection", "features": features}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def make_parser_fixtures():
    fixtures = ROOT / "test/fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    (fixtures / "gtfs_bom.csv").write_bytes(b'\xef\xbb\xbfstop_id,stop_name\r\nS1,"Plaza, Centro"\r\n')
    (fixtures / "gtfs_invalid_rows.csv").write_text(
        "stop_id,stop_name,stop_lat,stop_lon\nS1,Correcta,-34.9,-56.1\nS2,Invalida,not-a-lat\n",
        encoding="utf-8",
    )
    (fixtures / "gtfs_hours.csv").write_text("trip_id,arrival_time,departure_time\nt1,25:10:00,25:10:00\n", encoding="utf-8")
    with zipfile.ZipFile(fixtures / "gtfs_missing_required.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("stops.txt", "stop_id,stop_name,stop_lat,stop_lon\ns1,Stop,-34.9,-56.1\n")
    (fixtures / "gtfs_corrupt.zip").write_bytes(b"PK\x03\x04invalid-archive")


if __name__ == "__main__":
    make_gtfs()
    make_stm_fixture()
    make_parser_fixtures()

