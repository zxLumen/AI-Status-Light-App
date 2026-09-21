"""Aggregate many session states into one global light mode."""

import time

from . import states


def _ttl(state):
    return states.DEFAULT_TTL.get(state, 60.0)


def is_fresh(rec, now=None):
    now = now or time.time()
    state = rec.get("state")
    if state in states.PERSISTENT:
        return True
    return (now - rec.get("ts", 0)) <= _ttl(state)


def aggregate(records, now=None, overrides=None):
    now = now or time.time()
    overrides = overrides or {}
    manual = overrides.get("mode")
    if manual:
        return {
            "mode": manual,
            "state": manual,
            "reason": "manual override",
            "sessions": [],
            "manual": True,
        }

    live = [r for r in records if is_fresh(r, now) and not r.get("ack")]
    if not live:
        return {"mode": "idle", "state": "idle", "reason": "no active sessions", "sessions": []}

    best = max(live, key=lambda r: states.PRIORITY.get(r.get("state"), -1))
    state = best.get("state", "idle")
    mode = states.mode_for_state(state)
    label = best.get("name") or best.get("agent") or "?"
    reason = f"{label} -> {state}"
    return {"mode": mode, "state": state, "reason": reason, "sessions": live}
