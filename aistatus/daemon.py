"""Background watch daemon: aggregates session state and drives a transport."""

import threading
import time

from . import aggregate, store, transport


class WatchRunner:
    """Runs the same watch loop as `aistatus watch`, but in a daemon thread and
    with a small status snapshot the web control panel can inspect."""

    def __init__(self, transport_kind="null", port=None, interval=0.4, max_age=3600):
        self.transport_kind = transport_kind
        self.port = port
        self.interval = interval
        self.max_age = max_age
        self._stop = threading.Event()
        self._thread = None
        self.status = {
            "running": False,
            "transport": None,
            "last_mode": None,
            "last_ts": None,
            "error": None,
            "sessions": 0,
        }

    @property
    def running(self):
        return bool(self._thread and self._thread.is_alive())

    def start(self):
        if self.running:
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def stop(self, timeout=2.0):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout)

    def _run(self):
        try:
            tr = transport.build(self.transport_kind, port=self.port)
        except Exception as e:  # noqa: BLE001
            self.status.update({"running": False, "error": f"build failed: {e}"})
            return
        self.status.update({"running": True, "transport": tr.status(),
                            "error": None})
        last = None
        try:
            while not self._stop.is_set():
                records = store.read_sessions(max_age=self.max_age)
                result = aggregate.aggregate(records,
                                             overrides={"mode": store.get_override()})
                self.status["sessions"] = len(records)
                mode = result["mode"]
                if mode != last:
                    try:
                        tr.send(mode)
                        last = mode
                        self.status.update({
                            "last_mode": mode,
                            "last_ts": store.now_ts(),
                            "error": None,
                        })
                    except Exception as e:  # noqa: BLE001
                        self.status["error"] = str(e)
                self._stop.wait(self.interval)
        finally:
            try:
                tr.close()
            except Exception:  # noqa: BLE001
                pass
            self.status.update({"running": False})

    def snapshot(self):
        st = dict(self.status)
        st["running"] = self.running
        st["override"] = store.get_override()
        return st