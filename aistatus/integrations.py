"""Install/uninstall AI agent hooks that report state to the store."""

import json
import os
import shutil
import sys

from . import store

CLAUDE_HOOK_EVENTS = [
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "Notification",
    "Stop",
    "SubagentStop",
    "SessionEnd",
]

CURSOR_HOOK_EVENTS = [
    "beforeSubmitPrompt",
    "afterAgentThought",
    "afterAgentResponse",
    "beforeShellExecution",
    "afterShellExecution",
    "beforeMCPExecution",
    "afterFileEdit",
    "stop",
]

# Events the opencode plugin forwards to the store (kept in sync with the
# event hook in opencode_plugin.js). Semantic mapping lives in
# opencode_state(). Names follow opencode 1.18 (v1); "permission.asked" is
# kept for forward-compat with v2.
OPENCODE_EVENTS = [
    "session.created",
    "session.updated",
    "session.status",
    "session.idle",
    "session.error",
    "permission.updated",
    "permission.asked",
    "permission.replied",
    "tool.execute.before",
    "message.part.updated",
]

ACTIVE_STATES = ("working", "busy", "thinking")

EVENT_STATE = {
    "userpromptsubmit": "working",
    "pretooluse": "busy",
    "posttooluse": "working",
    "notification": "blocked",
    "stop": "success",
    "subagentstop": "success",
    "sessionend": "idle",
    "precompact": "thinking",
    "beforesubmitprompt": "working",
    "afteragentthought": "thinking",
    "afteragentresponse": "working",
    "beforeshellexecution": "busy",
    "aftershellexecution": "working",
    "beforemcpexecution": "busy",
    "afterfileedit": "working",
    "beforereadfile": "thinking",
}


def state_for_event(event):
    if not event:
        return None
    return EVENT_STATE.get(str(event).replace("_", "").replace("-", "").lower())


def _recent_activity(session_id, window=90):
    """True if this session was active (or just finished) within the window.

    opencode emits both `session.status: idle` and `session.idle` for the same
    turn; without treating a recent `success` as activity, the second event
    would downgrade the just-written success back to idle.
    """
    now = store.now_ts()
    best = None
    for rec in store.read_sessions():
        if rec.get("session_id") != str(session_id):
            continue
        ts = rec.get("ts", 0)
        if best is None or ts > best[0]:
            best = (ts, rec.get("state"))
    if not best:
        return False
    ts, state = best
    return now - ts <= window and state in (*ACTIVE_STATES, "success")


def _status_text(status):
    """Normalize an opencode session.status value.

    The value is a SessionStatus object like {"type": "busy"} in opencode
    1.18; accept it as-is (dict/full object) and extract its discriminator.
    """
    if isinstance(status, dict):
        for key in ("type", "status"):
            v = status.get(key)
            if isinstance(v, str):
                return v
        return str(status)
    return str(status or "")


def opencode_state(event_type, status, session_id, idle_window=90):
    """Map an opencode event to an aistatus state.

    opencode only distinguishes session busy/idle, so 'idle' is resolved to
    success when that session was actively working moments ago (a finished
    turn) and to idle otherwise (a fresh or dormant session).
    """
    et = str(event_type or "").lower()
    if et == "session.status":
        s = _status_text(status).lower()
        if s in ("busy", "retry"):
            return "working"
        if s == "idle":
            return "success" if _recent_activity(session_id, idle_window) else "idle"
        return None
    if et == "session.idle":
        return "success" if _recent_activity(session_id, idle_window) else "idle"
    if et == "session.error":
        return "error"
    if et in ("permission.updated", "permission.asked", "question.asked"):
        return "blocked"
    if et in ("permission.replied", "question.replied"):
        return "working"
    if et == "tool.execute.before":
        return "busy"
    return None


def opencode_state_for_payload(event_type, status, session_id, payload):
    """opencode_state() plus a content-based fallback.

    Some events (notably message.part.updated carrying the `question` tool) may
    arrive with an unexpected event name; detect the waiting-on-user case from
    the payload itself so it still maps to blocked.
    """
    state = opencode_state(event_type, status, session_id)
    if state:
        return state
    props = payload.get("properties") or {}
    part = props.get("part") if isinstance(props, dict) else None
    if isinstance(part, dict) and part.get("tool") == "question":
        s = (part.get("state") or {}).get("status")
        if s == "running":
            return "blocked"
        if s in ("completed", "error"):
            return "working"
    return None


def hook_command():
    return f'{sys.executable} -m aistatus hook'


def claude_settings_path():
    return os.path.expanduser("~/.claude/settings.json")


def cursor_hooks_path():
    return os.path.expanduser("~/.cursor/hooks.json")


def codex_config_path():
    return os.path.expanduser("~/.codex/config.toml")


def opencode_plugin_path():
    # opencode only auto-loads {plugin,plugins}/*.{ts,js} — .mjs is NOT matched.
    return os.path.expanduser("~/.config/opencode/plugins/aistatus.js")


def opencode_plugin_legacy_paths():
    return [os.path.expanduser("~/.config/opencode/plugins/aistatus.mjs")]


def opencode_plugin_text():
    here = os.path.dirname(os.path.abspath(__file__))
    with open(os.path.join(here, "opencode_plugin.js"), encoding="utf-8") as f:
        text = f.read()
    return (text
            .replace("__PY__", json.dumps(sys.executable))
            .replace("__AI_STATUS_HOME__", json.dumps(store.home_dir()))
            .replace("__EVENTS__", json.dumps(OPENCODE_EVENTS)))


def _backup(path):
    if os.path.exists(path):
        shutil.copy2(path, path + ".aistatus.bak")
        return path + ".aistatus.bak"
    return None


def _load_json(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _save_json(path, data, dry_run):
    text = json.dumps(data, ensure_ascii=False, indent=2)
    if dry_run:
        print(f"--- would write {path} ---")
        print(text)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    b = _backup(path)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    if b:
        print(f"backed up -> {b}")
    print(f"wrote {path}")


def install_claude(dry_run=False):
    path = claude_settings_path()
    data = _load_json(path)
    hooks = data.setdefault("hooks", {})
    cmd = hook_command()
    for event in CLAUDE_HOOK_EVENTS:
        entry = {"hooks": [{"type": "command", "command": cmd}]}
        if event in ("PreToolUse", "PostToolUse"):
            entry["matcher"] = "*"
        hooks[event] = [entry]
    _save_json(path, data, dry_run)


def install_cursor(dry_run=False):
    path = cursor_hooks_path()
    data = _load_json(path)
    data["version"] = data.get("version", 1)
    hooks = data.setdefault("hooks", {})
    cmd = hook_command()
    for event in CURSOR_HOOK_EVENTS:
        hooks[event] = [{"command": cmd}]
    _save_json(path, data, dry_run)


def install_codex(dry_run=False):
    path = codex_config_path()
    cmd = f'{sys.executable} -m aistatus hook --agent codex'
    line = f'notify = [{json.dumps(sys.executable)}, "-m", "aistatus", "hook", "--agent", "codex"]'
    existing = ""
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            existing = f.read()
    if "aistatus" in existing:
        print(f"{path} already contains an aistatus notify entry")
        return
    if dry_run:
        print(f"--- would append to {path} ---")
        print(line)
        print(f"# (or run manually when a turn completes): {cmd}")
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    b = _backup(path)
    with open(path, "a", encoding="utf-8") as f:
        if existing and not existing.endswith("\n"):
            f.write("\n")
        f.write(line + "\n")
    if b:
        print(f"backed up -> {b}")
    print(f"appended notify to {path}")


def _agent_wired(agent):
    try:
        if agent == "claude":
            data = _load_json(claude_settings_path())
            hooks = data.get("hooks") or {}
            return any("aistatus" in json.dumps(h)
                       for e in hooks.values() for h in (e if isinstance(e, list) else [e]))
        if agent == "cursor":
            data = _load_json(cursor_hooks_path())
            hooks = data.get("hooks") or {}
            return any("aistatus" in json.dumps(h)
                       for e in hooks.values() for h in (e if isinstance(e, list) else [e]))
        if agent == "codex":
            if not os.path.exists(codex_config_path()):
                return False
            with open(codex_config_path(), encoding="utf-8") as f:
                return "aistatus" in f.read()
        if agent == "opencode":
            return os.path.exists(opencode_plugin_path())
    except OSError:
        return False
    return False


def hooks_status(agents=None):
    return {a: _agent_wired(a) for a in agents or ("claude", "cursor", "codex", "opencode")}


def install_opencode(dry_run=False):
    path = opencode_plugin_path()
    text = opencode_plugin_text()
    if dry_run:
        print(f"--- would write {path} ---")
        print(text)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    for legacy in opencode_plugin_legacy_paths():
        if os.path.exists(legacy):
            os.remove(legacy)
            print(f"removed legacy {legacy}")
    if os.path.exists(path):
        shutil.copy2(path, path + ".aistatus.bak")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {path}")
    print("note: restart opencode to activate the plugin")


def uninstall(dry_run=False):
    for path, keys in ((claude_settings_path(), list(CLAUDE_HOOK_EVENTS)),
                       (cursor_hooks_path(), list(CURSOR_HOOK_EVENTS))):
        if not os.path.exists(path):
            continue
        data = _load_json(path)
        hooks = data.get("hooks") or {}
        removed = False
        for event in keys:
            if event in hooks:
                hooks.pop(event, None)
                removed = True
        if removed:
            _save_json(path, data, dry_run)
    cfg = codex_config_path()
    if os.path.exists(cfg):
        with open(cfg, encoding="utf-8") as f:
            lines = f.readlines()
        kept = [ln for ln in lines if "aistatus" not in ln]
        if len(kept) != len(lines):
            if dry_run:
                print(f"--- would remove aistatus notify from {cfg} ---")
            else:
                _backup(cfg)
                with open(cfg, "w", encoding="utf-8") as f:
                    f.writelines(kept)
                print(f"cleaned {cfg}")
    for plug in [opencode_plugin_path(), *opencode_plugin_legacy_paths()]:
        if os.path.exists(plug):
            if dry_run:
                print(f"--- would remove {plug} ---")
            else:
                _backup(plug)
                os.remove(plug)
                print(f"removed {plug}")
