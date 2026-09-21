"""Session state store. Hooks write tiny JSON files here; the daemon reads them."""

import json
import os
import time
from datetime import datetime, timezone


def home_dir():
    d = os.environ.get("AISTATUS_HOME") or os.environ.get("AI_STATUS_HOME")
    if d:
        return os.path.expanduser(d)
    return os.path.expanduser("~/.ai-status-light")


def sessions_dir():
    return os.path.join(home_dir(), "sessions")


def ensure_dirs():
    os.makedirs(sessions_dir(), exist_ok=True)


def _safe(name):
    return "".join(c if c.isalnum() or c in "-_." else "_" for c in str(name))[:120]


def _path(session_id):
    return os.path.join(sessions_dir(), _safe(session_id) + ".json")


def now_ts():
    return time.time()


def iso(ts):
    return datetime.fromtimestamp(ts, tz=timezone.utc).astimezone().isoformat(timespec="seconds")


def write_event(session_id, agent, state, message=None, ts=None, seq=None):
    ensure_dirs()
    path = _path(session_id)
    # Ignore out-of-order writes: concurrent hook processes may finish in the
    # wrong order (e.g. a stale "busy" landing after "idle").
    if seq is not None and os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as f:
                existing = json.load(f)
            old = existing.get("seq")
            if isinstance(old, (int, float)) and seq < old:
                return existing
        except (OSError, ValueError):
            pass
    ts = ts or now_ts()
    record = {
        "session_id": str(session_id),
        "agent": agent,
        "state": state,
        "message": message,
        "ts": ts,
        "at": iso(ts),
        "seq": seq,
    }
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False)
    os.replace(tmp, path)
    return record


def read_sessions(max_age=None):
    ensure_dirs()
    names = session_names()
    dirs = session_dirs()
    out = []
    cutoff = None if max_age is None else now_ts() - max_age
    for name in os.listdir(sessions_dir()):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(sessions_dir(), name), encoding="utf-8") as f:
                rec = json.load(f)
        except (OSError, ValueError):
            continue
        if cutoff is not None and rec.get("ts", 0) < cutoff:
            continue
        rec["name"] = names.get(str(rec.get("session_id")))
        rec["dir"] = dirs.get(str(rec.get("session_id")))
        out.append(rec)
    return out


def names_path():
    return os.path.join(home_dir(), "names.json")


def session_names():
    path = names_path()
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def set_session_name(session_id, name):
    if not name:
        return
    ensure_dirs()
    data = session_names()
    if data.get(str(session_id)) == str(name):
        return
    data[str(session_id)] = str(name)
    with open(names_path(), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def dirs_path():
    return os.path.join(home_dir(), "dirs.json")


def session_dirs():
    path = dirs_path()
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def set_session_dir(session_id, directory):
    if not directory:
        return
    ensure_dirs()
    data = session_dirs()
    if data.get(str(session_id)) == str(directory):
        return
    data[str(session_id)] = str(directory)
    with open(dirs_path(), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)


def touch(session_id, ts=None):
    """Refresh a session's timestamp without changing its state (heartbeat)."""
    path = _path(session_id)
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return None
    ts = ts or now_ts()
    rec["ts"] = ts
    rec["at"] = iso(ts)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(rec, f, ensure_ascii=False)
    os.replace(tmp, path)
    return rec


def clear(session_id=None):
    ensure_dirs()
    if session_id is None:
        for name in os.listdir(sessions_dir()):
            if name.endswith(".json") or name.endswith(".tmp"):
                try:
                    os.remove(os.path.join(sessions_dir(), name))
                except OSError:
                    pass
        try:
            os.remove(names_path())
        except OSError:
            pass
        try:
            os.remove(dirs_path())
        except OSError:
            pass
        return
    base = _path(session_id)
    for name in os.listdir(sessions_dir()):
        if name == os.path.basename(base) or name.startswith(os.path.basename(base) + ".") and name.endswith(".tmp"):
            try:
                os.remove(os.path.join(sessions_dir(), name))
            except OSError:
                pass
    data = session_names()
    if data.pop(str(session_id), None) is not None:
        with open(names_path(), "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    ddata = session_dirs()
    if ddata.pop(str(session_id), None) is not None:
        with open(dirs_path(), "w", encoding="utf-8") as f:
            json.dump(ddata, f, ensure_ascii=False)


def override_path():
    return os.path.join(home_dir(), "override.json")


def set_override(mode, ttl=None):
    ensure_dirs()
    rec = {"mode": mode, "ts": now_ts(), "ttl": ttl}
    with open(override_path(), "w", encoding="utf-8") as f:
        json.dump(rec, f)
    return rec


def get_override():
    path = override_path()
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
    except (OSError, ValueError):
        return None
    ttl = rec.get("ttl")
    if ttl and now_ts() - rec.get("ts", 0) > ttl:
        clear_override()
        return None
    return rec.get("mode")


def clear_override():
    try:
        os.remove(override_path())
    except OSError:
        pass

