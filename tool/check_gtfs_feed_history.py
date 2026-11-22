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
FIELDS = [
    "checked_at",
    "sha256",
    "size_bytes",
    "feed_version",
    "feed_start_date",
    "feed_end_date",
    "feed_publisher",
    "last_modified",
    "etag",
]


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
    zip_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(suffix=".zip", delete=False) as tmp:
            zip_path = Path(tmp.name)
            with urllib.request.urlopen(request, timeout=90) as response:
                status = response.status
                headers = response.headers
                if status < 200 or status >= 300:
                    print(f"GTFS download failed: HTTP {status}", file=sys.stderr)
                    return 1
                last_modified = headers.get("Last-Modified", "")
                etag = headers.get("ETag", "")
                tmp.write(response.read())

        assert zip_path is not None
        digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
        size = zip_path.stat().st_size
        info = read_feed_info(zip_path)
        checked_at = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

        row = {
            "checked_at": checked_at,
            "sha256": digest,
            "size_bytes": size,
            "feed_version": info.get("feed_version", ""),
            "feed_start_date": info.get("feed_start_date", ""),
            "feed_end_date": info.get("feed_end_date", ""),
            "feed_publisher": info.get("feed_publisher_name", ""),
            "last_modified": last_modified,
            "etag": etag,
        }

        HISTORY.parent.mkdir(parents=True, exist_ok=True)
        existing_rows = []
        if HISTORY.exists():
            with HISTORY.open("r", newline="", encoding="utf-8") as handle:
                existing_rows = list(csv.DictReader(handle))
        existing_rows.append(row)

        with tempfile.NamedTemporaryFile(
            "w",
            newline="",
            encoding="utf-8",
            dir=HISTORY.parent,
            delete=False,
        ) as history_tmp:
            history_path = Path(history_tmp.name)
            writer = csv.DictWriter(history_tmp, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(
                {field: previous.get(field, "") for field in FIELDS}
                for previous in existing_rows
            )
        history_path.replace(HISTORY)
        print(
            f"{checked_at},{digest},{size},{info.get('feed_version', '')},"
            f"last_modified={last_modified},etag={etag}"
        )
        return 0
    finally:
        if zip_path is not None:
            zip_path.unlink(missing_ok=True)


if __name__ == "__main__":
    raise SystemExit(main())
