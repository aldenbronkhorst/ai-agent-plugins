from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts" / "odoo_json2.py"


class RecordingHandler(BaseHTTPRequestHandler):
    records = []
    redirect_target = ""

    def do_GET(self) -> None:
        self.__class__.records.append({"method": "GET", "authorization": self.headers.get("Authorization")})
        self.send_response(200)
        self.end_headers()

    def do_POST(self) -> None:
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        self.__class__.records.append(
            {
                "path": self.path,
                "authorization": self.headers.get("Authorization"),
                "database": self.headers.get("X-Odoo-Database"),
                "content_type": self.headers.get("Content-Type"),
                "body": body,
            }
        )
        if "/redirect_" in self.path:
            code = int(self.path.rsplit("_", 1)[1])
            self.send_response(code)
            self.send_header("Location", self.redirect_target)
            self.end_headers()
            return
        if self.path.endswith("/create_then_disconnect"):
            self.close_connection = True
            return
        if self.path.endswith("/forced_error"):
            response = b'{"message":"expected failure"}'
            self.send_response(422)
        else:
            response = json.dumps({"path": self.path, "accepted": True}).encode()
            self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, _format: str, *_args: object) -> None:
        return


class OdooJson2TransparencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), RecordingHandler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls) -> None:
        cls.server.shutdown()
        cls.thread.join()
        cls.server.server_close()

    def setUp(self) -> None:
        RecordingHandler.records.clear()

    def direct_request(self, model: str, method: str, body: str) -> bytes:
        request = urllib.request.Request(
            f"{self.base_url}/json/2/{model}/{method}",
            data=body.encode(),
            headers={
                "Authorization": "bearer test-api-key",
                "Content-Type": "application/json; charset=utf-8",
                "X-Odoo-Database": "test-database",
            },
            method="POST",
        )
        with urllib.request.urlopen(request) as response:
            return response.read()

    def helper_request(self, model: str, method: str, body: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "ODOO_URL": self.base_url,
                "ODOO_API_KEY": "test-api-key",
                "ODOO_DATABASE": "test-database",
            }
        )
        return subprocess.run(
            [sys.executable, str(SCRIPT), model, method, "--body", body],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def test_helper_preserves_arbitrary_json2_requests(self) -> None:
        cases = [
            ("res.users", "context_get", "{}"),
            (
                "account.move",
                "search_read",
                json.dumps(
                    {
                        "domain": [["payment_state", "=", "not_paid"]],
                        "fields": ["name", "amount_residual"],
                        "limit": 25,
                        "context": {"allowed_company_ids": [1, 2]},
                    }
                ),
            ),
            (
                "x_custom.model",
                "write",
                json.dumps({"ids": [7], "values": {"x_payload": {"any": [1, 2, 3]}}}),
            ),
        ]
        for model, method, body in cases:
            with self.subTest(model=model, method=method):
                RecordingHandler.records.clear()
                direct_output = self.direct_request(model, method, body)
                direct_record = RecordingHandler.records[-1]
                helper = self.helper_request(model, method, body)
                helper_record = RecordingHandler.records[-1]

                self.assertEqual(helper.returncode, 0, helper.stderr)
                self.assertEqual(json.loads(helper.stdout), json.loads(direct_output))
                self.assertEqual(helper_record, direct_record)

    def test_helper_preserves_odoo_error_body(self) -> None:
        helper = self.helper_request("x_custom.model", "forced_error", "{}")
        self.assertEqual(helper.returncode, 1)
        self.assertEqual(json.loads(helper.stdout), {"message": "expected failure"})
        self.assertIn("HTTP 422", helper.stderr)

    def test_authenticated_redirects_are_never_followed(self) -> None:
        class DestinationHandler(RecordingHandler):
            records = []

        destination = ThreadingHTTPServer(("127.0.0.1", 0), DestinationHandler)
        thread = threading.Thread(target=destination.serve_forever, daemon=True)
        thread.start()
        try:
            for target in (
                f"http://127.0.0.1:{destination.server_port}/elsewhere",
                f"{self.base_url}/same-origin",
            ):
                RecordingHandler.redirect_target = target
                for code in (301, 302, 303, 307, 308):
                    with self.subTest(target=target, code=code):
                        RecordingHandler.records.clear()
                        DestinationHandler.records.clear()
                        helper = self.helper_request("x_custom.model", f"redirect_{code}", "{}")
                        self.assertEqual(helper.returncode, 1)
                        self.assertIn("redirect refused", helper.stderr)
                        self.assertEqual(len(RecordingHandler.records), 1)
                        self.assertEqual(DestinationHandler.records, [])
                        self.assertNotIn("test-api-key", helper.stdout + helper.stderr)
        finally:
            destination.shutdown()
            thread.join()
            destination.server_close()

    def test_uncertain_write_is_not_replayed(self) -> None:
        helper = self.helper_request("x_custom.model", "create_then_disconnect", '{"values":{"name":"test"}}')
        self.assertEqual(helper.returncode, 1)
        self.assertEqual(len(RecordingHandler.records), 1)
        self.assertNotIn("test-api-key", helper.stdout + helper.stderr)


if __name__ == "__main__":
    unittest.main()
