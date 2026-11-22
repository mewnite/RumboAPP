import csv
import hashlib
import os
import sys
import tempfile
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path


URL = os.environ.get(
    "RUMBO_API_BASE_URL",
    "https://rumboapp.onrender.com",
) + "/gtfs/latest"
HISTORY = Path("docs/feed_history.csv")


def read_feed_info(zip_path: Path) -> dict[str, str]:
    with zipfile.ZipFile(zip_path) as archive:
        if "feed_info.txt" not in archive.namelist():
            return {}
        with archive.open("feed_info.txt") as raw:
            rows = csv.DictReader(
                (line.decode("utf-8-sig") for line in raw),
            )
            return next(rows, {})


def main() -> int:
    request = urllib.request.Request(
        URL,
        headers={"User-Agent": "RumboAPP/1.0 feed-history"},
    )
    with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
        zip_path = Path(tmp.name)
        with urllib.request.urlopen(request, timeout=90) as response:
            if response.status < 200 or response.status >= 300:
                print(f"GTFS download failed: HTTP {response.status}", file=sys.stderr)
                return 1
            tmp.write(response.read())

    try:
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        size = zip_path.stat().st_size
        info = read_feed_info(zip_path)
        checked_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        rows = []
        if HISTORY.exists():
            with HISTORY.open("r", newline="", encoding="utf-8") as handle:
                rows = list(csv.DictReader(handle))
        if not rows or rows[-1].get("sha256") != digest:
            with HISTORY.open("a", newline="", encoding="utf-8") as handle:
                if not HISTORY.stat().st_size:
                    writer = csv.DictWriter(
                        handle,
                        fieldnames=[
                            "checked_at",
                            "sha256",
                            "size_bytes",
                            "feed_version",
                            "feed_start_date",
                            "feed_end_date",
                            "feed_publisher",
                        ],
                    )
                    writer.writeheader()
                writer = csv.DictWriter(
                    handle,
                    fieldnames=[
                        "checked_at",
                        "sha256",
                        "size_bytes",
                        "feed_version",
                        "feed_start_date",
                        "feed_end_date",
                        "feed_publisher",
                    ],
                )
                writer.writerow(
                    {
                        "checked_at": checked_at,
                        "sha256": digest,
                        "size_bytes": size,
                        "feed_version": info.get("feed_version", ""),
                        "feed_start_date": info.get("feed_start_date", ""),
                        "feed_end_date": info.get("feed_end_date", ""),
                        "feed_publisher": info.get("feed_publisher_name", ""),
                    }
                )
        print(
            f"{checked_at},{digest},{size},{info.get('feed_version', '')}"
        )
        return 0
    finally:
        zip_path.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
