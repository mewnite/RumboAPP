#!/usr/bin/env python3
"""Build a reproducible Montevideo walking seed from a pinned Geofabrik PBF."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = Path(__file__).with_name("manifest.json")
USER_AGENT = "RumboAPP seed builder (+https://github.com/mewnite/RumboAPP)"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run_osmium(*arguments: str) -> None:
    if shutil.which("osmium"):
        subprocess.run(["osmium", *arguments], check=True)
        return
    if sys.platform != "win32" or not shutil.which("wsl"):
        raise FileNotFoundError(
            "osmium-tool is required; install it with your OS package manager"
        )
    distro = os.environ.get("RUMBO_OSMIUM_WSL_DISTRO", "Ubuntu")

    def to_wsl_path(value: str) -> str:
        converted = subprocess.run(
            ["wsl", "--distribution", distro, "--exec", "wslpath", "-a", value],
            check=True,
            capture_output=True,
            text=True,
        )
        return converted.stdout.strip()

    translated = []
    for argument in arguments:
        if argument.startswith("--output="):
            translated.append(f"--output={to_wsl_path(argument.split('=', 1)[1])}")
        elif argument.endswith((".pbf", ".geojson")):
            translated.append(to_wsl_path(argument))
        else:
            translated.append(argument)
    subprocess.run(
        ["wsl", "--distribution", distro, "--exec", "osmium", *translated],
        check=True,
    )


def osmium_version() -> str:
    if shutil.which("osmium"):
        command = ["osmium", "--version"]
    elif sys.platform == "win32" and shutil.which("wsl"):
        command = [
            "wsl",
            "--distribution",
            os.environ.get("RUMBO_OSMIUM_WSL_DISTRO", "Ubuntu"),
            "--exec",
            "osmium",
            "--version",
        ]
    else:
        raise FileNotFoundError("osmium-tool is not installed")
    response = subprocess.run(
        command, check=True, capture_output=True, text=True
    )
    prefix = "osmium version "
    first_line = response.stdout.splitlines()[0]
    return first_line.removeprefix(prefix)


def clip_line_string(
    coordinates: list[list[float]], bbox: dict[str, float]
) -> list[list[list[float]]]:
    def clip_segment(
        start: list[float], end: list[float]
    ) -> tuple[list[float], list[float]] | None:
        x0, y0 = start[0], start[1]
        dx, dy = end[0] - x0, end[1] - y0
        lower, upper = 0.0, 1.0
        boundaries = (
            (-dx, x0 - bbox["west"]),
            (dx, bbox["east"] - x0),
            (-dy, y0 - bbox["south"]),
            (dy, bbox["north"] - y0),
        )
        for direction, distance in boundaries:
            if direction == 0:
                if distance < 0:
                    return None
                continue
            fraction = distance / direction
            if direction < 0:
                lower = max(lower, fraction)
            else:
                upper = min(upper, fraction)
            if lower > upper:
                return None
        return (
            [x0 + lower * dx, y0 + lower * dy],
            [x0 + upper * dx, y0 + upper * dy],
        )

    def same_point(left: list[float], right: list[float]) -> bool:
        return abs(left[0] - right[0]) < 1e-12 and abs(left[1] - right[1]) < 1e-12

    parts: list[list[list[float]]] = []
    current: list[list[float]] = []
    for start, end in zip(coordinates, coordinates[1:]):
        clipped = clip_segment(start, end)
        if clipped is None:
            if len(current) >= 2:
                parts.append(current)
            current = []
            continue
        clipped_start, clipped_end = clipped
        if current and same_point(current[-1], clipped_start):
            if not same_point(current[-1], clipped_end):
                current.append(clipped_end)
        else:
            if len(current) >= 2:
                parts.append(current)
            current = [clipped_start, clipped_end]
    if len(current) >= 2:
        parts.append(current)
    return parts


def feature_collection_to_overpass(
    source: Path, destination: Path, bbox: dict[str, float]
) -> tuple[int, int]:
    collection = json.loads(source.read_text(encoding="utf-8"))
    if not isinstance(collection, dict) or not isinstance(
        collection.get("features"), list
    ):
        raise ValueError("osmium export did not produce a GeoJSON FeatureCollection")
    elements = []
    exported_way_count = 0
    for feature in collection["features"]:
        if not isinstance(feature, dict):
            continue
        geometry = feature.get("geometry")
        properties = feature.get("properties")
        if (
            not isinstance(geometry, dict)
            or geometry.get("type") != "LineString"
            or not isinstance(properties, dict)
            or not isinstance(properties.get("highway"), str)
        ):
            continue
        coordinates = geometry.get("coordinates")
        if not isinstance(coordinates, list) or len(coordinates) < 2:
            continue
        exported_way_count += 1
        valid_coordinates = [
            coordinate
            for coordinate in coordinates
            if isinstance(coordinate, list)
            and len(coordinate) >= 2
            and isinstance(coordinate[0], (int, float))
            and isinstance(coordinate[1], (int, float))
        ]
        clipped_parts = clip_line_string(valid_coordinates, bbox)
        tags = {
            key: value
            for key, value in properties.items()
            if not key.startswith("@") and isinstance(value, (str, int, float))
        }
        way_id = properties.get("@id", properties.get("id", feature.get("id", 0)))
        try:
            way_id = int(str(way_id).split("/")[-1])
        except ValueError:
            way_id = 0
        for part in clipped_parts:
            elements.append(
                {
                    "type": "way",
                    "id": way_id,
                    "tags": tags,
                    "geometry": [
                        {"lat": coordinate[1], "lon": coordinate[0]}
                        for coordinate in part
                    ],
                }
            )
    destination.write_text(
        json.dumps({"elements": elements}, separators=(",", ":")),
        encoding="utf-8",
    )
    return exported_way_count, len(elements)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input-pbf",
        type=Path,
        help="use a local copy of the verified clipped Montevideo extract",
    )
    parser.add_argument(
        "--normalized-output",
        type=Path,
        help="also save normalized OSM JSON for local comparisons",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "build" / "seeds" / "walk_graph_seed.bin",
    )
    parser.add_argument(
        "--metadata-output",
        type=Path,
        default=ROOT / "build" / "seeds" / "walk_graph_seed_manifest.json",
    )
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    expected_hash = manifest["clipped_extract_sha256"]
    source = args.input_pbf or (
        ROOT
        / "build"
        / "seed_source"
        / manifest["clipped_extract_file"]
    )
    source.parent.mkdir(parents=True, exist_ok=True)
    if not source.exists():
        request = urllib.request.Request(
            manifest["clipped_extract_url"], headers={"User-Agent": USER_AGENT}
        )
        temp_source = source.with_name(f"{source.name}.download")
        try:
            with urllib.request.urlopen(request, timeout=180) as response:
                with temp_source.open("wb") as target:
                    shutil.copyfileobj(response, target)
                    target.flush()
                    os.fsync(target.fileno())
            os.replace(temp_source, source)
        finally:
            if temp_source.exists():
                temp_source.unlink()
    actual_hash = sha256_file(source)
    if actual_hash != expected_hash:
        raise ValueError(
            f"Clipped Montevideo PBF SHA-256 mismatch: "
            f"expected {expected_hash}, got {actual_hash}"
        )

    bbox = manifest["bbox"]
    source_bytes = source.stat().st_size
    osmium_tool_version = osmium_version()
    bbox_argument = ",".join(
        str(bbox[key]) for key in ("west", "south", "east", "north")
    )
    with tempfile.TemporaryDirectory(prefix="rumbo-walk-seed-") as work:
        work_dir = Path(work)
        selected = work_dir / "pedestrian.osm.pbf"
        exported = work_dir / "pedestrian.geojson"
        normalized = args.normalized_output or work_dir / "pedestrian.json"
        normalized.parent.mkdir(parents=True, exist_ok=True)
        run_osmium(
            "tags-filter",
            f"--output={selected}",
            str(source),
            "w/highway",
        )
        run_osmium(
            "export",
            "--add-unique-id=type_id",
            "--geometry-types=linestring",
            f"--output={exported}",
            str(selected),
        )
        exported_way_count, clipped_way_count = feature_collection_to_overpass(
            exported, normalized, bbox
        )
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.metadata_output.parent.mkdir(parents=True, exist_ok=True)
        dart_arguments = [
            "run",
            "tool/build_walk_graph_seed.dart",
            f"--input={normalized}",
            f"--output={args.output.resolve()}",
            f"--metadata-output={args.metadata_output.resolve()}",
            f"--source-date={manifest['source_date']}",
            f"--source-sha256={expected_hash}",
            f"--source-url={manifest['clipped_extract_url']}",
            f"--source-bytes={source_bytes}",
            f"--upstream-sha256={manifest['source_sha256']}",
            f"--upstream-url={manifest['source_url']}",
            f"--osmium-tool-version={osmium_tool_version}",
            f"--bbox={bbox_argument}",
            f"--exported-way-count={exported_way_count}",
            f"--clipped-way-count={clipped_way_count}",
        ]
        command = (
            [os.environ.get("COMSPEC", "cmd.exe"), "/c", "dart", *dart_arguments]
            if os.name == "nt"
            else ["dart", *dart_arguments]
        )
        subprocess.run(command, cwd=ROOT, check=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"walk_seed_build_failed={error}", file=sys.stderr)
        raise SystemExit(1) from error
