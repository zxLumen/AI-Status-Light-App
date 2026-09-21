"""State and mode model shared by the host bridge, the firmware and the web page.

The canonical data lives in states.json (single source of truth). The constants
below are loaded from it at import time, with inlined defaults as a fallback.
"""

import json
import os

CONTRACT = "ai-status-light/states"
CONTRACT_VERSION = 1

_DEFAULTS = {
    "modes": [
        "off", "idle", "thinking", "working", "busy", "success", "error",
        "blocked", "alarm", "demo", "traffic", "red", "yellow", "green",
    ],
    "event_states": [
        "idle", "thinking", "working", "busy", "success", "error", "blocked",
    ],
    "event_to_mode": {
        "idle": "idle", "thinking": "thinking", "working": "working",
        "busy": "busy", "success": "success", "error": "error",
        "blocked": "blocked",
    },
    "priority": {
        "blocked": 60, "error": 50, "success": 40, "busy": 30,
        "working": 20, "thinking": 15, "idle": 0,
    },
    "default_ttl": {
        "blocked": 300.0, "error": 60.0, "success": 25.0,
        "busy": 90.0, "working": 90.0, "thinking": 90.0, "idle": 15.0,
    },
    "agents": ["claude", "cursor", "codex", "opencode", "manual"],
}


def _load():
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "states.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if data.get("contract") != CONTRACT:
            return _DEFAULTS
        return data
    except (OSError, ValueError):
        return _DEFAULTS


data = _load()

MODES = data["modes"]
EVENT_STATES = data["event_states"]
EVENT_TO_MODE = data["event_to_mode"]
PRIORITY = data["priority"]
DEFAULT_TTL = data["default_ttl"]
DISPLAY = data.get("display", {})
AGENTS = data["agents"]

PERSISTENT = set()


def normalize_state(value):
    if not value:
        return None
    v = str(value).strip().lower()
    aliases = {
        "done": "success",
        "complete": "success",
        "completed": "success",
        "finished": "success",
        "fail": "error",
        "failed": "error",
        "failure": "error",
        "waiting": "blocked",
        "needs_input": "blocked",
        "needs-input": "blocked",
        "permission": "blocked",
        "notification": "blocked",
        "run": "working",
        "running": "working",
        "active": "working",
        "start": "working",
        "prompt": "working",
        "tool": "busy",
        "pre_tool": "busy",
        "pretooluse": "busy",
        "clear": "idle",
        "stop": "success",
        "stopped": "success",
    }
    if v in EVENT_STATES:
        return v
    return aliases.get(v)


def mode_for_state(state):
    return EVENT_TO_MODE.get(state, "idle")