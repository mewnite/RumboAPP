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
from tool.montevideo_api_proxy import classify_place_query, geocoding_query
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
        payload = (200, "application/json", b"[]")
        response = type(
            "Response",
            (),
            {
                "status": 200,
                "headers": {"Content-Type": "application/json"},
                "read": lambda self, limit: b'{"type":"FeatureCollection","features":[]}',
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
        self.assertIn("photon.komoot.io", request.full_url)
        self.assertIn("lat=-34.9037", request.full_url)
        self.assertIn("lon=-56.1882", request.full_url)
        self.assertIn(
            "bbox=" + urllib.parse.quote("-58.5,-35.2,-53.0,-30.0"),
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
            geocoding_query("SODRE"),
            "Auditorio Nacional Adela Reta, Montevideo, Uruguay",
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

    def test_place_catalog_resolves_known_aliases_without_coordinates(self):
        self.assertEqual(
            geocoding_query("Catedral Metropolitana de Montevideo"),
            "Catedral Metropolitana, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("Nuevo Centro Shopping"),
            "Nuevo Centro Shopping, Montevideo, Uruguay",
        )
        self.assertEqual(
            geocoding_query("Teatro Solís"),
            "Teatro Solís, Montevideo, Uruguay",
        )

    def test_place_query_classification_covers_geographic_intents(self):
        cases = {
            "Shopping Punta Carretas": "poi",
            "Avenida Italia": "street",
            "Rambla de Montevideo": "geographic_area",
            "Ciudad Vieja": "neighborhood",
            "18 de Julio y Ejido": "intersection",
            "Avenida Italia 2450": "address",
            "una consulta desconocida": "unknown",
        }
        for query, expected in cases.items():
            with self.subTest(query=query):
                self.assertEqual(classify_place_query(query), expected)

    def test_photon_normalizes_addresses_intersections_and_pois(self):
        fixture = Path("tool/test_fixtures/photon_montevideo.json").read_bytes()
        address = json.loads(
            self.proxy._normalize_photon_response(fixture, "18 de Julio 1234")
        )
        exact_address = next(item for item in address if item["kind"] == "address")
        self.assertEqual(exact_address["title"], "Avenida 18 de Julio 1234")
        self.assertEqual(exact_address["precision"], "exactDoorNumber")

        poi = json.loads(
            self.proxy._normalize_photon_response(fixture, "SODRE")
        )
        sodre = next(
            item
            for item in poi
            if item["title"] == "Auditorio Nacional Adela Reta"
        )
        self.assertEqual(sodre["kind"], "poi")
        self.assertEqual(sodre["source"], "openStreetMap")
        self.assertIn("SODRE", sodre["aliases"])

        intersection = json.loads(
            self.proxy._normalize_photon_response(
                fixture, "18 de Julio y Ejido"
            )
        )
        crossing = next(
            item for item in intersection
            if item["kind"] == "intersection"
        )
        self.assertEqual(crossing["title"], "18 de Julio y Ejido")
        self.assertEqual(crossing["precision"], "intersectionPoint")

    def test_photon_normalization_rejects_invalid_and_unconfirmed_results(self):
        with self.assertRaises(ApiError):
            self.proxy._normalize_photon_response(b"{bad", "SODRE")
        with self.assertRaises(ApiError):
            self.proxy._normalize_photon_response(b"[]", "SODRE")
        self.assertEqual(
            json.loads(
                self.proxy._normalize_photon_response(
                    b'{"type":"FeatureCollection","features":[{}]}',
                    "SODRE",
                )
            ),
            [],
        )

    def test_photon_normalization_validates_geojson_coordinates(self):
        feature = lambda coords, props: (
            '{"type":"FeatureCollection","features":[{'
            '"type":"Feature","geometry":{"type":"Point","coordinates":'
            + json.dumps(coords)
            + '},"properties":'
            + json.dumps(props)
            + '}]}'
        ).encode()

        for coords in ([200, -34.9], [-34.9, -56.2], [-60.0, -34.9],
                       [-56.2, -40.0]):
            results = json.loads(
                self.proxy._normalize_photon_response(
                    feature(coords, {"name": "Lugar"}),
                    "Lugar",
                )
            )
            self.assertEqual(results, [])

        no_name = feature([-56.2, -34.9], {"country": "Uruguay"})
        self.assertEqual(
            json.loads(
                self.proxy._normalize_photon_response(no_name, "Montevideo")
            ),
            [],
        )

        no_house = feature(
            [-56.2, -34.9],
            {"name": "Avenida Italia", "street": "Avenida Italia",
             "city": "Montevideo"},
        )
        results = json.loads(
            self.proxy._normalize_photon_response(no_house, "Avenida Italia 2450")
        )
        self.assertEqual(results[0]["precision"], "unconfirmedDoorNumber")
        self.assertEqual(results[0]["title"], "Avenida Italia 2450")

    def test_photon_normalization_matches_all_required_query_intents(self):
        fixture = Path("tool/test_fixtures/photon_montevideo.json").read_bytes()
        expectations = {
            "18 de Julio 1234": ("address", "exactDoorNumber"),
            "Avenida Italia 2450": ("address", "exactDoorNumber"),
            "Bulevar Artigas 1500": ("address", "exactDoorNumber"),
            "18 de Julio y Ejido": ("intersection", "intersectionPoint"),
            "Rivera esquina Soca": ("intersection", "intersectionPoint"),
            "Bulevar Artigas & Garibaldi": (
                "intersection",
                "intersectionPoint",
            ),
            "Palacio Legislativo": ("poi", "rooftopPoi"),
            "SODRE": ("poi", "rooftopPoi"),
            "Estadio Centenario": ("poi", "rooftopPoi"),
            "Terminal Tres Cruces": ("poi", "rooftopPoi"),
            "Parque Rodo": ("neighborhood", "approximateArea"),
        }

        for query, (expected_kind, expected_precision) in expectations.items():
            with self.subTest(query=query):
                results = json.loads(
                    self.proxy._normalize_photon_response(fixture, query)
                )
                self.assertTrue(results)
                self.assertEqual(results[0]["kind"], expected_kind)
                self.assertEqual(results[0]["precision"], expected_precision)

    def test_photon_normalization_preserves_poi_name_and_alternatives(self):
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [-56.1882, -34.9037],
            },
            "properties": {
                "osm_id": 9001,
                "osm_type": "R",
                "osm_key": "amenity",
                "osm_value": "theatre",
                "name": "Auditorio Nacional Adela Reta",
                "official_name": "Auditorio Nacional Adela Reta",
                "alt_name": "SODRE",
                "street": "Andes",
                "city": "Montevideo",
            },
        }
        response = json.dumps(
            {"type": "FeatureCollection", "features": [feature]}
        ).encode()

        result = json.loads(
            self.proxy._normalize_photon_response(response, "SODRE")
        )[0]

        self.assertEqual(result["title"], "Auditorio Nacional Adela Reta")
        self.assertIn("SODRE", result["aliases"])
        self.assertEqual(result["street"], "Andes")
        self.assertEqual(result["externalId"], "osm:relation:9001")
        self.assertEqual(result["subtitle"], "Andes · Montevideo")

    def test_photon_normalization_adds_known_sodre_alias(self):
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [-56.1987, -34.9042],
            },
            "properties": {
                "osm_id": 9002,
                "osm_type": "R",
                "osm_key": "amenity",
                "osm_value": "theatre",
                "name": 'Auditorio Nacional "Adela Reta"',
                "street": "Andes",
                "city": "Montevideo",
            },
        }
        response = json.dumps(
            {"type": "FeatureCollection", "features": [feature]}
        ).encode()

        result = json.loads(
            self.proxy._normalize_photon_response(response, "SODRE")
        )[0]

        self.assertEqual(result["title"], 'Auditorio Nacional "Adela Reta"')
        self.assertIn("SODRE", result["aliases"])

    def test_photon_normalization_classifies_neighborhood_boundary(self):
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [-56.1677, -34.9141],
            },
            "properties": {
                "osm_id": 9003,
                "osm_type": "R",
                "osm_key": "boundary",
                "osm_value": "neighborhood",
                "name": "Parque Rodó",
                "city": "Montevideo",
            },
        }
        response = json.dumps(
            {"type": "FeatureCollection", "features": [feature]}
        ).encode()

        result = json.loads(
            self.proxy._normalize_photon_response(response, "Parque Rodo")
        )[0]

        self.assertEqual(result["kind"], "neighborhood")
        self.assertEqual(result["precision"], "approximateArea")

    def test_photon_normalization_rejects_unrelated_or_unconfirmed_intersections(self):
        features = [
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [-56.1882, -34.9037],
                },
                "properties": {
                    "osm_id": 9010,
                    "osm_type": "N",
                    "osm_key": "highway",
                    "osm_value": "crossing",
                    "name": "Rivera & Soca",
                    "city": "Montevideo",
                },
            },
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [-56.1883, -34.9038],
                },
                "properties": {
                    "osm_id": 9010,
                    "osm_type": "N",
                    "osm_key": "highway",
                    "osm_value": "crossing",
                    "name": "Rivera & Soca",
                    "city": "Montevideo",
                },
            },
        ]
        response = json.dumps(
            {"type": "FeatureCollection", "features": features}
        ).encode()

        self.assertEqual(
            len(
                json.loads(
                    self.proxy._normalize_photon_response(
                        response,
                        "Rivera esquina Soca",
                    )
                )
            ),
            1,
        )
        self.assertEqual(
            json.loads(
                self.proxy._normalize_photon_response(
                    response,
                    "Rivera esquina Ejido",
                )
            ),
            [],
        )

    def test_photon_normalization_rejects_grouped_number_outside_range(self):
        feature = {
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [-56.1882, -34.9037],
            },
            "properties": {
                "osm_id": 9020,
                "osm_type": "W",
                "osm_key": "building",
                "osm_value": "residential",
                "name": "Avenida Italia",
                "street": "Avenida Italia",
                "housenumber": "2400, 2450, 2500",
                "city": "Montevideo",
            },
        }
        response = json.dumps(
            {"type": "FeatureCollection", "features": [feature]}
        ).encode()

        result = json.loads(
            self.proxy._normalize_photon_response(
                response,
                "Avenida Italia 2450",
            )
        )[0]
        self.assertEqual(result["precision"], "unconfirmedDoorNumber")
        self.assertEqual(result["title"], "Avenida Italia 2450")

    def test_photon_normalization_keeps_nearby_different_places(self):
        features = []
        for index, name, category, longitude_offset in (
            (9030, "Auditorio SODRE", "theatre", 0.0),
            (9031, "Café SODRE", "cafe", 0.00005),
        ):
            features.append(
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "Point",
                        "coordinates": [-56.1882 + longitude_offset, -34.9037],
                    },
                    "properties": {
                        "osm_id": index,
                        "osm_type": "N",
                        "osm_key": "amenity",
                        "osm_value": category,
                        "name": name,
                        "alt_name": "SODRE",
                        "city": "Montevideo",
                    },
                }
            )
        response = json.dumps(
            {"type": "FeatureCollection", "features": features}
        ).encode()

        results = json.loads(
            self.proxy._normalize_photon_response(response, "SODRE")
        )

        self.assertEqual(len(results), 2)
        self.assertNotEqual(results[0]["externalId"], results[1]["externalId"])

    def test_photon_request_uses_fixed_bias_and_uruguay_bbox(self):
        response = type(
            "Response",
            (),
            {
                "status": 200,
                "headers": {"Content-Type": "application/json"},
                "read": lambda self, limit: b'{"type":"FeatureCollection","features":[]}',
                "__enter__": lambda self: self,
                "__exit__": lambda self, *args: None,
            },
        )()
        with patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            return_value=response,
        ) as upstream:
            self.proxy.handle("/geocode?q=Estadio%20Centenario")
        request = upstream.call_args.args[0]
        query = urllib.parse.parse_qs(
            urllib.parse.urlsplit(request.full_url).query
        )
        self.assertEqual(query["lat"], ["-34.9037"])
        self.assertEqual(query["lon"], ["-56.1882"])
        self.assertEqual(query["bbox"], ["-58.5,-35.2,-53.0,-30.0"])
        self.assertIn("photon.komoot.io", request.full_url)

    def test_place_provider_timeout_http_error_and_large_response(self):
        with patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            side_effect=TimeoutError(),
        ):
            with self.assertRaises(ApiError) as context:
                self.proxy._search_places("SODRE")
            self.assertEqual(context.exception.status, 502)

        http_error = urllib.error.HTTPError(
            "https://photon.komoot.io/api/",
            503,
            "Unavailable",
            {},
            None,
        )
        with patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            side_effect=http_error,
        ):
            with self.assertRaises(ApiError) as context:
                self.proxy._search_places("Estadio Centenario")
            self.assertEqual(context.exception.status, 502)

        response = type(
            "Response",
            (),
            {
                "status": 200,
                "headers": {"Content-Type": "application/json"},
                "read": lambda self, limit: b"x" * (1024 * 1024 + 1),
                "__enter__": lambda self: self,
                "__exit__": lambda self, *args: None,
            },
        )()
        with patch(
            "tool.montevideo_api_proxy.urllib.request.urlopen",
            return_value=response,
        ):
            with self.assertRaises(ApiError) as context:
                self.proxy._search_places("Terminal Tres Cruces")
            self.assertIn("demasiado grande", context.exception.args[0])

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
        cache_key = geocoding_query("Centro").casefold()
        self.proxy._place_responses[cache_key] = (
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
