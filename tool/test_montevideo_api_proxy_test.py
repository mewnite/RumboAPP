import json
import tempfile
import time
import unittest
import urllib.error
import urllib.parse
import os
from pathlib import Path
from unittest.mock import patch

from tool.montevideo_api_proxy import (
    LIVE_STALE_SECONDS,
    MONTEVIDEO_GEOCODING_VIEWBOX,
    ApiError,
    ApiProxy,
    Handler,
    load_env,
)
from tool.montevideo_api_proxy import geocoding_query
from tool.fetch_seeds.fetch_seeds import feature_collection_to_overpass


class ApiProxyTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.proxy = ApiProxy({}, Path(self.directory.name), minimum_live_interval=10)

    def tearDown(self):
        self.directory.cleanup()

    def test_health_route_does_not_require_credentials(self):
        self.assertEqual(
            self.proxy.handle("/health"),
            (200, "application/json", b'{"status":"ok"}', {}),
        )

    def test_browser_cors_allows_only_loopback_origins(self):
        handler = object.__new__(Handler)
        handler.headers = {"Origin": "http://localhost:54321"}
        self.assertEqual(
            handler._local_cors_headers()["Access-Control-Allow-Origin"],
            "http://localhost:54321",
        )
        handler.headers = {"Origin": "http://127.0.0.1:8123"}
        self.assertEqual(
            handler._local_cors_headers()["Access-Control-Allow-Origin"],
            "http://127.0.0.1:8123",
        )
        for origin in (
            "https://localhost:54321",
            "http://localhost.evil.test",
            "https://example.com",
        ):
            handler.headers = {"Origin": origin}
            self.assertEqual(handler._local_cors_headers(), {})

    def test_place_search_is_validated_cached_and_identifies_rumbo(self):
        payload = (200, "application/json", b'[]')
        response = type(
            "Response",
            (),
            {
                "status": 200,
                "headers": {"Content-Type": "application/json"},
                "read": lambda self, limit: payload[2],
                "__enter__": lambda self: self,
                "__exit__": lambda self, *args: None,
            },
        )()
        with patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            return_value=response,
        ) as upstream:
            first = self.proxy.handle("/geocode?q=Nuevo%20Centro")
            second = self.proxy.handle("/geocode?q=nuevo%20centro")
        self.assertEqual(first, (*payload, {}))
        self.assertEqual(second, first)
        upstream.assert_called_once()
        request = upstream.call_args.args[0]
        self.assertIn("countrycodes=uy", request.full_url)
        self.assertIn("addressdetails=1", request.full_url)
        self.assertIn("bounded=1", request.full_url)
        self.assertIn(
            "viewbox=" + urllib.parse.quote(MONTEVIDEO_GEOCODING_VIEWBOX),
            request.full_url,
        )
        self.assertEqual(request.get_header("User-agent"), "RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)")

    def test_place_search_accepts_app_parameters_and_rejects_unknown_ones(self):
        payload = (200, "application/json", b"[]")
        with patch.object(
            self.proxy, "_search_places", return_value=payload
        ) as search:
            self.assertEqual(
                self.proxy.handle(
                    "/geocode?q=Centro&countrycodes=uy&format=jsonv2"
                    "&limit=5"
                ),
                (*payload, {}),
            )
            search.assert_called_once_with("Centro")
        for path in (
            "/geocode?q=Centro&viewbox=1",
            "/geocode?q=Centro&format=json",
            "/geocode?q=Centro&bias_lat=-34.9&bias_lon=-56.2",
            "/geocode?q=UY",
        ):
            with self.assertRaises(ApiError) as context:
                self.proxy.handle(path)
            self.assertEqual(context.exception.status, 400)

    def test_place_query_adds_montevideo_context_and_normalizes_crossings(self):
        self.assertEqual(
            geocoding_query("Shopping Punta Carretas"),
            "Shopping Punta Carretas, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("faramiñán n° 801"),
            "faraminan 801, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("shopping nuevocentro"),
            "shopping Nuevo Centro, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("Av. Italia y Gral. Flores"),
            "avenida Italia & general Flores, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("Faramiñán x Santa Lucía"),
            "Faraminan & Santa Lucia, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("18 de Julio y Ejido en Montevideo"),
            "18 de Julio & Ejido en Montevideo",
        )
        self.assertEqual(
            geocoding_query("Av. Italia 2450, Uruguay"),
            "avenida Italia 2450, Uruguay",
        )

    def test_geo_request_validates_bounds_and_normalizes_query(self):
        result = (200, "application/json", b"[]")
        with patch.object(self.proxy, "_live_request", return_value=result) as request:
            self.assertEqual(
                self.proxy.handle(
                    "/api/buses/geo?center=-34.9,-56.2&radius=500"
                ),
                (*result, {}),
            )
            request.assert_called_once_with(
                "/buses/geo?center=-34.9%2C-56.2&radius=500.0"
            )

    def test_live_request_caches_same_query_and_limits_other_queries(self):
        result = (200, "application/json", b"[]")
        with patch.object(self.proxy, "_upstream", return_value=result) as upstream:
            self.assertEqual(
                self.proxy._live_request("/buses/geo?center=-34.9%2C-56.2&radius=500"),
                result,
            )
            self.assertEqual(
                self.proxy._live_request("/buses/geo?center=-34.9%2C-56.2&radius=500"),
                result,
            )
            upstream.assert_called_once()
            with self.assertRaises(ApiError) as context:
                self.proxy._live_request("/buses?lines=522&format=json")
            self.assertEqual(context.exception.status, 429)

    def test_live_cache_refreshes_after_fifteen_seconds(self):
        path = "/buses/busstops/3628/upcomingbuses?lines=163"
        self.proxy._last_live_path = path
        self.proxy._last_live_response = (200, "application/json", b"[]")
        self.proxy._last_live_request = (
            time.monotonic() - LIVE_STALE_SECONDS - 1
        )
        fresh = (200, "application/json", b'[{"eta":30}]')
        with patch.object(self.proxy, "_upstream", return_value=fresh) as upstream:
            self.assertEqual(self.proxy._live_request(path), fresh)
        upstream.assert_called_once_with(path)

    def test_line_variants_are_cached_reference_data_not_live_polling(self):
        payload = (200, "application/json", b"[]")
        with patch.object(
            self.proxy, "_request_upstream", return_value=payload
        ) as upstream:
            first = self.proxy.handle("/api/linevariants")
            second = self.proxy.handle("/api/linevariants")
        self.assertEqual(first, (*payload, {}))
        self.assertEqual(second, first)
        upstream.assert_called_once_with(
            "/buses/linevariants", max_bytes=10 * 1024 * 1024
        )

    def test_geo_validation_rejects_out_of_range_values(self):
        with self.assertRaises(ApiError) as context:
            self.proxy._validate_geo("center=95,-56&radius=500")
        self.assertEqual(context.exception.status, 400)
        self.assertEqual(
            self.proxy._validate_geo("center=-34.9,-56.2&radius=500"),
            "center=-34.9%2C-56.2&radius=500.0",
        )

    def test_bus_filters_are_bounded(self):
        self.assertEqual(
            self.proxy._validate_bus_query(""),
            "format=geojson",
        )
        self.assertEqual(
            self.proxy._validate_upcoming_query("lines=522&amountperline=2"),
            "lines=522&amountperline=2&format=json",
        )
        self.assertEqual(
            self.proxy._validate_upcoming_query("lines=124+Sd&amountperline=1"),
            "lines=124+Sd&amountperline=1&format=json",
        )
        self.assertEqual(
            self.proxy._validate_bus_query("lines=124+Sd"),
            "format=geojson&lines=124+Sd",
        )
        with self.assertRaises(ApiError):
            self.proxy._validate_upcoming_query("lines=522&amountperline=99")
        with self.assertRaises(ApiError):
            self.proxy._validate_bus_query("lines=522&admin=true")
        with self.assertRaises(ApiError):
            self.proxy._validate_bus_query("format=json")

    def test_load_env_reads_only_key_value_pairs(self):
        path = Path(self.directory.name) / ".env"
        path.write_text(
            '# local credentials\nCLIENT_ID = "app-id"\nCLIENT_SECRET=secret\n',
            encoding="utf-8",
        )
        self.assertEqual(
            load_env(path),
            {"CLIENT_ID": "app-id", "CLIENT_SECRET": "secret"},
        )

    def test_place_search_returns_stale_cache_when_provider_fails(self):
        stale = (200, "application/json", b'[{"display_name":"Centro"}]')
        self.proxy._place_responses["centro"] = (
            time.monotonic() - 48 * 60 * 60,
            stale,
        )
        with patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            side_effect=urllib.error.URLError("offline"),
        ):
            self.assertEqual(self.proxy._search_places("Centro"), stale)

    def test_reference_data_returns_stale_cache_when_upstream_fails(self):
        stale = (200, "application/json", b"[]")
        self.proxy._reference_responses["/buses/busstops"] = (
            time.monotonic() - 48 * 60 * 60,
            stale,
        )
        with patch.object(
            self.proxy,
            "_request_upstream",
            side_effect=ApiError(502, "offline"),
        ):
            self.assertEqual(
                self.proxy._cached_reference("/buses/busstops"),
                stale,
            )

    def test_pedestrian_source_uses_mirror_and_persists_response(self):
        body = b'{"elements":[]}'
        self.proxy._overpass_urls = ("https://primary.test/api", "https://mirror.test/api")
        with patch.object(
            self.proxy,
            "_request_overpass",
            side_effect=[ApiError(502, "primary unavailable"), (200, "application/json", body)],
        ) as request:
            response = self.proxy.handle("/osm/pedestrian")
        self.assertEqual(response, (200, "application/json", body, {"X-Rumbo-Cache": "miss"}))
        self.assertEqual(
            [call.args[0] for call in request.call_args_list],
            ["https://primary.test/api", "https://mirror.test/api"],
        )
        self.assertEqual(
            (Path(self.directory.name) / "osm_pedestrian.json").read_bytes(),
            body,
        )

        restarted = ApiProxy({}, Path(self.directory.name))
        with patch.object(restarted, "_request_overpass") as request:
            cached = restarted.handle("/osm/pedestrian")
        self.assertEqual(cached, (200, "application/json", body, {"X-Rumbo-Cache": "disk"}))
        request.assert_not_called()

    def test_pedestrian_source_serves_stale_disk_cache_if_all_upstreams_fail(self):
        cache_path = Path(self.directory.name) / "osm_pedestrian.json"
        cache_path.write_text('{"elements":[]}', encoding="utf-8")
        old = time.time() - 2 * 24 * 60 * 60
        os.utime(cache_path, (old, old))
        self.proxy._overpass_urls = ("https://primary.test/api", "https://mirror.test/api")
        with patch.object(
            self.proxy,
            "_request_overpass",
            side_effect=ApiError(502, "unavailable"),
        ) as request:
            response = self.proxy.handle("/osm/pedestrian")
        self.assertEqual(
            response,
            (200, "application/json", b'{"elements":[]}', {"X-Rumbo-Cache": "stale"}),
        )
        self.assertEqual(request.call_count, 2)

    def test_pedestrian_filter_does_not_confuse_motor_vehicle_with_foot_access(self):
        from tool.montevideo_api_proxy import OVERPASS_QUERY

        self.assertNotIn("motor_vehicle", OVERPASS_QUERY)
        self.assertNotIn('["access"!="agricultural"]', OVERPASS_QUERY)
        self.assertIn('["access"!="private"]', OVERPASS_QUERY)
        self.assertIn('["foot"="yes"]', OVERPASS_QUERY)

    def test_osmium_geojson_adapter_clips_complete_ways_to_montevideo_bbox(self):
        source = Path("test/fixtures/osm_seed_minimal.geojson")
        destination = Path(self.directory.name) / "normalized.json"
        exported, clipped = feature_collection_to_overpass(
            source,
            destination,
            {"west": -1, "south": -1, "east": 1, "north": 1},
        )
        elements = json.loads(destination.read_text(encoding="utf-8"))["elements"]
        self.assertEqual(exported, 2)
        self.assertEqual(clipped, 1)
        self.assertEqual(
            elements[0]["geometry"],
            [{"lat": 0.25, "lon": -1.0}, {"lat": 0.5, "lon": 0}, {"lat": 0.75, "lon": 1}],
        )

    def test_gtfs_returns_last_valid_archive_when_upstream_is_offline(self):
        archive = Path(self.directory.name) / "google_transit.zip"
        archive.write_bytes(b"last-valid-feed")
        stale_time = time.time() - 48 * 60 * 60
        os.utime(archive, (stale_time, stale_time))
        with patch.object(
            self.proxy._oauth,
            "access_token",
            return_value="test-token",
        ), patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            side_effect=urllib.error.URLError("offline"),
        ):
            self.assertEqual(
                self.proxy._gtfs(),
                (200, "application/zip", b"last-valid-feed"),
            )


if __name__ == "__main__":
    unittest.main()
