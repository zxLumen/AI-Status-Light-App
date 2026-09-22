"""Command line interface for the AI Status Light host bridge."""

import argparse
import json
import os
import sys
import time

from . import aggregate, integrations, protocol, render, states, store, transport


def _read_payload():
    if sys.stdin is None or sys.stdin.isatty():
        return {}
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    if not raw or not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except ValueError:
        return {"raw": raw.strip()}


def _first(payload, *keys):
    for k in keys:
        if payload.get(k) not in (None, ""):
            return payload[k]
    return None


def _resolve(args, payload):
    agent = args.agent or _first(payload, "agent") or "claude"
    event = args.event or _first(payload, "hook_event_name", "event", "type")
    session = (args.session
               or _first(payload, "session_id", "conversation_id", "thread_id", "id")
               or agent)
    message = args.message or _first(payload, "message", "prompt", "text")
    state = args.state or integrations.state_for_event(event)

    if not state and str(agent) == "codex":
        t = str(event or "").lower()
        if "complete" in t or "done" in t:
            state = "success"
        elif "start" in t or "begin" in t:
            state = "working"

    if not state and str(agent) == "opencode":
        props = payload.get("properties") or {}
        status = (_first(payload, "status", "session_status")
                  or props.get("status"))
        state = integrations.opencode_state_for_payload(event, status, session, payload)

    if not state and str(event).lower() == "notification":
        nt = str(_first(payload, "notification_type", "notificationType") or "").lower()
        if "idle" in nt:
            state = "success"
        elif nt:
            state = "blocked"
    if not state:
        state = states.normalize_state(event) or args.default_state
    return agent, session, state, message


def _session_name(payload, agent):
    name = _first(payload, "session_name", "session_title", "sessionName")
    if not name and str(agent) == "opencode":
        props = payload.get("properties") or {}
        info = props.get("info") or {}
        name = info.get("title") or props.get("title")
    if name and str(name).startswith("New session"):
        return None
    return name


def _session_dir(payload, agent):
    directory = _first(payload, "session_dir", "directory", "cwd")
    if not directory and str(agent) == "opencode":
        props = payload.get("properties") or {}
        info = props.get("info") or {}
        directory = info.get("directory") or props.get("directory")
    return directory


def cmd_hook(args):
    payload = _read_payload()
    if str(payload.get("event") or "").lower() == "heartbeat":
        sid = _first(payload, "session_id", "sessionId", "conversation_id", "thread_id", "id")
        if sid:
            store.touch(sid)
        return 0
    agent, session, state, message = _resolve(args, payload)
    name = _session_name(payload, agent)
    if name:
        store.set_session_name(session, name)
    directory = _session_dir(payload, agent)
    if directory:
        store.set_session_dir(session, directory)
    host = _first(payload, "session_host", "host")
    ref = _first(payload, "session_ref", "ref")
    if host or ref:
        store.set_session_host(session, host, ref)
    if args.verbose:
        print(f"hook agent={agent} session={session} state={state} name={name}", file=sys.stderr)
    if not state:
        print("hook: no state mapped, skipping", file=sys.stderr)
        return 0
    store.write_event(session, agent, state, message=message, seq=payload.get("seq"))
    if args.direct:
        transport.build(args.transport, port=args.port, name=args.ble_name).send(
            states.mode_for_state(state))
    return 0


def cmd_event(args):
    state = states.normalize_state(args.state)
    if not state:
        print(f"unknown state: {args.state}", file=sys.stderr)
        return 2
    store.write_event(args.session or args.agent, args.agent, state, message=args.message)
    if args.direct:
        transport.build(args.transport, port=args.port, name=args.ble_name).send(
            states.mode_for_state(state))
        return 0
    print(f"recorded {args.agent}/{args.session or args.agent} -> {state}")
    return 0


def cmd_light(args):
    if args.off:
        store.clear_override()
    else:
        store.set_override(args.mode, ttl=args.ttl)
    tr = transport.build(args.transport, port=args.port, name=args.ble_name, verbose=args.verbose)
    tr.send("idle" if args.off else args.mode)
    tr.close()
    print(f"mode -> {args.mode}" + ("" if not args.ttl else f" (ttl {args.ttl}s)"))
    return 0


def cmd_state(args):
    records = store.read_sessions(max_age=args.max_age)
    result = aggregate.aggregate(records, overrides={"mode": store.get_override()})
    if args.json:
        print(json.dumps({**result, "records": records}, ensure_ascii=False, indent=2))
    else:
        print(render.line(result, result.get("sessions")))
    return 0


def cmd_watch(args):
    os.makedirs(store.home_dir(), exist_ok=True)
    if args.clear_on_start:
        store.clear()
        store.clear_override()
    tr = transport.build(args.transport, port=args.port, name=args.ble_name, verbose=args.verbose)
    print(f"AI Status Light · transport={tr.status()} · store={store.home_dir()}")
    print("watching for agent events... (Ctrl-C to stop)")
    last = None
    try:
        while True:
            records = store.read_sessions(max_age=args.max_age)
            result = aggregate.aggregate(records, overrides={"mode": store.get_override()})
            mode = result["mode"]
            if mode != last:
                try:
                    tr.send(mode)
                except Exception as e:
                    print(f"[transport] {e}", file=sys.stderr)
                last = mode
            if not args.quiet:
                render.render_once(result, clear=True)
            if args.once:
                break
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nstopping...")
    finally:
        tr.close()
    return 0


def cmd_devices(args):
    print("serial ports:")
    ports = transport.list_serial_ports()
    for device, desc in ports:
        print(f"  {device}  {desc}")
    if not ports:
        print("  (none)")
    try:
        import bleak  # noqa: F401
        print(f"ble: bleak available; will scan for '{protocol.BLE_NAME}'")
    except ImportError:
        print("ble: bleak not installed (pip install bleak)")
    return 0


def cmd_demo(args):
    tr = transport.build(args.transport, port=args.port, name=args.ble_name, verbose=args.verbose)
    sequence = ["thinking", "working", "busy", "success", "blocked", "error", "traffic", "idle"]
    print(f"demo · transport={tr.status()}")
    try:
        for mode in sequence:
            tr.send(mode)
            print(render.line({"mode": mode, "reason": "demo"}))
            time.sleep(args.delay)
    except KeyboardInterrupt:
        pass
    finally:
        tr.close()
    return 0


def cmd_install_hooks(args):
    agents = args.agent
    if "all" in agents:
        agents = ["claude", "cursor", "codex", "opencode"]
    for a in agents:
        print(f"== {a} ==")
        if a == "claude":
            integrations.install_claude(dry_run=args.dry_run)
        elif a == "cursor":
            integrations.install_cursor(dry_run=args.dry_run)
        elif a == "codex":
            integrations.install_codex(dry_run=args.dry_run)
        elif a == "opencode":
            integrations.install_opencode(dry_run=args.dry_run)
    return 0


def cmd_uninstall_hooks(args):
    integrations.uninstall(dry_run=args.dry_run)
    return 0


def cmd_clear(args):
    store.clear(args.session)
    if args.session is None:
        store.clear_override()
    print("cleared")
    return 0


def _add_transport(sp):
    sp.add_argument("--transport", choices=["null", "serial", "ble"], default="null")
    sp.add_argument("--port", default=None, help="serial device, e.g. /dev/cu.usbmodem*")
    sp.add_argument("--ble-name", default=protocol.BLE_NAME)
    sp.add_argument("--verbose", action="store_true")


def build_parser():
    ap = argparse.ArgumentParser(prog="aistatus", description="AI coding agent status light")
    sub = ap.add_subparsers(dest="cmd", required=True)

    h = sub.add_parser("hook", help="receive an agent hook (reads JSON on stdin)")
    h.add_argument("--agent", default=None)
    h.add_argument("--event", default=None)
    h.add_argument("--state", default=None)
    h.add_argument("--session", default=None)
    h.add_argument("--message", default=None)
    h.add_argument("--default-state", default="working")
    h.add_argument("--direct", action="store_true", help="also push straight to the device")
    _add_transport(h)
    h.set_defaults(func=cmd_hook)

    e = sub.add_parser("event", help="record a state manually")
    e.add_argument("state")
    e.add_argument("--agent", default="manual")
    e.add_argument("--session", default=None)
    e.add_argument("--message", default=None)
    e.add_argument("--direct", action="store_true")
    _add_transport(e)
    e.set_defaults(func=cmd_event)

    l = sub.add_parser("light", help="force a mode (manual override)")
    l.add_argument("mode", nargs="?", default="idle")
    l.add_argument("--ttl", type=float, default=None, help="override expiry in seconds")
    l.add_argument("--off", action="store_true", help="clear the override")
    _add_transport(l)
    l.set_defaults(func=cmd_light)

    s = sub.add_parser("state", help="show the aggregated state")
    s.add_argument("--json", action="store_true")
    s.add_argument("--max-age", type=float, default=3600)
    s.set_defaults(func=cmd_state)

    w = sub.add_parser("watch", help="daemon: aggregate state and drive the light")
    w.add_argument("--interval", type=float, default=0.4)
    w.add_argument("--max-age", type=float, default=3600)
    w.add_argument("--once", action="store_true")
    w.add_argument("--quiet", action="store_true")
    w.add_argument("--clear-on-start", action="store_true")
    _add_transport(w)
    w.set_defaults(func=cmd_watch)

    d = sub.add_parser("devices", help="list serial ports and BLE availability")
    d.set_defaults(func=cmd_devices)

    dm = sub.add_parser("demo", help="cycle through all light modes")
    dm.add_argument("--delay", type=float, default=1.2)
    _add_transport(dm)
    dm.set_defaults(func=cmd_demo)

    ih = sub.add_parser("install-hooks", help="wire agent hooks to the store")
    ih.add_argument("--agent", nargs="+", default=["all"],
                    choices=["all", "claude", "cursor", "codex", "opencode"])
    ih.add_argument("--dry-run", action="store_true")
    ih.set_defaults(func=cmd_install_hooks)

    uh = sub.add_parser("uninstall-hooks", help="remove aistatus hook entries")
    uh.add_argument("--dry-run", action="store_true")
    uh.set_defaults(func=cmd_uninstall_hooks)

    c = sub.add_parser("clear", help="clear session state")
    c.add_argument("--session", default=None)
    c.set_defaults(func=cmd_clear)
    return ap


def main(argv=None):
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
