"""Wire protocol shared with the ESP32 firmware (newline-terminated text).

WRITE: "MODE <mode>\\n" | "COLOR <r> <g> <b>\\n" | "PING\\n" | "HELLO\\n"
       | "NAME <nickname>\\n" | "BOOT <mode>\\n" | "AP ON|OFF\\n" | "CFG\\n"
READ:  "OK <mode>\\n" | "PONG\\n" | "HELLO AI-STATUS-LIGHT v<ver>\\n"
       | "OK color(ignored)\\n" | "ERR <why>\\n" | "CFG ...\\n"
"""

SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
RX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
TX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
BLE_NAME = "AI-Status-Light"
BAUD = 115200

HELLO = b"HELLO\n"


def encode_mode(mode):
    return f"MODE {mode}\n".encode()


def encode_color(r, g, b):
    return f"COLOR {int(r)} {int(g)} {int(b)}\n".encode()


PING = b"PING\n"


def parse_response(data):
    text = data.decode(errors="replace").strip()
    if text in ("OK", "PONG", "ERR"):
        return text
    return text or None
