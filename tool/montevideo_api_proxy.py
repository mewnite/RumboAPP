"""Local-only OAuth proxy for testing Montevideo API without APK secrets."""

from __future__ import annotations

import json
import io
import os
import re
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TOKEN_URL = (
    "https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/"
    "protocol/openid-connect/token"
)
API_BASE = "https://api.montevideo.gub.uy/api/transportepublico"
LIVE_MIN_INTERVAL_SECONDS = 10
GTFS_CACHE_SECONDS = 24 * 60 * 60
REFERENCE_DATA_CACHE_SECONDS = 24 * 60 * 60
PLACE_SEARCH_CACHE_SECONDS = 24 * 60 * 60
MAX_GTFS_BYTES = 100 * 1024 * 1024
PLACE_SEARCH_URL = os.environ.get(
    "RUMBO_GEOCODING_URL",
    "https://nominatim.openstreetmap.org/search",
)
RUMBO_USER_AGENT = "RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)"
# Accepted from the app's place sources. The proxy builds its own upstream
# query, so these only describe the client request and never reach Nominatim
# verbatim.
PLACE_QUERY_PARAMETERS = {
    "q",
    "countrycodes",
    "format",
    "limit",
    "bias_lat",
    "bias_lon",
}


class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


class OAuthClient:
    def __init__(self, credentials: dict[str, str]):
        self._client_id = credentials.get("CLIENT_ID", "")
        self._client_secret = credentials.get("CLIENT_SECRET", "")
        self._access_token = ""
        self._token_expires_at = 0.0
        self._lock = threading.Lock()

    def access_token(self) -> str:
        with self._lock:
            if self._access_token and time.monotonic() < self._token_expires_at:
                return self._access_token
            if not self._client_id or not self._client_secret:
                raise ApiError(
                    503,
                    "Faltan CLIENT_ID y CLIENT_SECRET en el archivo .env local.",
                )
            body = urllib.parse.urlencode(
                {
                    "grant_type": "client_credentials",
                    "client_id": self._client_id,
                    "client_secret": self._client_secret,
                }
            ).encode()
            request = urllib.request.Request(
                TOKEN_URL,
                data=body,
                headers={"Content-Type": "application/x-www-form-urlencoded"},
                method="POST",
            )
            try:
                with urllib.request.urlopen(request, timeout=20) as response:
                    payload = json.loads(response.read())
            except urllib.error.HTTPError as error:
                raise ApiError(
                    502,
                    f"El servicio OAuth respondió HTTP {error.code}.",
                ) from None
            except (urllib.error.URLError, TimeoutError):
                raise ApiError(502, "No se pudo conectar al servicio OAuth.") from None
            if not isinstance(payload, dict) or not isinstance(
                payload.get("access_token"), str
            ):
                raise ApiError(502, "Respuesta OAuth sin access_token.")
            self._access_token = payload["access_token"]
            expires_in = payload.get("expires_in", 60)
            lifetime = expires_in if isinstance(expires_in, int) else 60
            self._token_expires_at = time.monotonic() + max(5, lifetime - 20)
            return self._access_token


class ApiProxy:
    def __init__(
        self,
        credentials: dict[str, str],
        cache_directory: Path | None = None,
        minimum_live_interval: int = LIVE_MIN_INTERVAL_SECONDS,
    ):
        self._oauth = OAuthClient(credentials)
        self._cache_directory = cache_directory or (
            Path(tempfile.gettempdir()) / "rumbo-montevideo-api"
        )
        self._minimum_live_interval = minimum_live_interval
        self._last_live_request = 0.0
        self._last_live_path = ""
        self._last_live_response: tuple[int, str, bytes] | None = None
        self._reference_responses: dict[str, tuple[float, tuple[int, str, bytes]]] = {}
        self._lock = threading.Lock()
        self._place_lock = threading.Lock()
        self._place_responses: dict[str, tuple[float, tuple[int, str, bytes]]] = {}
        self._last_place_request = 0.0

    def handle(self, target: str) -> tuple[int, str, bytes, dict[str, str]]:
        parsed = urllib.parse.urlsplit(target)
        if parsed.path == "/health":
            return 200, "application/json", b'{"status":"ok"}', {}
        if parsed.path == "/geocode":
            query = self._validate_place_query(parsed.query)
            status, content_type, body = self._search_places(query)
            return status, content_type, body, {}
        if parsed.path == "/gtfs/latest":
            status, content_type, body = self._gtfs()
            return status, content_type, body, {}
        if parsed.path == "/api/buses/geo":
            query = self._validate_geo(parsed.query)
            status, content_type, body = self._live_request(f"/buses/geo?{query}")
            return status, content_type, body, {}
        if parsed.path == "/api/buses":
            query = self._validate_bus_query(parsed.query)
            status, content_type, body = self._live_request(f"/buses?{query}")
            return status, content_type, body, {}
        if parsed.path == "/api/linevariants":
            status, content_type, body = self._cached_reference(
                "/buses/linevariants"
            )
            return status, content_type, body, {}
        line_variant = re.fullmatch(r"/api/linevariants/([A-Za-z0-9_-]+)", parsed.path)
        if line_variant:
            status, content_type, body = self._cached_reference(
                f"/buses/linevariants/{line_variant.group(1)}"
            )
            return status, content_type, body, {}
        upcoming = re.fullmatch(r"/api/busstops/(\d+)/upcomingbuses", parsed.path)
        if upcoming:
            query = self._validate_upcoming_query(parsed.query)
            status, content_type, body = self._live_request(
                f"/buses/busstops/{upcoming.group(1)}/upcomingbuses?{query}"
            )
            return status, content_type, body, {}
        if parsed.path == "/api/busstops":
            status, content_type, body = self._cached_reference("/buses/busstops")
            return status, content_type, body, {}
        stop_lines = re.fullmatch(r"/api/busstops/(\d+)/lines", parsed.path)
        if stop_lines:
            status, content_type, body = self._cached_reference(
                f"/buses/busstops/{stop_lines.group(1)}/lines"
            )
            return status, content_type, body, {}
        raise ApiError(404, "Ruta no habilitada en el proxy local.")

    def _validate_place_query(self, query: str) -> str:
        values = self._query_values(query)
        if (
            set(values) - PLACE_QUERY_PARAMETERS
            or len(values.get("q", [])) != 1
        ):
            raise ApiError(400, "Se requiere una única búsqueda de lugar.")
        search = values["q"][0].strip()
        if not 3 <= len(search) <= 160:
            raise ApiError(400, "La búsqueda debe tener entre 3 y 160 caracteres.")
        if values.get("countrycodes", ["uy"]) != ["uy"]:
            raise ApiError(400, "El país de búsqueda debe ser Uruguay.")
        if values.get("format", ["jsonv2"]) != ["jsonv2"]:
            raise ApiError(400, "El formato de búsqueda no está permitido.")
        if "limit" in values:
            try:
                limit = int(values["limit"][0])
            except ValueError:
                raise ApiError(400, "El límite de búsqueda no es válido.") from None
            if not 1 <= limit <= 10:
                raise ApiError(
                    400, "El límite de búsqueda debe estar entre 1 y 10."
                )
        if ("bias_lat" in values) != ("bias_lon" in values):
            raise ApiError(400, "La referencia de búsqueda está incompleta.")
        if "bias_lat" in values:
            try:
                latitude = float(values["bias_lat"][0])
                longitude = float(values["bias_lon"][0])
            except ValueError:
                raise ApiError(400, "La referencia de búsqueda no es válida.") from None
            if (
                not -90 <= latitude <= 90
                or not -180 <= longitude <= 180
            ):
                raise ApiError(400, "La referencia de búsqueda está fuera de rango.")
        return search

    def _search_places(self, search: str) -> tuple[int, str, bytes]:
        cache_key = search.casefold()
        with self._place_lock:
            now = time.monotonic()
            cached = self._place_responses.get(cache_key)
            if (
                cached is not None
                and now - cached[0] < PLACE_SEARCH_CACHE_SECONDS
            ):
                return cached[1]
            wait = 1.0 - (now - self._last_place_request)
            if wait > 0:
                time.sleep(wait)
            params = urllib.parse.urlencode(
                {
                    "q": search,
                    "countrycodes": "uy",
                    "format": "jsonv2",
                    "limit": "5",
                }
            )
            request = urllib.request.Request(
                f"{PLACE_SEARCH_URL}?{params}",
                headers={
                    "Accept": "application/json",
                    "User-Agent": RUMBO_USER_AGENT,
                },
            )
            self._last_place_request = time.monotonic()
            try:
                with urllib.request.urlopen(request, timeout=20) as response:
                    body = response.read(1024 * 1024 + 1)
                    if len(body) > 1024 * 1024:
                        raise ApiError(502, "Respuesta de lugares demasiado grande.")
                    result = (
                        response.status,
                        response.headers.get("Content-Type", "application/json"),
                        body,
                    )
            except urllib.error.HTTPError as error:
                raise ApiError(
                    502,
                    f"El servicio de lugares respondió HTTP {error.code}.",
                ) from None
            except (urllib.error.URLError, TimeoutError):
                raise ApiError(502, "No se pudo conectar al servicio de lugares.") from None
            self._place_responses[cache_key] = (time.monotonic(), result)
            return result

    def _live_request(self, api_path: str) -> tuple[int, str, bytes]:
        now = time.monotonic()
        with self._lock:
            if (
                api_path == self._last_live_path
                and self._last_live_response is not None
                and now - self._last_live_request < self._minimum_live_interval
            ):
                return self._last_live_response
            wait = self._minimum_live_interval - (now - self._last_live_request)
            if wait > 0:
                raise ApiError(
                    429,
                    f"Límite local: reintentá en {max(1, int(wait) + 1)} segundos.",
                )
            self._last_live_request = now
            self._last_live_path = api_path
            result = self._upstream(api_path)
            self._last_live_response = result
            return result

    def _upstream(self, api_path: str) -> tuple[int, str, bytes]:
        return self._request_upstream(api_path, max_bytes=10 * 1024 * 1024)

    def _cached_reference(self, api_path: str) -> tuple[int, str, bytes]:
        now = time.monotonic()
        with self._lock:
            cached = self._reference_responses.get(api_path)
            if cached is not None and now - cached[0] < REFERENCE_DATA_CACHE_SECONDS:
                return cached[1]
            result = self._request_upstream(api_path, max_bytes=10 * 1024 * 1024)
            self._reference_responses[api_path] = (now, result)
            return result

    def _request_upstream(
        self, api_path: str, *, max_bytes: int
    ) -> tuple[int, str, bytes]:
        request = urllib.request.Request(
            API_BASE + api_path,
            headers={
                "Authorization": f"Bearer {self._oauth.access_token()}",
                "Accept": "application/json",
                "User-Agent": "Rumbo local development proxy",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                body = response.read(max_bytes + 1)
                if len(body) > max_bytes:
                    raise ApiError(502, "Respuesta de transporte demasiado grande.")
                return (
                    response.status,
                    response.headers.get("Content-Type", "application/json"),
                    body,
                )
        except urllib.error.HTTPError as error:
            message = error.read(1000).decode("utf-8", errors="replace")
            raise ApiError(
                502,
                f"El servicio de transporte respondió HTTP {error.code}: "
                f"{message[:300]}",
            ) from None
        except (urllib.error.URLError, TimeoutError):
            raise ApiError(502, "No se pudo conectar al servicio de transporte.") from None

    def _gtfs(self) -> tuple[int, str, bytes]:
        self._cache_directory.mkdir(parents=True, exist_ok=True)
        archive_path = self._cache_directory / "google_transit.zip"
        now = time.time()
        if (
            archive_path.exists()
            and now - archive_path.stat().st_mtime < GTFS_CACHE_SECONDS
        ):
            return 200, "application/zip", archive_path.read_bytes()

        token = self._oauth.access_token()
        url = f"{API_BASE}/buses/gtfs/static/latest/google_transit.zip"
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/zip",
                "User-Agent": "Rumbo local development proxy",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=90) as response:
                body = response.read(MAX_GTFS_BYTES + 1)
        except urllib.error.HTTPError as error:
            raise ApiError(
                502, f"La descarga GTFS respondió HTTP {error.code}."
            ) from None
        except (urllib.error.URLError, TimeoutError):
            raise ApiError(502, "No se pudo descargar el feed GTFS.") from None
        if len(body) > MAX_GTFS_BYTES:
            raise ApiError(502, "El ZIP GTFS supera el límite local de 100 MiB.")
        try:
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                required = {"stops.txt", "routes.txt", "trips.txt", "stop_times.txt"}
                if not required.issubset(set(archive.namelist())):
                    raise ApiError(502, "El ZIP GTFS no contiene los archivos requeridos.")
        except zipfile.BadZipFile:
            raise ApiError(502, "El servicio no devolvió un ZIP GTFS válido.") from None
        temporary_path = archive_path.with_suffix(".tmp")
        temporary_path.write_bytes(body)
        temporary_path.replace(archive_path)
        return 200, "application/zip", body

    @staticmethod
    def _query_values(query: str) -> dict[str, list[str]]:
        return urllib.parse.parse_qs(query, strict_parsing=True)

    def _validate_geo(self, query: str) -> str:
        values = self._query_values(query)
        if set(values) - {"center", "radius"}:
            raise ApiError(400, "Parámetros geo no permitidos.")
        center = values.get("center", [""])[0].split(",")
        if len(center) != 2:
            raise ApiError(400, "center debe tener el formato latitud,longitud.")
        try:
            latitude, longitude = map(float, center)
            radius = float(values.get("radius", [""])[0])
        except ValueError:
            raise ApiError(400, "Coordenadas o radio inválidos.") from None
        if (
            not -90 <= latitude <= 90
            or not -180 <= longitude <= 180
            or not 50 <= radius <= 2000
        ):
            raise ApiError(400, "Coordenadas o radio fuera del rango permitido.")
        return urllib.parse.urlencode({"center": f"{latitude},{longitude}", "radius": radius})

    def _validate_bus_query(self, query: str) -> str:
        values = self._query_values(query)
        if set(values) - {"lines", "format"}:
            raise ApiError(400, "Parámetros de buses no permitidos.")
        lines = values.get("lines", [])
        if len(lines) > 1 or (lines and not re.fullmatch(r"[A-Za-z0-9,-]{1,80}", lines[0])):
            raise ApiError(400, "Filtro de líneas inválido.")
        output_format = values.get("format", ["geojson"])[0]
        if output_format != "geojson":
            raise ApiError(400, "Solo se permite el formato GeoJSON.")
        params = {"format": output_format}
        if lines:
            params["lines"] = lines[0]
        return urllib.parse.urlencode(params)

    def _validate_upcoming_query(self, query: str) -> str:
        values = self._query_values(query)
        if set(values) - {"lines", "amountperline"}:
            raise ApiError(400, "Parámetros de arribos no permitidos.")
        lines = values.get("lines", [])
        if len(lines) != 1 or not re.fullmatch(r"[A-Za-z0-9,-]{1,80}", lines[0]):
            raise ApiError(400, "Se requiere un filtro de líneas válido.")
        amount = values.get("amountperline", ["1"])[0]
        if not amount.isdigit() or not 1 <= int(amount) <= 5:
            raise ApiError(400, "amountperline debe estar entre 1 y 5.")
        return urllib.parse.urlencode(
            {"lines": lines[0], "amountperline": int(amount), "format": "json"}
        )


def load_env(path: Path) -> dict[str, str]:
    credentials: dict[str, str] = {
        key: value
        for key in ("CLIENT_ID", "CLIENT_SECRET")
        if (value := os.environ.get(key))
    }
    if path.exists():
        for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            value = value.strip()
            if (
                len(value) >= 2
                and value[0] == value[-1]
                and value[0] in {"'", '"'}
            ):
                value = value[1:-1]
            credentials.setdefault(key.strip(), value)
    return credentials


class Handler(BaseHTTPRequestHandler):
    proxy: ApiProxy

    def _local_cors_headers(self) -> dict[str, str]:
        origin = self.headers.get("Origin", "")
        parsed = urllib.parse.urlsplit(origin)
        allowed_origin = os.environ.get("RUMBO_ALLOWED_ORIGIN", "")
        is_loopback = parsed.scheme == "http" and parsed.hostname in {
            "localhost",
            "127.0.0.1",
            "::1",
        }
        if not origin or (not is_loopback and origin != allowed_origin):
            return {}
        return {
            "Access-Control-Allow-Origin": origin,
            "Vary": "Origin",
            "Access-Control-Allow-Methods": "GET, OPTIONS",
            "Access-Control-Allow-Headers": "Accept, Content-Type",
            "Access-Control-Max-Age": "600",
            "Vary": "Origin",
        }

    def do_OPTIONS(self) -> None:
        headers = self._local_cors_headers()
        self.send_response(204 if headers else 403)
        for key, value in headers.items():
            self.send_header(key, value)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self) -> None:
        try:
            status, content_type, body, headers = self.proxy.handle(self.path)
        except ApiError as error:
            status = error.status
            content_type = "application/json; charset=utf-8"
            body = json.dumps({"error": str(error)}, ensure_ascii=False).encode()
            headers = {}
            if status == 429:
                headers["Retry-After"] = str(LIVE_MIN_INTERVAL_SECONDS)
        except Exception:
            status = 500
            content_type = "application/json; charset=utf-8"
            body = b'{"error":"Error interno del proxy local."}'
            headers = {}
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        cors_headers = self._local_cors_headers()
        for key, value in cors_headers.items():
            self.send_header(key, value)
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: object) -> None:
        print(f"{self.client_address[0]} {format % args}")


def main() -> int:
    credentials = load_env(Path(".env"))
    host = os.environ.get("RUMBO_PROXY_HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", os.environ.get("RUMBO_PROXY_PORT", "8765")))
    server = ThreadingHTTPServer((host, port), Handler)
    Handler.proxy = ApiProxy(credentials)
    print(f"Proxy de Rumbo escuchando en {host}:{port}")
    print("Límite de tiempo real: 1 consulta global cada 10 segundos.")
    if not credentials.get("CLIENT_ID") or not credentials.get("CLIENT_SECRET"):
        print(
            "Búsqueda de lugares habilitada; GTFS y tiempo real STM requieren "
            "CLIENT_ID y CLIENT_SECRET en .env."
        )
    if host == "127.0.0.1":
        print("Solo escucha en localhost; usá adb reverse para el teléfono USB.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nProxy detenido.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
