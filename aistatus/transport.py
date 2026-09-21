"""Transports: send a mode to the light over USB serial, BLE, or nowhere (screen)."""

import asyncio
import queue
import threading
import time

from . import protocol


def list_serial_ports():
    try:
        from serial.tools import list_ports
    except ImportError:
        return []
    return [(p.device, p.description or "") for p in list_ports.comports()]


class Transport:
    kind = "null"

    def send(self, mode):
        raise NotImplementedError

    def close(self):
        pass

    def status(self):
        return self.kind


class NullTransport(Transport):
    kind = "null"

    def __init__(self, verbose=False):
        self.verbose = verbose
        self.last = None

    def send(self, mode):
        if self.last != mode:
            self.last = mode
            if self.verbose:
                print(f"[null] -> MODE {mode}", flush=True)


class SerialTransport(Transport):
    kind = "serial"

    def __init__(self, port=None, baud=protocol.BAUD, timeout=1.0, verbose=False):
        try:
            import serial
            from serial.tools import list_ports
        except ImportError as e:
            raise RuntimeError("pyserial not installed (pip install pyserial)") from e
        self._serial_mod = serial
        self.verbose = verbose
        if port is None:
            port = self._autodetect(list_ports)
        self.port = port
        self.baud = baud
        self.timeout = timeout
        self._serial = None
        self._open()

    @staticmethod
    def _autodetect(list_ports):
        candidates = []
        for p in list_ports.comports():
            desc = (p.description or "").lower()
            if any(k in desc for k in ("usb", "uart", "serial", "cp210", "ch34", "esp")):
                candidates.append(p.device)
        if not candidates:
            ports = list(list_ports.comports())
            candidates = [p.device for p in ports]
        if not candidates:
            raise RuntimeError("no serial port found")
        return candidates[0]

    def _open(self):
        self._serial = self._serial_mod.Serial(self.port, self.baud, timeout=self.timeout)

    def send(self, mode):
        if self._serial is None:
            self._open()
        self._serial.write(protocol.encode_mode(mode))
        self._serial.flush()

    def close(self):
        if self._serial is not None:
            try:
                self._serial.close()
            finally:
                self._serial = None

    def status(self):
        return f"serial:{self.port}@{self.baud}"


class BleTransport(Transport):
    kind = "ble"

    def __init__(self, name=protocol.BLE_NAME, verbose=False):
        try:
            import bleak  # noqa: F401
        except ImportError as e:
            raise RuntimeError("bleak not installed (pip install bleak)") from e
        self.name = name
        self.verbose = verbose
        self._q = queue.Queue(maxsize=8)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._connected = False
        self._thread.start()

    def _log(self, *a):
        if self.verbose:
            print("[ble]", *a, flush=True)

    def _run(self):
        try:
            asyncio.run(self._main())
        except Exception as e:
            self._log("loop stopped:", e)

    async def _main(self):
        from bleak import BleakClient, BleakScanner
        while not self._stop.is_set():
            client = None
            try:
                self._log("scanning for", self.name)
                device = await BleakScanner.find_device_by_name(self.name, timeout=8.0)
                if not device:
                    await asyncio.sleep(2)
                    continue
                client = BleakClient(device)
                await client.connect(timeout=15.0)
                self._connected = True
                self._log("connected", device.address)
                while not self._stop.is_set() and client.is_connected:
                    try:
                        mode = self._q.get(timeout=1.0)
                    except queue.Empty:
                        continue
                    await client.write_gatt_char(protocol.RX_CHAR_UUID,
                                                 protocol.encode_mode(mode), response=False)
                    self._log("->", mode)
            except Exception as e:
                self._log("error:", e)
            finally:
                self._connected = False
                if client is not None:
                    try:
                        await client.disconnect()
                    except Exception:
                        pass
                await asyncio.sleep(2)

    def send(self, mode):
        while self._q.full():
            try:
                self._q.get_nowait()
            except queue.Empty:
                break
        try:
            self._q.put_nowait(mode)
        except queue.Full:
            pass

    def close(self):
        self._stop.set()
        self._thread.join(timeout=3)

    def status(self):
        return f"ble:{self.name} ({'connected' if self._connected else 'connecting'})"


def build(kind, port=None, name=None, verbose=False):
    kind = (kind or "null").lower()
    if kind == "serial":
        return SerialTransport(port=port, verbose=verbose) if port else SerialTransport(verbose=verbose)
    if kind == "ble":
        return BleTransport(name=name or protocol.BLE_NAME, verbose=verbose)
    return NullTransport(verbose=verbose)
