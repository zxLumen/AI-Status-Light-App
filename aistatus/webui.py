"""Local web control panel (lightd).

Serves the control page at http://127.0.0.1:8377 and a small JSON API that
exposes the computer-side functions as web operations: agent hook install,
watch start/stop, aggregated state, device list, manual events.
"""

import json
import os
import posixpath
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from . import aggregate, integrations, protocol, states, store, transport
from .daemon import WatchRunner

PAGE = "control.html"
FALLBACK_PAGE = "config.html"


def package_states_path():
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "states.json")


class ControlServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, addr, handler, webdir):
        self.webdir = webdir
        self.runner = WatchRunner()
        super().__init__(addr, handler)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server: ControlServer

    # ---------------- helpers ----------------
    def log_message(self, fmt, *args):  # quiet default
        pass

    def _send(self, code, ctype, body):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _text(self, code, text):
        self._send(code, "text/plain; charset=utf-8", text)

    def _json(self, code, obj):
        self._send(code, "application/json; charset=utf-8",
                   json.dumps(obj, ensure_ascii=False))

    def _err(self, code, msg):
        self._json(code, {"ok": False, "error": msg})

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0:
            return {}
        try:
            return json.loads(self.rfile.read(length) or b"{}")
        except (ValueError, OSError):
            return {}

    def _file(self, path, ctype):
        try:
            with open(path, "rb") as f:
                data = f.read()
        except OSError:
            return False
        self._send(200, ctype, data)
        return True

    def _resolve_web(self, rel):
        if ".." in rel or rel.startswith("/"):
            return None
        return os.path.join(self.server.webdir, rel)

    # ---------------- static ----------------
    def _static(self, path):
        path = posixpath.normpath(path or "/")
        if path in ("/", "/control.html"):
            return self._file(os.path.join(self.server.webdir, PAGE),
                              "text/html; charset=utf-8")
        if path == "/config.html":
            return self._file(os.path.join(self.server.webdir, FALLBACK_PAGE),
                              "text/html; charset=utf-8")
        if path == "/states.json":
            local = os.path.join(self.server.webdir, "states.json")
            return self._file(local if os.path.exists(local) else package_states_path(),
                              "application/json; charset=utf-8")
        rel = path.lstrip("/")
        if rel.startswith("web/"):
            rel = rel[4:]
        fpath = self._resolve_web(rel)
        if fpath and os.path.isfile(fpath):
            return self._file(fpath, "application/octet-stream")
        return None

    # ---------------- API ----------------
    def _api_state(self):
        records = store.read_sessions(max_age=3600)
        result = aggregate.aggregate(records, overrides={"mode": store.get_override()})
        self._json(200, {"ok": True, "override": store.get_override(),
                         "state": result, "records": records[-50:]})

    def _api_devices(self):
        ports = transport.list_serial_ports()
        try:
            import bleak  # noqa: F401
            ble = f"bleak available; scans for '{protocol.BLE_NAME}'"
        except ImportError:
            ble = "bleak not installed (pip install bleak)"
        self._json(200, {"ok": True, "ports": ports, "ble": ble})

    def _api_hooks(self):
        self._json(200, {"ok": True, "agents": integrations.hooks_status()})

    def _api_watch(self):
        self._json(200, {"ok": True, "watch": self.server.runner.snapshot()})

    def _api_event(self, body):
        state = states.normalize_state(body.get("state"))
        if not state:
            return self._err(400, "unknown state: " + str(body.get("state")))
        store.write_event(
            body.get("session") or body.get("agent") or "web",
            body.get("agent") or "web",
            state,
            message=body.get("message"))
        return self._json(200, {"ok": True, "recorded": state})

    def _api_light(self, body):
        if body.get("off"):
            store.clear_override()
            return self._json(200, {"ok": True, "override": None})
        mode = body.get("mode")
        if mode not in states.MODES:
            return self._err(400, "unknown mode: " + str(mode))
        store.set_override(mode, ttl=body.get("ttl"))
        return self._json(200, {"ok": True, "override": mode})

    def _api_clear(self, body):
        store.clear(body.get("session"))
        if not body.get("session"):
            store.clear_override()
        return self._json(200, {"ok": True})

    def _api_hooks_install(self, body):
        agents = body.get("agents") or list(integrations.hooks_status())
        fn = {
            "claude": integrations.install_claude,
            "cursor": integrations.install_cursor,
            "codex": integrations.install_codex,
            "opencode": integrations.install_opencode,
        }
        done, errors = [], []
        for a in agents:
            try:
                fn[a](dry_run=False)
                done.append(a)
            except KeyError:
                errors.append(f"{a}: unknown agent")
            except Exception as e:  # noqa: BLE001
                errors.append(f"{a}: {e}")
        return self._json(200, {"ok": True, "installed": done, "errors": errors,
                                "agents": integrations.hooks_status()})

    def _api_hooks_uninstall(self, body):
        integrations.uninstall(dry_run=False)
        return self._json(200, {"ok": True, "agents": integrations.hooks_status()})

    def _api_watch_start(self, body):
        kind = body.get("transport") or "null"
        if kind not in ("null", "serial", "ble"):
            return self._err(400, "transport must be null|serial|ble")
        runner = self.server.runner
        if runner.running:
            runner.stop()
        runner = WatchRunner(transport_kind=kind, port=body.get("port"))
        self.server.runner = runner
        runner.start()
        return self._json(200, {"ok": True, "watch": runner.snapshot()})

    def _api_watch_stop(self, body):
        self.server.runner.stop()
        return self._json(200, {"ok": True, "watch": self.server.runner.snapshot()})

    # ---------------- dispatch ----------------
    def _route(self, method):
        path, _, qs = self.path.partition("?")
        body = self._body() if method == "POST" else {}
        route = (method, path)
        if route == ("GET", "/api/state"):
            return self._api_state()
        if route == ("GET", "/api/devices"):
            return self._api_devices()
        if route == ("GET", "/api/hooks"):
            return self._api_hooks()
        if route == ("GET", "/api/watch"):
            return self._api_watch()
        if route == ("POST", "/api/event"):
            return self._api_event(body)
        if route == ("POST", "/api/light"):
            return self._api_light(body)
        if route == ("POST", "/api/clear"):
            return self._api_clear(body)
        if route == ("POST", "/api/hooks/install"):
            return self._api_hooks_install(body)
        if route == ("POST", "/api/hooks/uninstall"):
            return self._api_hooks_uninstall(body)
        if route == ("POST", "/api/watch/start"):
            return self._api_watch_start(body)
        if route == ("POST", "/api/watch/stop"):
            return self._api_watch_stop(body)
        if method == "GET" and not path.startswith("/api/"):
            if self._static(path):
                return
            self._err(404, "not found")
            return
        self._err(404, f"no route: {method} {path}")

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")


def default_webdir():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(here, "web")


def serve(host="127.0.0.1", port=8377, webdir=None, open_browser=False):
    webdir = webdir or default_webdir()
    if not os.path.exists(os.path.join(webdir, PAGE)):
        raise FileNotFoundError(f"missing {PAGE} in {webdir}")
    server = ControlServer((host, port), Handler, webdir)
    url = f"http://{host}:{port}"
    print(f"AI Status Light 控制面板 → {url}")
    print(f"页面: {webdir}")
    if open_browser:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopping...")
        server.runner.stop()
    finally:
        server.server_close()