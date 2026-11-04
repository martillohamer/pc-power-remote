"""
pc-power-remote — API local para control remoto del PC.
"""

from __future__ import annotations

import asyncio
import hmac
import logging
import os
import platform
import re
import socket
import subprocess
import threading
import time
import uuid
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Annotated

import psutil
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from starlette.websockets import WebSocketDisconnect

try:
    from wakeonlan import send_magic_packet
except ImportError:
    send_magic_packet = None

logger = logging.getLogger("pc_power_remote")
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", "%H:%M:%S")
    )
    logger.addHandler(_handler)
    logger.setLevel(logging.INFO)

BACKEND_DIR = Path(__file__).resolve().parent
ENV_FILE = BACKEND_DIR / ".env"
_REAL_ENV_KEYS = set(os.environ)

def _load_env_file(path: Path) -> None:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value

_load_env_file(ENV_FILE)

DEFAULT_PIN = "134113"
APP_PIN = os.getenv("APP_PIN", DEFAULT_PIN).strip()
DRY_RUN = os.getenv("APP_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"}

MAX_MINUTES = 24 * 60
PIN_HEADER = "X-App-Pin"

MAC_PATTERN = re.compile(r"^[0-9A-Fa-f]{2}([:-]?[0-9A-Fa-f]{2}){5}$")

_IPCONFIG_MAC = re.compile(
    r"(?:Physical Address|Direcci.n f.sica)[ .]*:\s*"
    r"([0-9A-Fa-f]{2}(?:[-:][0-9A-Fa-f]{2}){5})",
    re.IGNORECASE,
)
_IPCONFIG_GATEWAY = re.compile(
    r"(?:Default Gateway|Puerta de enlace predeterminada)[ .]*:\s*"
    r"\d{1,3}(?:\.\d{1,3}){3}",
    re.IGNORECASE,
)

def normalize_mac(value: str) -> str:
    if not MAC_PATTERN.fullmatch(value.strip()):
        raise ValueError("MAC invalida")
    raw = re.sub(r"[^0-9A-Fa-f]", "", value)
    return ":".join(raw[index : index + 2] for index in range(0, 12, 2)).upper()

def _env_mac() -> str | None:
    raw = os.getenv("APP_MAC_ADDRESS", "").strip()
    if not raw:
        return None
    try:
        return normalize_mac(raw)
    except ValueError:
        return None

def _lan_ip() -> str | None:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
        except OSError:
            return None

def _parse_ipconfig(text: str, ip: str | None = None) -> str | None:
    for block in re.split(r"\r?\n\s*\r?\n", text):
        match = _IPCONFIG_MAC.search(block)
        if not match:
            continue
        if ip:
            if ip not in block:
                continue
        elif not _IPCONFIG_GATEWAY.search(block):
            continue
        try:
            return normalize_mac(match.group(1))
        except ValueError:
            continue
    return None

def _detect_system_mac() -> str | None:
    if platform.system() == "Windows":
        try:
            completed = subprocess.run(["ipconfig", "/all"], capture_output=True, timeout=10, check=False)
        except (OSError, subprocess.SubprocessError):
            pass
        else:
            if completed.returncode == 0:
                text = completed.stdout.decode("cp850", errors="replace")
                mac = _parse_ipconfig(text, _lan_ip()) or _parse_ipconfig(text)
                if mac:
                    return mac
    node = uuid.getnode()
    if not (node >> 40) & 1:
        return ":".join(f"{(node >> shift) & 0xFF:02X}" for shift in range(40, -1, -8))
    return None

_ENV_MAC_LINE = re.compile(r"^\s*APP_MAC_ADDRESS\s*=", re.IGNORECASE)

def _write_env_mac(mac: str) -> bool:
    try:
        lines = ENV_FILE.read_text(encoding="utf-8").splitlines() if ENV_FILE.exists() else []
    except OSError:
        return False
    new_line = f"APP_MAC_ADDRESS={mac}"
    updated: list[str] = []
    replaced = False
    for line in lines:
        if _ENV_MAC_LINE.match(line):
            if line.strip() == new_line:
                return False
            updated.append(new_line)
            replaced = True
        else:
            updated.append(line)
    if not replaced:
        updated.append(new_line)
    try:
        ENV_FILE.write_text("\n".join(updated) + "\n", encoding="utf-8")
    except OSError:
        return False
    return True

def _resolve_mac() -> tuple[str | None, str]:
    if "APP_MAC_ADDRESS" in _REAL_ENV_KEYS:
        mac = _env_mac()
        if mac:
            return mac, "env"
    detected = _detect_system_mac()
    if detected:
        if _write_env_mac(detected):
            logger.info("MAC autodetectada %s guardada", detected)
        return detected, "auto"
    mac = _env_mac()
    if mac:
        return mac, "env-file"
    return None, "none"

APP_MAC_ADDRESS, MAC_SOURCE = _resolve_mac()
WOL_BROADCAST = os.getenv("APP_WOL_BROADCAST", "255.255.255.255").strip() or "255.255.255.255"
try:
    WOL_PORT = int(os.getenv("APP_WOL_PORT", "9"))
except ValueError:
    WOL_PORT = 9

@asynccontextmanager
async def lifespan(_: FastAPI):
    yield

app = FastAPI(title="pc-power-remote", version="0.6.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# --- Autenticación y Rate Limiting ---
FAILED_PIN_ATTEMPTS: dict[str, list[float]] = {}
RATE_LIMIT_WINDOW_SECONDS = 60
MAX_FAILED_PIN_ATTEMPTS = 5

def verify_pin_with_rate_limit(
    request: Request,
    x_app_pin: Annotated[str | None, Header(alias=PIN_HEADER)] = None,
) -> None:
    client_ip = (
        request.headers.get("CF-Connecting-IP")
        or request.headers.get("X-Forwarded-For", "").split(",")[0].strip()
        or (request.client.host if request.client else "127.0.0.1")
    )
    if not client_ip:
        client_ip = "127.0.0.1"

    now = time.time()
    attempts = [t for t in FAILED_PIN_ATTEMPTS.get(client_ip, []) if now - t < RATE_LIMIT_WINDOW_SECONDS]
    FAILED_PIN_ATTEMPTS[client_ip] = attempts

    if len(attempts) >= MAX_FAILED_PIN_ATTEMPTS:
        raise HTTPException(status_code=429, detail="Rate limit excedido", headers={"Retry-After": str(RATE_LIMIT_WINDOW_SECONDS)})

    if not x_app_pin or not hmac.compare_digest(x_app_pin.encode("utf-8"), APP_PIN.encode("utf-8")):
        attempts.append(now)
        FAILED_PIN_ATTEMPTS[client_ip] = attempts
        raise HTTPException(status_code=401, detail="PIN invalido", headers={"WWW-Authenticate": PIN_HEADER})

    FAILED_PIN_ATTEMPTS.pop(client_ip, None)

def require_pin(request: Request, x_app_pin: Annotated[str | None, Header(alias=PIN_HEADER)] = None) -> None:
    verify_pin_with_rate_limit(request, x_app_pin)

# --- Modelos ---
class ShutdownRequest(BaseModel):
    minutes: int = Field(default=0, ge=0, le=MAX_MINUTES)

class ShutdownScheduled(BaseModel):
    ok: bool = True
    minutes: int
    seconds: int
    ends_at: str

class ShutdownCancelled(BaseModel):
    ok: bool = True
    message: str

class PowerState(BaseModel):
    pending: bool
    minutes: int | None = None
    seconds_left: int | None = None
    ends_at: str | None = None

class WakeRequest(BaseModel):
    mac: str | None = Field(default=None)
    @field_validator("mac")
    @classmethod
    def _normalize_mac(cls, value: str | None) -> str | None:
        return normalize_mac(value) if value and value.strip() else None

class WolConfig(BaseModel):
    mac_address: str | None
    broadcast: str
    port: int
    source: str = "none"

class Telemetry(BaseModel):
    cpu_usage: float
    ram_usage: float
    ram_used_mb: float
    ram_total_mb: float
    disk_usage: float
    uptime_seconds: int

class ForensicLogEntry(BaseModel):
    timestamp: str
    event: str
    details: str = ""

class ForensicProcessInfo(BaseModel):
    pid: int
    name: str
    cpu_percent: float
    memory_mb: float
    status: str

_forensic_log: list[ForensicLogEntry] = []

def _log_forensic(event: str, details: str = "") -> None:
    _forensic_log.append(ForensicLogEntry(timestamp=datetime.now(timezone.utc).isoformat(), event=event, details=details))
    if len(_forensic_log) > 100:
        _forensic_log.pop(0)

@dataclass(frozen=True)
class _PendingShutdown:
    ends_at: datetime
    minutes: int

_lock = threading.Lock()
_pending: _PendingShutdown | None = None

def _set_pending(p: _PendingShutdown | None) -> None:
    global _pending
    with _lock:
        _pending = p

def _read_pending() -> _PendingShutdown | None:
    with _lock:
        return _pending

def _decode(raw: bytes) -> str:
    for encoding in ("utf-8", "cp850", "cp1252"):
        try:
            return raw.decode(encoding).strip()
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace").strip()

def _run_shutdown(args: list[str]) -> None:
    if platform.system() != "Windows":
        raise HTTPException(status_code=501, detail="Solo Windows")
    if DRY_RUN:
        return
    try:
        completed = subprocess.run(args, capture_output=True, timeout=15, check=False)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    
    if completed.returncode == 0:
        return
    
    stdout_str = _decode(completed.stdout)
    stderr_str = _decode(completed.stderr)
    message = stderr_str or stdout_str

    if completed.returncode == 1116:
        raise HTTPException(status_code=409, detail=message or "No hay apagado pendiente.")
    raise HTTPException(status_code=500, detail=message or "Error shutdown")

TELEMETRY_INTERVAL = 1.5
CPU_SAMPLE_SECONDS = 0.1

def collect_telemetry() -> Telemetry:
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage(os.path.abspath(os.sep))
    mib = 1024 * 1024
    return Telemetry(
        cpu_usage=round(float(psutil.cpu_percent(interval=CPU_SAMPLE_SECONDS)), 1),
        ram_usage=round(float(memory.percent), 1),
        ram_used_mb=round(memory.used / mib, 1),
        ram_total_mb=round(memory.total / mib, 1),
        disk_usage=round(float(disk.percent), 1),
        uptime_seconds=max(0, int(time.time() - psutil.boot_time())),
    )

# --- Endpoints ---
@app.get("/")
def read_root():
    return {"status": "online"}

@app.get("/api/health")
def health():
    return {"status": "online"}

# Endpoint público para que la app web y móvil consulten el estado sin PIN
@app.get("/api/public-state", response_model=PowerState)
def public_power_state() -> PowerState:
    pending = _read_pending()
    if pending is None:
        return PowerState(pending=False)
    seconds_left = int((pending.ends_at - datetime.now(timezone.utc)).total_seconds())
    if seconds_left <= 0:
        _set_pending(None)
        return PowerState(pending=False)
    return PowerState(pending=True, minutes=pending.minutes, seconds_left=seconds_left, ends_at=pending.ends_at.isoformat())

@app.get("/api/config", response_model=WolConfig)
def get_config() -> WolConfig:
    return WolConfig(mac_address=APP_MAC_ADDRESS, broadcast=WOL_BROADCAST, port=WOL_PORT, source=MAC_SOURCE)

# Endpoint público para que la app web y móvil consulten el estado sin PIN
@app.get("/api/state", response_model=PowerState)
def power_state() -> PowerState:
    pending = _read_pending()
    if pending is None:
        return PowerState(pending=False)
    seconds_left = int((pending.ends_at - datetime.now(timezone.utc)).total_seconds())
    if seconds_left <= 0:
        _set_pending(None)
        return PowerState(pending=False)
    return PowerState(pending=True, minutes=pending.minutes, seconds_left=seconds_left, ends_at=pending.ends_at.isoformat())

# WEBSOCKET DE TELEMETRIA (100% Abierto para tests y app)
@app.websocket("/ws/telemetry")
async def websocket_telemetry(websocket: WebSocket):
    await websocket.accept()
    try:
        while True:
            try:
                data = collect_telemetry()
                await websocket.send_json(data.model_dump())
            except Exception as exc:
                await websocket.send_json({"error": str(exc)})
            await asyncio.sleep(TELEMETRY_INTERVAL)
    except WebSocketDisconnect:
        pass

@app.get("/api/forensic/processes", dependencies=[Depends(require_pin)])
def forensic_processes() -> list[ForensicProcessInfo]:
    try:
        candidate_procs = []
        for proc in psutil.process_iter(["pid", "name", "memory_info", "status"]):
            try:
                info = proc.info
                name = info.get("name")
                if name in (None, "System Idle Process", "System"):
                    continue
                proc.cpu_percent(None)
                candidate_procs.append(proc)
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue

        time.sleep(0.3)
        num_cores = psutil.cpu_count() or 1
        max_cpu = 100.0 * num_cores

        processes: list[ForensicProcessInfo] = []
        for proc in candidate_procs:
            try:
                info = proc.info
                raw_cpu = proc.cpu_percent(None)
                cpu_percent = round(min(max(0.0, float(raw_cpu)), max_cpu), 1)
                memory_mb = 0.0
                if info.get("memory_info"):
                    memory_mb = round(float(info["memory_info"].rss) / (1024 * 1024), 1)
                processes.append(
                    ForensicProcessInfo(
                        pid=info["pid"],
                        name=info["name"],
                        cpu_percent=cpu_percent,
                        memory_mb=memory_mb,
                        status=info.get("status") or "unknown",
                    )
                )
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue

        processes.sort(key=lambda p: (p.cpu_percent, p.memory_mb), reverse=True)
        return processes[:10]
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))

@app.get("/api/forensic/logs", dependencies=[Depends(require_pin)])
def forensic_logs_endpoint() -> list[ForensicLogEntry]:
    return list(_forensic_log)

@app.post("/api/shutdown", dependencies=[Depends(require_pin)], response_model=ShutdownScheduled)
def schedule_shutdown(payload: ShutdownRequest | None = None):
    minutes = payload.minutes if payload is not None else 0
    if minutes == 0:
        _run_shutdown(["shutdown", "/s", "/f", "/t", "0"])
        _set_pending(None)
        return ShutdownScheduled(minutes=0, seconds=0, ends_at=datetime.now(timezone.utc).isoformat())

    try:
        _run_shutdown(["shutdown", "/a"])
    except HTTPException as exc:
        if exc.status_code != 409:
            raise

    seconds = minutes * 60
    _run_shutdown(["shutdown", "/s", "/t", str(seconds)])
    ends_at = datetime.now(timezone.utc) + timedelta(seconds=seconds)
    _set_pending(_PendingShutdown(ends_at=ends_at, minutes=minutes))
    return ShutdownScheduled(minutes=minutes, seconds=seconds, ends_at=ends_at.isoformat())

@app.post("/api/cancel", dependencies=[Depends(require_pin)], response_model=ShutdownCancelled)
def cancel_shutdown():
    try:
        _run_shutdown(["shutdown", "/a"])
    except HTTPException as exc:
        if exc.status_code == 409:
            _set_pending(None)
            return ShutdownCancelled(ok=True, message="No había apagado pendiente para cancelar.")
        raise
    _set_pending(None)
    return ShutdownCancelled(ok=True, message="Apagado cancelado.")

@app.post("/api/wake", dependencies=[Depends(require_pin)])
def wake_pc(payload: WakeRequest | None = None):
    target_mac = payload.mac if payload and payload.mac else APP_MAC_ADDRESS
    if not target_mac:
        raise HTTPException(status_code=409, detail="No hay MAC configurada.")
    if send_magic_packet is None:
        raise HTTPException(status_code=503, detail="Librería wakeonlan no disponible.")
    try:
        send_magic_packet(target_mac, ip_address=WOL_BROADCAST, port=WOL_PORT)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
    return {"ok": True, "mac": target_mac, "broadcast": WOL_BROADCAST, "port": WOL_PORT}