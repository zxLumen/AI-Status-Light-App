"""Terminal renderer used when no hardware is attached."""

import sys
import time

from . import states, store

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"

_GLYPH = {
    "off": "○", "idle": "○", "busy": "◐", "alarm": "◉", "demo": "◈",
    "traffic": "◍", "thinking": "●", "warning": "⚠",
}


def _ansi_from_hex(color):
    try:
        color = color.lstrip("#")
        r, g, b = (int(color[i:i + 2], 16) for i in (0, 2, 4))
    except (ValueError, AttributeError):
        return "\033[2m"
    lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if lum > 200:
        return "\033[1m"
    return "\033[38;2;%d;%d;%dm" % (r, g, b)


def _style(mode):
    info = states.DISPLAY.get(mode) or {}
    color = _ansi_from_hex(info.get("color", ""))
    label = info.get("label", mode)
    glyph = _GLYPH.get(mode, "●")
    return color, glyph, label


def line(result, records=None):
    mode = result.get("mode", "idle")
    color, icon, label = _style(mode)
    ts = time.strftime("%H:%M:%S")
    reason = result.get("reason", "")
    extra = ""
    if records:
        agents = sorted({r.get("agent", "?") for r in records})
        extra = f"  {DIM}[{len(records)} session(s): {', '.join(agents)}]{RESET}"
    return f"{DIM}{ts}{RESET} {color}{BOLD}{icon} {label:<10}{RESET} {DIM}{reason}{RESET}{extra}"


def render_once(result, clear=False):
    if clear:
        sys.stdout.write("\r\033[K")
        sys.stdout.write(line(result))
        sys.stdout.flush()
    else:
        print(line(result))
