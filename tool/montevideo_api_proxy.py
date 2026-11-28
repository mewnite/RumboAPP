"""Local-only OAuth proxy for testing Montevideo API without APK secrets."""

from __future__ import annotations

import json
import io
import logging
import math
import os
import re
import tempfile
import threading
import time
import unicodedata
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
LIVE_STALE_SECONDS = 15
GTFS_CACHE_SECONDS = 24 * 60 * 60
REFERENCE_DATA_CACHE_SECONDS = 24 * 60 * 60
PLACE_SEARCH_CACHE_SECONDS = 24 * 60 * 60
MAX_GTFS_BYTES = 100 * 1024 * 1024
PLACE_SEARCH_URL = os.environ.get(
    "RUMBO_GEOCODING_URL",
    "https://photon.komoot.io/api/",
)
OVERPASS_URL = os.environ.get(
    "RUMBO_OVERPASS_URL",
    "https://overpass-api.de/api/interpreter",
)
OVERPASS_MIRROR_URL = os.environ.get(
    "RUMBO_OVERPASS_MIRROR_URL",
    "https://overpass.private.coffee/api/interpreter",
)
# MCIO bbox (lat -34.9271..-34.7167, lon -56.4048..-55.9955 from the GTFS seed)
# with a safety margin.
OVERPASS_QUERY = (
    "[out:json][timeout:90];("
    'way["highway"~"pedestrian|path|footway|service|residential|unclassified'
    '|living_street|track|tertiary|secondary|primary|primary_link'
    '|secondary_link|tertiary_link"]'
    '["foot"!="no"]["access"!="private"]'
    '["barrier"!="wall"]["barrier"!="fence"]'
    "(-34.9771,-56.4548,-34.6667,-55.9455);"
    'way["highway"="steps"]'
    '["foot"!="no"]["access"!="private"]'
    '["barrier"!="wall"]["barrier"!="fence"]'
    "(-34.9771,-56.4548,-34.6667,-55.9455);"
    'way["highway"~"motorway|motorway_link|trunk|trunk_link"]'
    '["foot"="yes"]["access"!="private"]'
    '["barrier"!="wall"]["barrier"!="fence"]'
    "(-34.9771,-56.4548,-34.6667,-55.9455);"
    ");out geom;"
)
PEDESTRIAN_CACHE_SECONDS = 24 * 60 * 60
MAX_PEDESTRIAN_BYTES = 32 * 1024 * 1024
RUMBO_USER_AGENT = "RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)"
# Nominatim viewbox order is west,north,east,south; bounds follow the
# Montevideo-area transit seed and are intentionally only an approximate bias.
MONTEVIDEO_GEOCODING_VIEWBOX = "-56.4048,-34.7167,-55.9955,-34.9271"
# Uruguay bounds used as a hard geographic filter. Montevideo receives a fixed
# location bias, never the user's GPS position.
URUGUAY_GEOCODING_BOUNDS = (-58.5, -35.2, -53.0, -30.0)
MONTEVIDEO_GEOCODING_BIAS = (-34.9037, -56.1882)
MONTEVIDEO_POI_CATALOG = {
    "auditorio nacional adela reta": {
        "official_name": "Auditorio Nacional Adela Reta",
        "aliases": ("SODRE", "Auditorio Adela Reta"),
        "category": "amenity:theatre",
    },
    "nuevo centro shopping": {
        "official_name": "Nuevo Centro Shopping",
        "aliases": ("Nuevo Centro", "Nuevo Centro Montevideo"),
        "category": "shop:mall",
    },
    "catedral metropolitana de montevideo": {
        "official_name": "Catedral Metropolitana",
        "aliases": (
            "Catedral Metropolitana",
            "Catedral Metropolitana de Montevideo",
            "Catedral de Montevideo",
        ),
        "category": "amenity:place_of_worship",
    },
    "teatro solis": {
        "official_name": "Teatro Solís",
        "aliases": ("Teatro Solis"),
        "category": "amenity:theatre",
    },
    "estadio centenario": {
        "official_name": "Estadio Centenario",
        "aliases": ("Estadio Centenario",),
        "category": "leisure:stadium",
    },
    "shopping punta carretas": {
        "official_name": "Shopping Punta Carretas",
        "aliases": ("Punta Carretas Shopping",),
        "category": "shop:mall",
    },
    "palacio salvo": {
        "official_name": "Palacio Salvo",
        "aliases": ("Edificio Palacio Salvo",),
        "category": "building:palace",
    },
}
# Accepted from the app's place sources. The proxy builds its own upstream
# query, so these only describe the client request and never reach Nominatim
# verbatim.
PLACE_QUERY_PARAMETERS = {
    "q",
    "countrycodes",
    "format",
    "limit",
}
INTERSECTION_QUERY = re.compile(
    r"^\s*(.+)\s+(?:y|x|esq\.?(?:\s+(?:de|con))?|"
    r"esquina(?:\s+(?:de|con))?|con|/|&)\s+(.+?)\s*$",
    flags=re.IGNORECASE,
)
MONTEVIDEO_CONTEXT = re.compile(r"\b(?:montevideo|uruguay)\b", re.IGNORECASE)


def geocoding_query(search: str) -> str:
    """Normalize local address syntax and add city context for geocoders."""
    normalized = unicodedata.normalize("NFKD", search)
    normalized = "".join(
        character
        for character in normalized
        if not unicodedata.combining(character)
    )
    normalized = re.sub(
        r"\bn\s*\.?\s*(?:[º°]|ro?\.?|o\.?)\s*(?=\d)",
        "",
        normalized,
        flags=re.IGNORECASE,
    )
    abbreviations = {
        "av": "avenida",
        "avda": "avenida",
        "bvar": "bulevar",
        "bvr": "bulevar",
        "bv": "bulevar",
        "gral": "general",
        "cno": "camino",
        "tte": "teniente",
        "dr": "doctor",
        "sta": "santa",
        "sto": "santo",
        "pta": "punta",
        "pto": "puerto",
        "pje": "pasaje",
        "pza": "plaza",
        "rbla": "rambla",
    }
    normalized = re.sub(
        r"\b(avda|av|bvar|bvr|bv|gral|cno|tte|dr|sta|sto|pta|pto|pje|pza|rbla)\b\.?",
        lambda match: abbreviations[match.group(1).lower()],
        normalized,
        flags=re.IGNORECASE,
    )
    normalized = re.sub(
        r"\bnuevocentro\b",
        "Nuevo Centro",
        normalized,
        flags=re.IGNORECASE,
    )
    normalized = re.sub(r"\s+", " ", normalized).strip()
    catalog_query = re.sub(r"\s+", " ", normalized).strip().casefold()
    catalog_match = next(
        (
            record
            for canonical, record in MONTEVIDEO_POI_CATALOG.items()
            if catalog_query == canonical
            or any(
                catalog_query == unicodedata.normalize("NFKD", alias).encode(
                    "ascii", "ignore"
                ).decode("ascii").casefold()
                for alias in record["aliases"]
            )
        ),
        None,
    )
    if catalog_match is not None:
        normalized = catalog_match["official_name"]
    match = INTERSECTION_QUERY.match(normalized)
    scoped_search = (
        f"{match.group(1).strip()} & {match.group(2).strip()}"
        if match
        else normalized
    )
    if MONTEVIDEO_CONTEXT.search(scoped_search):
        return scoped_search
    return f"{scoped_search}, Montevideo, Uruguay"


def classify_place_query(search: str) -> str:
    """Classify query structure without treating provider matches as evidence."""
    normalized = ApiProxy._normalize_place_text(search)
    if INTERSECTION_QUERY.match(normalized):
        return "intersection"
    if ApiProxy._address_query(normalized) is not None:
        return "address"
    if re.search(
        r"\brambla\b|\bplaya\b|\bbahia\b",
        normalized,
    ):
        return "geographic_area"
    if re.search(
        r"\bbarrio\b|\bciudad vieja\b|\bpocitos\b|\bparque rodo\b",
        normalized,
    ):
        return "neighborhood"
    if re.search(
        r"\b(shopping|teatro|estadio|catedral|auditorio|terminal|mercado|"
        r"aeropuerto|hospital|palacio|plaza|mercado)\b",
        normalized,
    ):
        return "poi"
    if re.search(
        r"\b(avenida|bulevar|camino|rambla|calle|pasaje|general)\b",
        normalized,
    ):
        return "street"
    return "unknown"


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
        self._cache_directory = cache_directory or Path(
            os.environ.get(
                "RUMBO_CACHE_DIR",
                str(Path(tempfile.gettempdir()) / "rumbo-montevideo-api"),
            )
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
        self._pedestrian_cache: tuple[float, tuple[int, str, bytes]] | None = None
        self._pedestrian_lock = threading.Lock()
        self._pedestrian_retry_after = 0.0
        self._overpass_urls = tuple(
            dict.fromkeys((OVERPASS_URL, OVERPASS_MIRROR_URL))
        )

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
        if parsed.path == "/osm/pedestrian":
            status, content_type, body, cache_status = self._pedestrian()
            return status, content_type, body, {"X-Rumbo-Cache": cache_status}
        raise ApiError(404, "Ruta no habilitada en el proxy local.")

    def _pedestrian(self) -> tuple[int, str, bytes, str]:
        with self._pedestrian_lock:
            now = time.monotonic()
            cached = self._pedestrian_cache
            if cached is not None and now - cached[0] < PEDESTRIAN_CACHE_SECONDS:
                return (*cached[1], "memory")

            disk_cache = self._read_pedestrian_cache()
            stale = cached[1] if cached is not None else None
            if disk_cache is not None:
                stale = disk_cache[1]
            if disk_cache is not None:
                cache_age = time.time() - disk_cache[0]
                if cache_age < PEDESTRIAN_CACHE_SECONDS:
                    self._pedestrian_cache = (now, disk_cache[1])
                    return (*disk_cache[1], "disk")

            if now < self._pedestrian_retry_after and stale is not None:
                return (*stale, "stale")

            failures = []
            for endpoint in self._overpass_urls:
                try:
                    result = self._request_overpass(endpoint)
                except ApiError as error:
                    failures.append(f"{endpoint}: {error}")
                    continue
                self._write_pedestrian_cache(result[2])
                self._pedestrian_cache = (now, result)
                self._pedestrian_retry_after = 0.0
                return (*result, "miss")

            self._pedestrian_retry_after = now + 60
            if stale is not None:
                logging.warning(
                    "Overpass primario y mirror fallaron; sirviendo caché "
                    "peatonal obsoleta. Errores: %s",
                    "; ".join(failures),
                )
                self._pedestrian_cache = (
                    now - PEDESTRIAN_CACHE_SECONDS,
                    stale,
                )
                return (*stale, "stale")
            raise ApiError(
                502,
                "Fallaron Overpass y su mirror; no hay caché peatonal válida. "
                + "; ".join(failures),
            )

    def _read_pedestrian_cache(
        self,
    ) -> tuple[float, tuple[int, str, bytes]] | None:
        cache_path = self._cache_directory / "osm_pedestrian.json"
        try:
            stat = cache_path.stat()
            body = cache_path.read_bytes()
        except FileNotFoundError:
            return None
        except OSError as error:
            logging.warning("No se pudo leer la caché peatonal %s: %s", cache_path, error)
            return None
        if len(body) > MAX_PEDESTRIAN_BYTES:
            logging.warning("La caché peatonal excede el máximo permitido: %s", cache_path)
            return None
        try:
            payload = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            logging.warning("La caché peatonal está corrupta (%s): %s", cache_path, error)
            return None
        if not isinstance(payload, dict) or not isinstance(payload.get("elements"), list):
            logging.warning("La caché peatonal no tiene el formato esperado: %s", cache_path)
            return None
        return stat.st_mtime, (200, "application/json", body)

    def _write_pedestrian_cache(self, body: bytes) -> None:
        cache_path = self._cache_directory / "osm_pedestrian.json"
        temp_path: Path | None = None
        try:
            self._cache_directory.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(
                mode="wb",
                prefix="osm_pedestrian.",
                suffix=".tmp",
                dir=self._cache_directory,
                delete=False,
            ) as temp_file:
                temp_path = Path(temp_file.name)
                temp_file.write(body)
                temp_file.flush()
                os.fsync(temp_file.fileno())
            os.replace(temp_path, cache_path)
        except OSError as error:
            logging.warning("No se pudo persistir la caché peatonal: %s", error)
        finally:
            if temp_path is not None and temp_path.exists():
                try:
                    temp_path.unlink()
                except OSError as error:
                    logging.warning("No se pudo limpiar temporal %s: %s", temp_path, error)

    def _request_overpass(self, endpoint: str) -> tuple[int, str, bytes]:
        request = urllib.request.Request(
            endpoint,
            data=OVERPASS_QUERY.encode("utf-8"),
            headers={
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": RUMBO_USER_AGENT,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read(MAX_PEDESTRIAN_BYTES + 1)
                if len(body) > MAX_PEDESTRIAN_BYTES:
                    raise ApiError(502, "Respuesta de la red peatonal demasiado grande.")
                payload = json.loads(body)
                if not isinstance(payload, dict) or not isinstance(
                    payload.get("elements"), list
                ):
                    raise ApiError(
                        502,
                        "Respuesta de Overpass sin una lista de elementos válida.",
                    )
                result = (
                    response.status,
                    "application/json",
                    body,
                )
        except urllib.error.HTTPError as error:
            raise ApiError(
                502,
                f"El servicio de la red peatonal respondió HTTP {error.code}.",
            ) from None
        except (urllib.error.URLError, TimeoutError):
            raise ApiError(502, "No se pudo conectar al servicio de la red peatonal.") from None
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise ApiError(502, f"Overpass devolvió JSON inválido: {error}") from None
        return result

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
        return search

    @staticmethod
    def _normalize_place_text(value: str) -> str:
        normalized = unicodedata.normalize("NFKD", value)
        normalized = "".join(
            character
            for character in normalized
            if not unicodedata.combining(character)
        )
        normalized = re.sub(r"[^a-zA-Z0-9\s]", " ", normalized).casefold()
        abbreviations = {
            "av": "avenida",
            "avda": "avenida",
            "bvar": "bulevar",
            "bvr": "bulevar",
            "bv": "bulevar",
            "gral": "general",
            "cno": "camino",
            "dr": "doctor",
            "sta": "santa",
            "sto": "santo",
            "pje": "pasaje",
            "pza": "plaza",
            "rbla": "rambla",
        }
        tokens = re.sub(r"\s+", " ", normalized).strip().split()
        return " ".join(abbreviations.get(token, token) for token in tokens)

    @classmethod
    def _street_matches(cls, candidate: str, requested: str) -> bool:
        candidate_tokens = cls._normalize_place_text(candidate).split()
        requested_tokens = cls._normalize_place_text(requested).split()
        if not candidate_tokens or not requested_tokens:
            return False

        prefixes = {
            "avenida",
            "calle",
            "camino",
            "bulevar",
            "rambla",
            "pasaje",
            "plaza",
            "general",
            "doctor",
            "ingeniero",
            "brigadier",
        }

        def variants(tokens: list[str]) -> list[list[str]]:
            result = [tokens]
            start = 0
            while start < len(tokens) and tokens[start] in prefixes:
                start += 1
                result.append(tokens[start:])
            return result

        def contains(haystack: list[str], needle: list[str]) -> bool:
            return any(
                haystack[start : start + len(needle)] == needle
                for start in range(len(haystack) - len(needle) + 1)
            )

        return any(
            contains(candidate_variant, requested_variant)
            or contains(requested_variant, candidate_variant)
            for candidate_variant in variants(candidate_tokens)
            for requested_variant in variants(requested_tokens)
        )

    @staticmethod
    def _address_query(search: str) -> tuple[str, int] | None:
        match = re.fullmatch(
            r"\s*(.+?)\s+(?:n\s*[º°o.]?\s*)?(\d{1,5})"
            r"(?:\s*(?:bis|b|a))?\s*",
            search,
            flags=re.IGNORECASE,
        )
        if match is None:
            return None
        street = match.group(1).strip()
        number = int(match.group(2))
        return (street, number) if street and number > 0 else None

    @staticmethod
    def _photon_house_number(
        value: str, requested: int
    ) -> str:
        if not value:
            return "missing"
        exact = re.fullmatch(
            r"\s*0*(\d+)(?:\s*(?:bis|b|a))?\s*",
            value,
            flags=re.IGNORECASE,
        )
        if exact is not None:
            return "exact" if int(exact.group(1)) == requested else "different"
        range_match = re.fullmatch(r"\s*(\d+)\s*[-–]\s*(\d+)\s*", value)
        if range_match is not None:
            start, end = map(int, range_match.groups())
            return (
                "approximate"
                if min(start, end) <= requested <= max(start, end)
                else "different"
            )
        numbers = [int(number) for number in re.findall(r"\d+", value)]
        if requested in numbers:
            return "approximate"
        return "different" if numbers else "missing"

    @staticmethod
    def _photon_names(properties: dict[str, object]) -> list[str]:
        aliases: list[str] = []
        for key in (
            "alt_name",
            "official_name",
            "short_name",
            "int_name",
            "name:es",
            "name:en",
            "brand",
        ):
            value = properties.get(key)
            if isinstance(value, str):
                aliases.extend(re.split(r"[;,|]", value))
            elif isinstance(value, list):
                aliases.extend(item for item in value if isinstance(item, str))
        return list(dict.fromkeys(alias.strip() for alias in aliases if alias.strip()))

    @staticmethod
    def _photon_osm_id(properties: dict[str, object]) -> str | None:
        osm_id = properties.get("osm_id")
        osm_type = str(properties.get("osm_type") or "").strip().lower()
        if osm_id is None:
            return None
        normalized_type = {
            "n": "node",
            "w": "way",
            "r": "relation",
        }.get(osm_type, osm_type)
        if not normalized_type:
            return None
        return f"osm:{normalized_type}:{osm_id}"

    @classmethod
    def _photon_feature_score(
        cls,
        *,
        query: str,
        title: str,
        aliases: list[str],
        kind: str,
        precision: str,
        city: str,
        latitude: float,
        longitude: float,
    ) -> float:
        normalized_query = cls._normalize_place_text(query)
        normalized_names = [
            cls._normalize_place_text(name)
            for name in [title, *aliases]
            if name
        ]
        if normalized_query in normalized_names:
            text_score = 100
        elif any(normalized_query in name for name in normalized_names):
            text_score = 85
        else:
            query_tokens = normalized_query.split()
            best_coverage = max(
                (
                    sum(token in name.split() for token in query_tokens)
                    / max(1, len(query_tokens))
                    for name in normalized_names
                ),
                default=0,
            )
            text_score = best_coverage * 75
        kind_score = (
            100
            if kind in {"poi", "geographicArea", "neighborhood"}
            else 70
            if kind in {"address", "street"}
            else 40
        )
        precision_score = 100 if precision == "exactDoorNumber" else 60
        locality_score = 100 if "montevideo" in city.casefold() else 70
        distance = math.sqrt(
            (latitude - MONTEVIDEO_GEOCODING_BIAS[0]) ** 2
            + (longitude - MONTEVIDEO_GEOCODING_BIAS[1]) ** 2
        )
        locality_bias = max(0, 100 - distance * 1000)
        return (
            text_score * 0.68
            + kind_score * 0.20
            + precision_score * 0.08
            + locality_score * 0.03
            + locality_bias * 0.01
        )

    @classmethod
    def _photon_text_score(
        cls,
        query: str,
        names: list[str],
    ) -> float:
        normalized_query = cls._normalize_place_text(query)
        if not normalized_query:
            return 0
        normalized_names = [
            cls._normalize_place_text(name) for name in names if name
        ]
        if normalized_query in normalized_names:
            return 100
        if any(normalized_query in name for name in normalized_names):
            return 85
        query_tokens = normalized_query.split()
        return max(
            (
                75
                * sum(token in name.split() for token in query_tokens)
                / len(query_tokens)
                for name in normalized_names
            ),
            default=0,
        )

    @staticmethod
    def _is_unrequested_service(
        *,
        osm_key: str,
        osm_value: str,
        search: str,
    ) -> bool:
        normalized = ApiProxy._normalize_place_text(search)
        if osm_key == "amenity" and osm_value == "bicycle_rental":
            return not any(
                token in normalized
                for token in ("bicicleta", "bicicletas", "bici", "bicicletero", "alquiler")
            )
        if osm_key == "amenity" and osm_value == "parking":
            return not any(
                token in normalized
                for token in ("parking", "estacionamiento")
            )
        return False

    def _normalize_photon_response(self, body: bytes, search: str) -> bytes:
        try:
            payload = json.loads(body)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise ApiError(
                502,
                f"Photon devolvió JSON inválido: {error}",
            ) from None
        if not isinstance(payload, dict) or not isinstance(payload.get("features"), list):
            raise ApiError(
                502,
                "Photon devolvió GeoJSON malformado sin una lista de features.",
            )

        intersection = INTERSECTION_QUERY.match(search)
        address_query = self._address_query(search)
        west, south, east, north = URUGUAY_GEOCODING_BOUNDS
        normalized_results: list[tuple[float, dict[str, object]]] = []
        seen_osm_ids: set[str] = set()
        seen_fallback: list[tuple[str, str, float, float]] = []

        for index, feature in enumerate(payload["features"]):
            if not isinstance(feature, dict):
                continue
            geometry = feature.get("geometry")
            properties = feature.get("properties")
            if not isinstance(geometry, dict) or not isinstance(properties, dict):
                continue
            coordinates = geometry.get("coordinates")
            if not isinstance(coordinates, list) or len(coordinates) < 2:
                continue
            try:
                longitude = float(coordinates[0])
                latitude = float(coordinates[1])
            except (TypeError, ValueError):
                continue
            if not (
                -90 <= latitude <= 90
                and -180 <= longitude <= 180
                and west <= longitude <= east
                and south <= latitude <= north
            ):
                continue
            countrycode = str(properties.get("countrycode") or "").casefold()
            if countrycode and countrycode != "uy":
                continue

            name = str(properties.get("name") or "").strip()
            official_name = str(properties.get("official_name") or "").strip()
            street = str(properties.get("street") or "").strip()
            house_number = str(properties.get("housenumber") or "").strip()
            osm_key = str(properties.get("osm_key") or "").strip().casefold()
            osm_value = str(properties.get("osm_value") or "").strip().casefold()
            aliases = self._photon_names(properties)
            if name and official_name and name.casefold() != official_name.casefold():
                aliases.append(name)
            title_name = official_name or name
            if (
                self._normalize_place_text(search) == "sodre"
                and self._normalize_place_text(title_name)
                == "auditorio nacional adela reta"
            ):
                aliases.append("SODRE")
            category = f"{osm_key}:{osm_value}".strip(":")
            query_catalog = next(
                (
                    record
                    for canonical, record in MONTEVIDEO_POI_CATALOG.items()
                    if (
                        self._normalize_place_text(search)
                        in {
                            canonical,
                            *[
                                self._normalize_place_text(alias)
                                for alias in record["aliases"]
                            ],
                        }
                        or self._normalize_place_text(title_name)
                        in {
                            canonical,
                            *[
                                self._normalize_place_text(alias)
                                for alias in record["aliases"]
                            ],
                        }
                    )
                ),
                None,
            )
            if query_catalog is not None:
                aliases.extend(query_catalog["aliases"])
                if not official_name:
                    official_name = title_name
                is_sodre_auditorio = (
                    self._normalize_place_text(search) == "sodre"
                    and category in {"amenity:theatre", "amenity:auditorium"}
                    and self._normalize_place_text(title_name)
                    in {"sodre", "auditorio nacional adela reta"}
                )
                if is_sodre_auditorio:
                    if self._normalize_place_text(title_name) == "sodre":
                        official_name = "Auditorio Nacional Adela Reta"
                        title_name = official_name
                    elif not official_name:
                        official_name = title_name
                elif (
                    query_catalog["official_name"]
                    and self._normalize_place_text(title_name)
                    in {
                        self._normalize_place_text(query_catalog["official_name"]),
                        *[
                            self._normalize_place_text(alias)
                            for alias in query_catalog["aliases"]
                        ],
                    }
                ):
                    official_name = query_catalog["official_name"]
                    title_name = official_name
            neighborhood = next(
                (
                    str(properties.get(key)).strip()
                    for key in ("district", "suburb", "neighbourhood", "quarter")
                    if properties.get(key)
                ),
                "",
            )
            city = str(
                properties.get("city")
                or properties.get("locality")
                or properties.get("state")
                or ""
            ).strip()
            address_fields = {
                key: value
                for key, value in {
                    "street": street,
                    "house_number": house_number,
                    "neighborhood": neighborhood,
                    "city": city,
                    "country": properties.get("country"),
                }.items()
                if value
            }

            if intersection:
                street1 = intersection.group(1).strip()
                street2 = intersection.group(2).strip()
                candidate_text = " ".join(
                    [name, official_name, street, *aliases]
                )
                explicit_crossing = (
                    (osm_key == "highway" and osm_value in {"crossing", "junction"})
                    or osm_key == "junction"
                    or any(separator in name for separator in ("&", " / "))
                )
                if (
                    not explicit_crossing
                    or not self._street_matches(candidate_text, street1)
                    or not self._street_matches(candidate_text, street2)
                ):
                    continue
                title = search.strip()
                kind = "intersection"
                precision = "intersectionPoint"
                text_for_score = f"{street1} {street2}"
            elif address_query is not None:
                requested_street, door_number = address_query
                candidate_street = street or name
                if (
                    osm_value in {"crossing", "junction"}
                    or not self._street_matches(candidate_street, requested_street)
                ):
                    continue
                number_match = self._photon_house_number(
                    house_number,
                    door_number,
                )
                if number_match == "different":
                    continue
                if not street and osm_key not in {"highway", "road"}:
                    continue
                precision = (
                    "exactDoorNumber"
                    if number_match == "exact"
                    else "unconfirmedDoorNumber"
                )
                kind = "address"
                title = (
                    f"{candidate_street} {door_number}"
                    if number_match == "exact"
                    else search.strip()
                )
                text_for_score = requested_street
            elif osm_key == "highway" or osm_value in {
                "residential",
                "primary",
                "secondary",
                "tertiary",
            }:
                title = street or name
                if not title:
                    continue
                kind = "address"
                precision = "streetSegment"
                text_for_score = title
            else:
                if self._is_unrequested_service(
                    osm_key=osm_key,
                    osm_value=osm_value,
                    search=search,
                ):
                    continue
                title = title_name
                if not title:
                    continue
                kind = self._photon_kind(osm_key, osm_value)
                if self._photon_text_score(search, [title, *aliases]) < 50:
                    continue
                query_kind = classify_place_query(search)
                if query_kind == "geographic_area":
                    kind = "geographicArea"
                    precision = "approximateArea"
                elif query_kind == "neighborhood":
                    kind = "neighborhood"
                    precision = "approximateArea"
                elif query_kind == "street":
                    kind = "street"
                    precision = "streetSegment"
                else:
                    precision = {
                        "poi": "rooftopPoi",
                        "neighborhood": "approximateArea",
                    }.get(kind, "streetSegment")
                text_for_score = search

            if intersection:
                title_name = title

            location_parts: list[str] = []
            if kind == "poi" and street:
                location_parts.append(
                    " ".join(part for part in (street, house_number) if part)
                )
            for value in (neighborhood, city):
                if value and value not in location_parts:
                    location_parts.append(value)
            if not location_parts:
                country = str(properties.get("country") or "").strip()
                if country:
                    location_parts.append(country)
            subtitle = " · ".join(location_parts)

            external_id = self._photon_osm_id(properties)
            if external_id and external_id in seen_osm_ids:
                continue
            normalized_title = self._normalize_place_text(title)
            normalized_category = category or kind
            if not external_id and any(
                old_title == normalized_title
                and old_category == normalized_category
                and math.hypot(
                    longitude - old_longitude,
                    latitude - old_latitude,
                )
                <= 0.0002
                for old_title, old_category, old_latitude, old_longitude in seen_fallback
            ):
                continue
            if external_id:
                seen_osm_ids.add(external_id)
            else:
                seen_fallback.append(
                    (normalized_title, normalized_category, latitude, longitude)
                )

            score = self._photon_feature_score(
                query=text_for_score,
                title=title_name,
                aliases=aliases,
                kind=kind,
                precision=precision,
                city=city,
                latitude=latitude,
                longitude=longitude,
            )
            normalized_results.append(
                (
                    score,
                    {
                        "id": external_id or f"photon:{index}:{latitude}_{longitude}",
                        "externalId": external_id,
                        "kind": kind,
                        "title": title,
                        "name": name or None,
                        "officialName": official_name or None,
                        "subtitle": subtitle,
                        "address": address_fields,
                        "street": street or None,
                        "houseNumber": house_number or None,
                        "lat": latitude,
                        "lon": longitude,
                        "precision": precision,
                        "source": "openStreetMap",
                        "category": category or None,
                        "neighborhood": neighborhood or None,
                        "aliases": list(dict.fromkeys(aliases)),
                    },
                )
            )
        normalized_results.sort(key=lambda result: result[0], reverse=True)
        return json.dumps(
            [result for _, result in normalized_results[:5]],
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")

    @staticmethod
    def _photon_kind(osm_key: str, osm_value: str) -> str:
        if osm_key in {"highway", "road"}:
            return "address"
        if osm_key == "boundary" and osm_value in {
            "neighborhood",
            "neighbourhood",
            "suburb",
            "quarter",
        }:
            return "neighborhood"
        if osm_key in {"place"}:
            if osm_value in {"suburb", "neighbourhood", "quarter"}:
                return "neighborhood"
            return "poi"
        if osm_key in {"shop", "tourism", "amenity", "leisure", "building"}:
            return "poi"
        return "poi"

    def _search_places(self, search: str) -> tuple[int, str, bytes]:
        cache_key = geocoding_query(search).casefold()
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
            upstream_search = geocoding_query(search)
            provider_hostname = urllib.parse.urlsplit(PLACE_SEARCH_URL).hostname or ""
            is_photon = "photon" in provider_hostname.lower()
            if is_photon:
                west, south, east, north = URUGUAY_GEOCODING_BOUNDS
                bias_lat, bias_lon = MONTEVIDEO_GEOCODING_BIAS
                params = urllib.parse.urlencode(
                    {
                        "q": upstream_search,
                        "limit": "5",
                        "bbox": f"{west},{south},{east},{north}",
                        "lat": bias_lat,
                        "lon": bias_lon,
                        "zoom": "10",
                    }
                )
            else:
                params = urllib.parse.urlencode(
                    {
                        "q": upstream_search,
                        "countrycodes": "uy",
                        "format": "jsonv2",
                        "addressdetails": "1",
                        "limit": "5",
                        "viewbox": MONTEVIDEO_GEOCODING_VIEWBOX,
                        "bounded": "1",
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
                if cached is not None:
                    return cached[1]
                raise ApiError(
                    502,
                    f"El servicio de lugares respondió HTTP {error.code}.",
                ) from None
            except (urllib.error.URLError, TimeoutError):
                if cached is not None:
                    return cached[1]
                raise ApiError(502, "No se pudo conectar al servicio de lugares.") from None
            try:
                if is_photon:
                    result = (
                        response.status,
                        "application/json",
                        self._normalize_photon_response(body, search),
                    )
                else:
                    payload = json.loads(body)
                    if not isinstance(payload, list):
                        raise ApiError(
                            502,
                            "El proveedor devolvió una respuesta geográfica inválida.",
                        )
                    result = (
                        response.status,
                        "application/json",
                        body,
                    )
            except (json.JSONDecodeError, UnicodeDecodeError) as error:
                if cached is not None:
                    return cached[1]
                raise ApiError(
                    502,
                    f"El proveedor de lugares devolvió JSON inválido: {error}",
                ) from None
            except ApiError:
                if cached is not None:
                    return cached[1]
                raise
            self._place_responses[cache_key] = (time.monotonic(), result)
            return result

    def _live_request(self, api_path: str) -> tuple[int, str, bytes]:
        now = time.monotonic()
        with self._lock:
            if (
                api_path == self._last_live_path
                and self._last_live_response is not None
                and now - self._last_live_request < LIVE_STALE_SECONDS
                and now - self._last_live_request >= self._minimum_live_interval
            ):
                threading.Thread(
                    target=self._refresh_live,
                    args=(api_path,),
                    daemon=True,
                ).start()
                return self._last_live_response
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

    def _refresh_live(self, api_path: str) -> None:
        with self._lock:
            if api_path != self._last_live_path:
                return
            if time.monotonic() - self._last_live_request < self._minimum_live_interval:
                return
            self._last_live_request = time.monotonic()
        try:
            result = self._upstream(api_path)
        except ApiError:
            return
        with self._lock:
            self._last_live_response = result

    def _upstream(self, api_path: str) -> tuple[int, str, bytes]:
        return self._request_upstream(api_path, max_bytes=10 * 1024 * 1024)

    def _cached_reference(self, api_path: str) -> tuple[int, str, bytes]:
        now = time.monotonic()
        with self._lock:
            cached = self._reference_responses.get(api_path)
            if cached is not None and now - cached[0] < REFERENCE_DATA_CACHE_SECONDS:
                return cached[1]
            try:
                result = self._request_upstream(api_path, max_bytes=10 * 1024 * 1024)
            except ApiError:
                if cached is not None:
                    return cached[1]
                raise
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

        try:
            token = self._oauth.access_token()
        except ApiError:
            if archive_path.exists():
                return 200, "application/zip", archive_path.read_bytes()
            raise
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
            if archive_path.exists():
                return 200, "application/zip", archive_path.read_bytes()
            raise ApiError(
                502, f"La descarga GTFS respondió HTTP {error.code}."
            ) from None
        except (urllib.error.URLError, TimeoutError):
            if archive_path.exists():
                return 200, "application/zip", archive_path.read_bytes()
            raise ApiError(502, "No se pudo descargar el feed GTFS.") from None
        if len(body) > MAX_GTFS_BYTES:
            if archive_path.exists():
                return 200, "application/zip", archive_path.read_bytes()
            raise ApiError(502, "El ZIP GTFS supera el límite local de 100 MiB.")
        try:
            with zipfile.ZipFile(io.BytesIO(body)) as archive:
                required = {"stops.txt", "routes.txt", "trips.txt", "stop_times.txt"}
                if not required.issubset(set(archive.namelist())):
                    raise ApiError(502, "El ZIP GTFS no contiene los archivos requeridos.")
        except zipfile.BadZipFile:
            if archive_path.exists():
                return 200, "application/zip", archive_path.read_bytes()
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
        if len(lines) > 1 or (
            lines and not re.fullmatch(r"[A-Za-z0-9 ,-]{1,80}", lines[0])
        ):
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
        if len(lines) != 1 or not re.fullmatch(r"[A-Za-z0-9 ,-]{1,80}", lines[0]):
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
    if credentials.get("CLIENT_ID") and credentials.get("CLIENT_SECRET"):
        threading.Thread(
            target=Handler.proxy._live_request,
            args=("/buses?format=geojson",),
            daemon=True,
        ).start()
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
