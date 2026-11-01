"""Comprueba un WebSocket de telemetria: conecta, valida frames y sale con 0 o 1.

Uso (frames validos):
    python ws_check.py <URL> <N_min_frames> <timeout_s>

Uso (PIN invalido, espera cierre 1008):
    python ws_check.py <URL> 0 <timeout_s> --expect-close 1008

Sin --expect-close: conecta, valida que cada frame JSON tenga cpu_usage,
ram_usage y disk_usage, y espera al menos N frames dentro del timeout.
Sale 0 si ok, 1 si fallo.

Con --expect-close 1008: espera a que el servidor cierre con codigo 1008
(PIN invalido o ausente). Sale 0 si se cierra con 1008, 1 si no.
"""

import json
import sys
import time

from websockets.sync.client import connect
from websockets.exceptions import ConnectionClosed


REQUIRED_KEYS = ("cpu_usage", "ram_usage", "disk_usage")


def validate_frame(payload: str) -> bool:
    """Devuelve True si el frame es JSON y contiene las claves requeridas."""
    try:
        data = json.loads(payload)
    except (json.JSONDecodeError, TypeError):
        return False
    if not isinstance(data, dict):
        return False
    # Ignorar frames de error del servidor (clave "error")
    if "error" in data:
        return True
    return all(k in data for k in REQUIRED_KEYS)


def main() -> int:
    if len(sys.argv) < 4:
        print("Uso: ws_check.py <URL> <N_min_frames> <timeout_s> [--expect-close 1008]")
        return 1

    url = sys.argv[1]
    try:
        n_min = int(sys.argv[2])
        timeout = float(sys.argv[3])
    except ValueError:
        print("ERROR: N_min_frames y timeout_s deben ser numericos.")
        return 1

    expect_close = False
    if len(sys.argv) >= 5 and sys.argv[4] == "--expect-close":
        expect_close = True

    deadline = time.time() + timeout
    frames_ok = 0

    try:
        with connect(url) as ws:
            if expect_close:
                # Esperar a que el servidor cierre la conexion (PIN invalido).
                while time.time() < deadline:
                    try:
                        ws.recv()
                    except ConnectionClosed as exc:
                        if getattr(exc, "code", None) == 1008:
                            print(f"OK: servidor cerro con codigo 1008 (PIN invalido).")
                            return 0
                        print(f"ERROR: servidor cerro con codigo {getattr(exc, 'code', None)} (se esperaba 1008).")
                        return 1
                    time.sleep(0.2)
                print("ERROR: no se recibio cierre 1008 antes del timeout.")
                return 1
            else:
                # Esperar al menos N frames validos.
                while time.time() < deadline:
                    if frames_ok >= n_min:
                        print(f"OK: {frames_ok} frame(s) valido(s) recibido(s) (>= {n_min}).")
                        return 0
                    try:
                        msg = ws.recv(timeout=1.0)
                    except ConnectionClosed:
                        print(f"ERROR: conexion cerrada despues de {frames_ok} frame(s) valido(s).")
                        return 1
                    except TimeoutError:
                        continue
                    if validate_frame(msg):
                        frames_ok += 1
                print(f"ERROR: solo {frames_ok} frame(s) valido(s) (se necesitaban >= {n_min}).")
                return 1
    except Exception as exc:
        print(f"ERROR: no se pudo conectar al WebSocket: {exc}")
        return 1

    print("ERROR: bucle terminado sin resultado.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
