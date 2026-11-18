#!/usr/bin/env python3
"""Loopback-only dashboard server for the repository's fixed simulation targets."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit


ROOT = Path(__file__).resolve().parents[1]
FRONTEND = Path(__file__).resolve().parent
SIMULATION_LOCK = threading.Lock()
FAILURE_PATTERN = re.compile(r"\[FAIL\]|FAILED|FATAL ERROR", re.IGNORECASE)

SIMULATIONS = {
    "harvard": {
        "name": "Harvard memory",
        "target": "sim-harvard",
        "description": "Check instruction/data separation, byte enables, and concurrent access.",
        "waveform": "sim/harvard_mem.vcd",
    },
    "von-neumann": {
        "name": "Von Neumann baseline",
        "target": "sim-vn",
        "description": "Check the shared-memory arbiter and its structural stall behavior.",
        "waveform": "sim/von_neumann.vcd",
    },
    "comparison": {
        "name": "Harvard vs Von Neumann",
        "target": "sim-comparison",
        "description": "Run the array-sum workload and compare cycles, CPI, and memory results.",
        "waveform": "sim/comparison.vcd",
    },
    "core": {
        "name": "RV32I mini core",
        "target": "sim-core",
        "description": "Run the execution-core datapath testbench.",
        "waveform": "sim/mini_core.vcd",
    },
    "icache": {
        "name": "Instruction cache",
        "target": "sim-icache",
        "description": "Run the direct-mapped instruction-cache testbench.",
        "waveform": "sim/icache.vcd",
    },
    "unified-pipeline": {
        "name": "Unified pipeline",
        "target": "sim-unified-pipe",
        "description": "Run the shared-memory pipelined-core and telemetry testbench.",
        "waveform": "sim/unified_pipeline.vcd",
    },
    "harvard-pipeline": {
        "name": "Harvard pipeline",
        "target": "sim-pipeline-harvard",
        "description": "Run the Harvard pipeline hazard, forwarding, and concurrency suite.",
        "waveform": "sim/pipeline_harvard.vcd",
    },
}

STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/app.css": ("app.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
}


class DashboardHandler(BaseHTTPRequestHandler):
    server_version = "MemoryHierarchyDashboard/1.0"
    protocol_version = "HTTP/1.1"

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'self'; style-src 'self'; script-src 'self'; "
            "connect-src 'self'; img-src 'self' data:; base-uri 'none'; "
            "frame-ancestors 'none'",
        )
        self.send_header("Connection", "close")
        self.close_connection = True
        super().end_headers()

    def _send(self, status: int, content_type: str, body: bytes, headers=None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self._send(status, "application/json; charset=utf-8", body)

    def _simulation_list(self) -> list[dict]:
        return [
            {
                "id": simulation_id,
                "name": details["name"],
                "target": details["target"],
                "description": details["description"],
                "waveform_available": (ROOT / details["waveform"]).is_file(),
            }
            for simulation_id, details in SIMULATIONS.items()
        ]

    def do_GET(self) -> None:
        request = urlsplit(self.path)
        if request.path == "/api/simulations":
            self._send_json(200, {"simulations": self._simulation_list()})
            return

        if request.path == "/api/waveform":
            query = parse_qs(request.query)
            simulation_id = query.get("id", [""])[0]
            details = SIMULATIONS.get(simulation_id)
            if details is None:
                self._send_json(400, {"error": "Unknown simulation."})
                return

            waveform_path = ROOT / details["waveform"]
            if not waveform_path.is_file():
                self._send_json(404, {"error": "Run this simulation to generate its waveform."})
                return

            body = waveform_path.read_bytes()
            if len(body) > 5_000_000:
                self._send_json(413, {"error": "Waveform is larger than the dashboard limit."})
                return

            disposition = "attachment" if query.get("download") == ["1"] else "inline"
            self._send(
                200,
                "text/plain; charset=utf-8",
                body,
                {"Content-Disposition": f'{disposition}; filename="{waveform_path.name}"'},
            )
            return

        static_file = STATIC_FILES.get(request.path)
        if static_file is not None:
            file_name, content_type = static_file
            body = (FRONTEND / file_name).read_bytes()
            self._send(200, content_type, body)
            return

        self._send_json(404, {"error": "Not found."})

    def _valid_local_origin(self) -> bool:
        port = self.server.server_address[1]
        allowed = {f"localhost:{port}", f"127.0.0.1:{port}"}
        origin = self.headers.get("Origin", "")
        host = self.headers.get("Host", "")
        parsed_origin = urlsplit(origin)
        return (
            parsed_origin.scheme == "http"
            and parsed_origin.netloc in allowed
            and host in allowed
        )

    def do_POST(self) -> None:
        if urlsplit(self.path).path != "/api/run":
            self._send_json(404, {"error": "Not found."})
            return

        if not self._valid_local_origin():
            self._send_json(403, {"error": "Simulation requests must come from this local dashboard."})
            return

        try:
            content_length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self._send_json(400, {"error": "Invalid request length."})
            return
        if content_length <= 0 or content_length > 2048:
            self._send_json(400, {"error": "Invalid request size."})
            return

        try:
            payload = json.loads(self.rfile.read(content_length))
        except (json.JSONDecodeError, UnicodeDecodeError):
            self._send_json(400, {"error": "Request must contain valid JSON."})
            return

        simulation_id = payload.get("id") if isinstance(payload, dict) else None
        details = SIMULATIONS.get(simulation_id) if isinstance(simulation_id, str) else None
        if details is None:
            self._send_json(400, {"error": "Choose a listed simulation."})
            return

        if not SIMULATION_LOCK.acquire(blocking=False):
            self._send_json(409, {"error": "A simulation is already running. Please wait for it to finish."})
            return

        started = time.perf_counter()
        try:
            result = subprocess.run(
                ["make", details["target"]],
                cwd=ROOT,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=180,
                check=False,
            )
            output = result.stdout
            passed = result.returncode == 0 and FAILURE_PATTERN.search(output) is None
            self._send_json(
                200,
                {
                    "simulation": simulation_id,
                    "name": details["name"],
                    "target": details["target"],
                    "passed": passed,
                    "returncode": result.returncode,
                    "duration_seconds": round(time.perf_counter() - started, 2),
                    "output": output,
                    "waveform_available": (ROOT / details["waveform"]).is_file(),
                },
            )
        except subprocess.TimeoutExpired as error:
            partial = error.stdout or b""
            if isinstance(partial, bytes):
                partial = partial.decode("utf-8", errors="replace")
            self._send_json(
                504,
                {
                    "error": "Simulation exceeded the 180-second time limit.",
                    "output": partial,
                    "passed": False,
                },
            )
        except FileNotFoundError as error:
            self._send_json(500, {"error": f"Could not start make: {error}", "passed": False})
        finally:
            SIMULATION_LOCK.release()

    def log_message(self, format_string: str, *args) -> None:
        print(f"[dashboard] {self.address_string()} - {format_string % args}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the local memory hierarchy simulation dashboard.")
    parser.add_argument("--port", type=int, default=8765, help="Local port (default: 8765)")
    args = parser.parse_args()

    server = ThreadingHTTPServer(("127.0.0.1", args.port), DashboardHandler)
    server.daemon_threads = True
    print(f"Memory Hierarchy Dashboard: http://127.0.0.1:{server.server_address[1]}")
    print("Bound to 127.0.0.1 only. Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping dashboard.")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
