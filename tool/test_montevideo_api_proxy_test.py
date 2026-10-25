import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool.montevideo_api_proxy import ApiError, ApiProxy, load_env


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
        self.assertEqual(request.get_header("User-agent"), "RumboAPP/1.0 (+https://github.com/mewnite/RumboAPP)")

    def test_place_search_accepts_app_parameters_and_rejects_unknown_ones(self):
        payload = (200, "application/json", b"[]")
        with patch.object(
            self.proxy, "_search_places", return_value=payload
        ) as search:
            self.assertEqual(
                self.proxy.handle(
                    "/geocode?q=Centro&countrycodes=uy&format=jsonv2"
                    "&limit=5&bias_lat=-34.9&bias_lon=-56.2"
                ),
                (*payload, {}),
            )
            search.assert_called_once_with("Centro")
        for path in (
            "/geocode?q=Centro&viewbox=1",
            "/geocode?q=Centro&format=json",
            "/geocode?q=Centro&bias_lat=-34.9",
            "/geocode?q=UY",
        ):
            with self.assertRaises(ApiError) as context:
                self.proxy.handle(path)
            self.assertEqual(context.exception.status, 400)

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


if __name__ == "__main__":
    unittest.main()
