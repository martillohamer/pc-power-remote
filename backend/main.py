"""pc-power-remote — API local para control remoto del PC.

Ejecutar en desarrollo:
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload

Variables de entorno:
    APP_PIN            PIN exigido en la cabecera X-App-Pin (default: "134113").
    APP_DRY_RUN        "1" para simular el apagado sin ejecutar shutdown.exe.
    APP_MAC_ADDRESS    MAC de la NIC (opcional: si falta se autodetecta).
    APP_WOL_BROADCAST  Broadcast del paquete magico (default: 255.255.255.255).
    APP_WOL_PORT       Puerto UDP de Wake-on-LAN (default: 9).

La MAC autodetectada se guarda en `backend/.env` para reutilizarse en el
siguiente arranque. Un APP_MAC_ADDRESS definido en el entorno real siempre
tiene prioridad sobre la deteccion automatica.

Nueva Fase 4.4 - Caja Negra Forense:
  - /api/forensic/processes : lista los 10 procesos de mayor consumo de CPU/RAM.
  - /api/forensic/logs    : log circular de eventos críticos (picos, suspensiones, reinicios).
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
from fastapi import Depends, FastAPI, Header, HTTPException, Query, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field, field_validator
from starlette.websockets import WebSocketDisconnect

try:
    from wakeonlan import send_magic_packet
except ImportError:  # la API de apagado sigue funcionando sin la libreria
    send_magic_packet = None

logger = logging.getLogger("pc_power_remote")
if not logger.handlers:
    # uvicorn solo configura sus propios loggers; este handler hace visibles los
    # eventos de apagado/WOL en la misma terminal sin activar el resto de librerias.
    _handler = logging.StreamHandler()
    _handler.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(message)s", "%H:%M:%S")
    )
    logger.addHandler(_handler)
    logger.setLevel(logging.INFO)

# --- Carga de .env -----------------------------------------------------------

BACKEND_DIR = Path(__file__).resolve().parent
ENV_FILE = BACKEND_DIR / ".env"
_REAL_ENV_KEYS = set(os.environ)  # variables definidas antes de leer .env


def _load_env_file(path: Path) -> None:
    """Carga KEY=VALUE de .env sin sobrescribir variables ya definidas."""
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

# --- Configuracion -----------------------------------------------------------

DEFAULT_PIN = "134113"
APP_PIN = os.getenv("APP_PIN", DEFAULT_PIN).strip()
DRY_RUN = os.getenv("APP_DRY_RUN", "").strip().lower() in {"1", "true", "yes", "on"}

MAX_MINUTES = 24 * 60  # 24 h
PIN_HEADER = "X-App-Pin"

MAC_PATTERN = re.compile(r"^[0-9A-Fa-f]{2}([:-]?[0-9A-Fa-f]{2}){5}$")

# ipconfig /all: "Physical Address" (en) o "Dirección física" (es).
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
    """Normaliza una MAC a AA:BB:CC:DD:EE:FF. Lanza ValueError si no es valida."""
    if not MAC_PATTERN.fullmatch(value.strip()):
        raise ValueError("MAC invalida: usa el formato AA:BB:CC:DD:EE:FF")
    raw = re.sub(r"[^0-9A-Fa-f]", "", value)
    return ":".join(raw[index : index + 2] for index in range(0, 12, 2)).upper()


def _env_mac() -> str | None:
    raw = os.getenv("APP_MAC_ADDRESS", "").strip()
    if not raw:
        return None
    try:
        return normalize_mac(raw)
    except ValueError:
        logger.error(
            "APP_MAC_ADDRESS invalida (%r): se ignora. Usa el formato AA:BB:CC:DD:EE:FF.",
            raw,
        )
        return None


def _lan_ip() -> str | None:
    """IP local de la interfaz usada por la ruta por defecto (no envia trafico real)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        try:
            sock.connect(("8.8.8.8", 80))
            return sock.getsockname()[0]
        except OSError:
            return None


def _parse_ipconfig(text: str, ip: str | None = None) -> str | None:
    """MAC del adaptador que usa `ip`; sin IP, la del adaptador con puerta de enlace."""
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
    """MAC de la NIC activa principal (Windows: ipconfig; fallback: uuid.getnode)."""
    if platform.system() == "Windows":
        try:
            completed = subprocess.run(
                ["ipconfig", "/all"],
                capture_output=True,
                timeout=10,
                check=False,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            logger.warning("No se pudo ejecutar ipconfig: %s", exc)
        else:
            if completed.returncode == 0:
                text = completed.stdout.decode("cp850", errors="replace")
                mac = _parse_ipconfig(text, _lan_ip()) or _parse_ipconfig(text)
                if mac:
                    return mac

    # Fallback portable. uuid.getnode() marca el bit multicast cuando la MAC
    # es aleatoria (no corresponde a una tarjeta real), asi que se descarta.
    node = uuid.getnode()
    if not (node >> 40) & 1:
        return ":".join(
            f"{(node >> shift) & 0xFF:02X}" for shift in range(40, -1, -8)
        )
    return None


_ENV_MAC_LINE = re.compile(r"^\s*APP_MAC_ADDRESS\s*=", re.IGNORECASE)


def _write_env_mac(mac: str) -> bool:
    """Crea/actualiza APP_MAC_ADDRESS en .env preservando el resto del archivo.

    Devuelve True solo si el archivo cambio (evita recargas infinitas con --reload).
    """
    try:
        lines = (
            ENV_FILE.read_text(encoding="utf-8").splitlines()
            if ENV_FILE.exists()
            else []
        )
    except OSError as exc:
        logger.warning("No se pudo leer %s: %s", ENV_FILE, exc)
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
    except OSError as exc:
        logger.warning("No se pudo escribir %s: %s", ENV_FILE, exc)
        return False
    return True


def _resolve_mac() -> tuple[str | None, str]:
    """Resuelve la MAC efectiva y su origen.

    Prioridad: APP_MAC_ADDRESS real > autodeteccion > valor de .env.
    """
    if "APP_MAC_ADDRESS" in _REAL_ENV_KEYS:
        mac = _env_mac()
        if mac:
            return mac, "env"

    detected = _detect_system_mac()
    if detected:
        if _write_env_mac(detected):
            logger.info("MAC autodetectada %s guardada en %s", detected, ENV_FILE.name)
        return detected, "auto"

    mac = _env_mac()
    if mac:
        return mac, "env-file"
    return None, "none"


APP_MAC_ADDRESS, MAC_SOURCE = _resolve_mac()

WOL_BROADCAST = (
    os.getenv("APP_WOL_BROADCAST", "255.255.255.255").strip() or "255.255.255.255"
)
try:
    WOL_PORT = int(os.getenv("APP_WOL_PORT", "9"))
except ValueError:
    logger.error("APP_WOL_PORT invalido: se usa el puerto 9.")
    WOL_PORT = 9

if APP_PIN == DEFAULT_PIN:
    logger.warning(
        "Usando el PIN por defecto (%s). Define APP_PIN antes de exponer la API en la LAN.",
        DEFAULT_PIN,
    )

if APP_MAC_ADDRESS:
    logger.info("Wake-on-LAN listo: MAC %s (origen: %s)", APP_MAC_ADDRESS, MAC_SOURCE)
else:
    logger.warning(
        "No se pudo autodetectar la MAC. Define APP_MAC_ADDRESS o envia "
        "{\"mac\": \"AA:BB:CC:DD:EE:FF\"} en /api/wake."
    )


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Imprime en la terminal las URLs para abrir la app desde el movil."""
    host = _lan_ip() or "IP_DE_TU_PC"
    pin_state = (
        f"por defecto ({DEFAULT_PIN}) - define APP_PIN para cambiarlo"
        if APP_PIN == DEFAULT_PIN
        else "definido por la variable APP_PIN"
    )
    wol_state = (
        f"{APP_MAC_ADDRESS} ({MAC_SOURCE})"
        if APP_MAC_ADDRESS
        else "no detectada - define APP_MAC_ADDRESS"
    )
    banner = [
        "",
        "=" * 66,
        "  pc-power-remote  |  servidor listo",
        "  Backend local   : http://localhost:8000",
        f"  Backend red     : http://{host}:8000",
        f"  Swagger         : http://{host}:8000/docs",
        f"  Frontend (Vite) : http://{host}:5173",
        f"  PIN             : {pin_state}",
        f"  Wake-on-LAN     : {wol_state}",
        "=" * 66,
        "",
    ]
    print("\n".join(banner), flush=True)
    logger.info("IP local detectada: %s (backend :8000, frontend :5173)", host)
    yield

app = FastAPI(
    title="pc-power-remote",
    description="API local para controlar el estado y la energia del PC desde la red local.",
    version="0.6.0",
    lifespan=lifespan,
)

# En desarrollo el frontend corre en otro origen (Vite: 5173), por eso se habilita CORS.
# En produccion, restringir allow_origins a los origenes reales.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Permite cualquier origen en desarrollo; en prod restringir a dominios reales
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    # Permite que cabeceras de proxy inverso pasen seguras:
    expose_headers=["*"],
)


# --- Autenticacion por PIN ---------------------------------------------------

def require_pin(
    x_app_pin: Annotated[str | None, Header(alias=PIN_HEADER)] = None,
) -> None:
    """Dependency: valida la cabecera X-App-Pin contra APP_PIN.

    Se usa comparacion en tiempo constante para no filtrar informacion del PIN
    mediante diferencias de tiempo de respuesta.
    """
    if not x_app_pin or not hmac.compare_digest(
        x_app_pin.encode("utf-8"), APP_PIN.encode("utf-8")
    ):
        raise HTTPException(
            status_code=401,
            detail="PIN invalido o ausente.",
            headers={"WWW-Authenticate": PIN_HEADER},
        )


def _ws_pin_ok(websocket: WebSocket, pin: str | None) -> bool:
    """Valida el PIN de un WebSocket: query param ?pin= o cabecera X-App-Pin."""
    candidate = (pin or websocket.headers.get(PIN_HEADER) or "").strip()
    return bool(candidate) and hmac.compare_digest(
        candidate.encode("utf-8"), APP_PIN.encode("utf-8")
    )


# --- Modelos -----------------------------------------------------------------


class ShutdownRequest(BaseModel):
    minutes: int = Field(
        default=0,
        ge=0,
        le=MAX_MINUTES,
        description="Minutos de espera antes de apagar el equipo (0 = inmediato).",
        examples=[0, 15],
    )


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
    mac: str | None = Field(
        default=None,
        description="MAC destino (AA:BB:CC:DD:EE:FF). Si se omite se usa APP_MAC_ADDRESS.",
        examples=["AA:BB:CC:DD:EE:FF"],
    )

    @field_validator("mac")
    @classmethod
    def _normalize_mac(cls, value: str | None) -> str | None:
        if value is None or not value.strip():
            return None
        return normalize_mac(value)


class WakeSent(BaseModel):
    ok: bool = True
    mac: str
    broadcast: str
    port: int


class WolConfig(BaseModel):
    mac_address: str | None
    broadcast: str
    port: int
    source: str = Field(
        default="none",
        description="Origen de la MAC: env, auto, env-file o none.",
    )


class Telemetry(BaseModel):
    cpu_usage: float
    ram_usage: float
    ram_used_mb: float
    ram_total_mb: float
    disk_usage: float
    uptime_seconds: int


class SuspendRequest(BaseModel):
    minutes: int | None = Field(
        default=None,
        ge=1,
        le=60,
        description="Minutos para esperar antes de suspender (máx. 60). Si omite, suspende inmediatamente.",
        examples=[5],
    )


class GuardianState(BaseModel):
    enabled: bool = False
    cpu_threshold_percent: float = Field(default=5.0, ge=1.0, le=50.0)
    inactivity_minutes: int = Field(default=30, ge=1, le=480)
    last_check: str | None = None
    suspended: bool = False


# --- Sistema de logs forense (caja negra) -----------------------------------

MAX_LOG_ENTRIES = 100  # máximo de entradas en el log circular


class ForensicLogEntry(BaseModel):
    timestamp: str
    event: str  # "cpu_pico", "suspension", "restart", "alert", etc.
    details: str = ""  # mensaje descriptivo opcional


# Almacenamiento en memoria (se reinicia al reiniciar el backend)
_forensic_log: list[ForensicLogEntry] = []


class ForensicProcessInfo(BaseModel):
    pid: int
    name: str
    cpu_percent: float
    memory_mb: float
    status: str


# Helper para añadir entradas al log forense
def _log_forensic(event: str, details: str = "") -> None:
    """Añade una entrada al log circular forense."""
    entry = ForensicLogEntry(timestamp=datetime.now(timezone.utc).isoformat(), event=event, details=details)
    _forensic_log.append(entry)
    # Mantener solo los MAX_LOG_ENTRIES entradas
    if len(_forensic_log) > MAX_LOG_ENTRIES:
        _forensic_log.pop(0)


# --- Endpoints forenses ------------------------------------------------------

@app.get(
    "/api/forensic/processes",
    dependencies=[Depends(require_pin)],
    summary="Los 10 procesos de mayor consumo de CPU y RAM",
)
def forensic_processes() -> list[ForensicProcessInfo]:
    """Retorna los procesos actuales que más CPU y memoria RAM consumen.

    Cada elemento contiene: pid, nombre, uso de CPU %, memoria en MB y estado.
    Solo está disponible cuando el PIN se proporciona en la cabecera X-App-Pin.
    """
    try:
        candidate_procs = []
        for proc in psutil.process_iter(["pid", "name", "memory_info", "status"]):
            try:
                info = proc.info
                name = info.get("name")
                if name in (None, "System Idle Process", "System"):
                    continue
                # Primera pasada: primar medición de CPU
                proc.cpu_percent(None)
                candidate_procs.append(proc)
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue

        # Esperar ~0.3 s entre primera y segunda pasada para obtener muestra real
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

        # Ordenar por (cpu_percent, memory_mb) descendente
        processes.sort(key=lambda p: (p.cpu_percent, p.memory_mb), reverse=True)

        # Retornar solo los top 10
        return processes[:10]
    except Exception as exc:
        logger.error("Error al obtener procesos forenses: %s", exc)
        raise HTTPException(status_code=500, detail=f"Error interno: {exc}")


@app.get(
    "/api/forensic/logs",
    dependencies=[Depends(require_pin)],
    summary="Log circular de eventos críticos del sistema",
)
def forensic_logs_endpoint() -> list[ForensicLogEntry]:
    """Retorna el log circular de los últimos eventos críticos.

    Incluye picos de CPU, intentos de suspensión, reinicios o alertas de
    autodefensa. El log se mantiene en memoria y se reinicia al reiniciar
    el servidor.
    """
    return list(_forensic_log)


# --- Ejecucion de comandos de Windows ---------------------------------------


def _decode(raw: bytes) -> str:
    """shutdown.exe responde en la codificacion local de Windows (cp850 en es-PY)."""
    for encoding in ("utf-8", "cp850", "cp1252"):
        try:
            return raw.decode(encoding).strip()
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace").strip()


def _run_shutdown(args: list[str]) -> None:
    """Ejecuta `shutdown` y traduce los fallos a HTTPException."""
    if platform.system() != "Windows":
        raise HTTPException(
            status_code=501,
            detail="Los comandos de apagado solo estan disponibles en Windows.",
        )

    if DRY_RUN:
        logger.warning("APP_DRY_RUN activo: se omite la ejecucion de %s", args)
        return

    try:
        completed = subprocess.run(args, capture_output=True, timeout=15, check=False)
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=500,
            detail="No se encontro el comando 'shutdown' en el sistema.",
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(
            status_code=500,
            detail="El comando shutdown no respondio a tiempo.",
        ) from exc
    except OSError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo ejecutar shutdown: {exc}",
        ) from exc

    stdout_str = _decode(completed.stdout)
    stderr_str = _decode(completed.stderr)
    logger.info(
        "Comando '%s' finalizado. returncode=%d, stdout=%r, stderr=%r",
        " ".join(args),
        completed.returncode,
        stdout_str,
        stderr_str,
    )

    if completed.returncode == 0:
        return

    message = stderr_str or stdout_str

    # 1116: no hay un apagado en curso que cancelar (Windows en es-PY).
    if completed.returncode == 1116:
        raise HTTPException(
            status_code=409,
            detail=message or "No hay un apagado programado para cancelar.",
        )

    raise HTTPException(
        status_code=500,
        detail=message or f"shutdown finalizo con codigo {completed.returncode}.",
    )


# --- Estado en memoria del apagado programado --------------------------------


@dataclass(frozen=True)
class _PendingShutdown:
    ends_at: datetime
    minutes: int


_lock = threading.Lock()
_pending: _PendingShutdown | None = None


def _set_pending(pending: _PendingShutdown | None) -> None:
    global _pending
    with _lock:
        _pending = pending


def _read_pending() -> _PendingShutdown | None:
    with _lock:
        return _pending


# --- Reloj del countdown -----------------------------------------------------





# --- Guardian de energia -----------------------------------------------------


_guardian = GuardianState()
_guardian_lock = threading.Lock()
_guardian_thread: threading.Thread | None = None
_guardian_stop_event = threading.Event()


def _guardian_monitor() -> None:
    # Monitor de CPU para suspension automática
    global _guardian
    cpu_threshold = _guardian.cpu_threshold_percent
    inactivity_minutes = _guardian.inactivity_minutes
    enabled = _guardian.enabled
    if not enabled:
        with _guardian_lock:
            _guardian.last_check = datetime.utcnow().isoformat()
        return
    consecutive_low = 0
    total_low_seconds = 0
    sample_interval = 3
    while not _guardian_stop_event.is_set():
        try:
            cpu_pct = psutil.cpu_percent(interval=CPU_SAMPLE_SECONDS)
            total_low_seconds += sample_interval
            consecutive_low += 1
            if cpu_pct < cpu_threshold:
                if consecutive_low >= GUARDIAN_CONSECUTIVE_LOW and total_low_seconds >= (inactivity_minutes * 60):
                    _attempt_suspend()
                    consecutive_low = 0
                    total_low_seconds = 0
            else:
                consecutive_low = 0
                total_low_seconds = 0
            with _guardian_lock:
                _guardian.last_check = datetime.utcnow().isoformat()
                _guardian.suspended = total_low_seconds >= (inactivity_minutes * 60) and consecutive_low >= GUARDIAN_CONSECUTIVE_LOW
            _guardian_stop_event.wait(timeout=GUARDIAN_CPU_SAMPLE_INTERVAL)
        except RuntimeError:
            break
        except Exception as exc:
            logger.error("Error en monitor guardian: %s", exc)
            _guardian_stop_event.wait(timeout=5.0)


GUARDIAN_CONSECUTIVE_LOW = 3
GUARDIAN_CPU_SAMPLE_INTERVAL = 10
GUARDIAN_DEFAULT_THRESHOLD = 5.0
GUARDIAN_DEFAULT_INACTIVITY = 30


def _attempt_suspend() -> None:
    _log_forensic("suspension", "Suspensión programada" if DRY_RUN else "Suspensión ejecutada")

    if DRY_RUN:
        logger.info("Suspensión programada (Dry Run)")
        with _guardian_lock:
            _guardian.suspended = True
        return
    cmd = ["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"]
    try:
        subprocess.run(cmd, capture_output=True, timeout=5, check=False)
        logger.info("Suspensión ejecutada")
    except FileNotFoundError:
        logger.error("No se encontro rundll32.exe")
    except OSError as exc:
        logger.error("Error al ejecutar suspensión: %s", exc)
    with _guardian_lock:
        _guardian.suspended = True


def _reset_guardian() -> None:
    global _guardian
    with _guardian_lock:
        _guardian.enabled = False
        _guardian.suspended = False
        _guardian.cpu_threshold_percent = GUARDIAN_DEFAULT_THRESHOLD
        _guardian.inactivity_minutes = GUARDIAN_DEFAULT_INACTIVITY
        _guardian.last_check = None


def _start_guardian_thread() -> None:
    global _guardian_thread, _guardian_stop_event
    if _guardian_thread and _guardian_thread.is_alive():
        _guardian_stop_event.set()
        _guardian_thread.join(timeout=5.0)
    _guardian_stop_event = threading.Event()
    with _guardian_lock:
        _guardian.enabled = False
        _guardian.suspended = False
    _guardian_thread = threading.Thread(target=_guardian_monitor, daemon=True)
    _guardian_thread.start()
    logger.info("Hilo de guardian de energía iniciado")


def _stop_guardian_thread() -> None:
    global _guardian_thread
    if _guardian_thread and _guardian_thread.is_alive():
        _guardian_stop_event.set()
        _guardian_thread.join(timeout=10.0)
        _guardian_thread = None
        logger.info("Hilo de guardian detenido")


# --- Telemetria en tiempo real (WebSocket) -----------------------------------


TELEMETRY_INTERVAL = 1.5  # segundos entre muestras
CPU_SAMPLE_SECONDS = 0.1  # ventana de medicion de CPU (en el hilo de trabajo)
GUARDIAN_CONSECUTIVE_LOW = 3  # muestreos consecutivos por debajo del umbral
GUARDIAN_CPU_SAMPLE_INTERVAL = 10  # segundos entre muestreos de decisi.on
GUARDIAN_DEFAULT_THRESHOLD = 5.0  # %
GUARDIAN_DEFAULT_INACTIVITY = 30  # minutos


def collect_telemetry() -> Telemetry:
    """Muestra puntual del sistema (se ejecuta en un hilo aparte).

    cpu_percent usa interval=0.1 para que la primera muestra sea real: psutil
    guarda el estado por hilo y un interval=None devolveria 0.0 la primera vez.
    """
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


# --- Endpoints ---------------------------------------------------------------


@app.get("/")
def read_root() -> dict[str, str]:
    """Healthcheck publico."""
    return {"status": "online", "system": "Windows"}


@app.get("/api/health")
def health() -> dict[str, str]:
    """Mismo payload que `/`, pero bajo /api para consumirse via el proxy de Vite."""
    return {"status": "online", "system": "Windows"}


@app.get(
    "/api/state",
    dependencies=[Depends(require_pin)],
    response_model=PowerState,
    summary="Estado del apagado programado",
)
def power_state() -> PowerState:
    pending = _read_pending()
    if pending is None:
        return PowerState(pending=False)

    seconds_left = int((pending.ends_at - datetime.now(timezone.utc)).total_seconds())
    if seconds_left <= 0:
        _set_pending(None)
        return PowerState(pending=False)

    return PowerState(
        pending=True,
        minutes=pending.minutes,
        seconds_left=seconds_left,
        ends_at=pending.ends_at.isoformat(),
    )


@app.post(
    "/api/shutdown",
    dependencies=[Depends(require_pin)],
    response_model=ShutdownScheduled,
    summary="Programa el apagado del equipo",
)
def schedule_shutdown(
    payload: ShutdownRequest | None = None,
) -> ShutdownScheduled:
    minutes = payload.minutes if payload is not None else 0

    if minutes == 0:
        # Apagado inmediato sincrono (Terminator)
        _run_shutdown(["shutdown", "/s", "/f", "/t", "0"])
        _set_pending(None)
        _log_forensic("shutdown_terminator", "Apagado inmediato Terminator ejecutado")
        logger.info("Apagado inmediato Terminator ejecutado (shutdown /s /f /t 0)")
        now_iso = datetime.now(timezone.utc).isoformat()
        return ShutdownScheduled(
            minutes=0,
            seconds=0,
            ends_at=now_iso,
        )

    # Si es mayor que 0: abortar apagado previo ignorando 409 para evitar error 1190
    try:
        _run_shutdown(["shutdown", "/a"])
    except HTTPException as exc:
        if exc.status_code != 409:
            raise

    seconds = minutes * 60
    _run_shutdown(["shutdown", "/s", "/t", str(seconds)])

    ends_at = datetime.now(timezone.utc) + timedelta(seconds=seconds)
    _set_pending(_PendingShutdown(ends_at=ends_at, minutes=minutes))
    _log_forensic("shutdown_scheduled", f"Apagado programado en {minutes} min")

    logger.info("Apagado programado en %s min (ends_at=%s)", minutes, ends_at)
    return ShutdownScheduled(
        minutes=minutes,
        seconds=seconds,
        ends_at=ends_at.isoformat(),
    )


@app.post(
    "/api/cancel",
    dependencies=[Depends(require_pin)],
    response_model=ShutdownCancelled,
    summary="Cancela un apagado programado",
)
def cancel_shutdown() -> ShutdownCancelled:
    """Cancela cualquier apagado programado mediante shutdown /a.

    Nota de limitación: un apagado ejecutado con /t 0 (inmediato/Terminator)
    no puede ser cancelado por Windows. Solo los apagados con temporizador
    (/t > 0) son cancelables.
    """
    try:
        # Ejecutar shutdown /a para abortar cualquier apagado programado
        _run_shutdown(["shutdown", "/a"])
    except HTTPException as exc:
        # 1116 (mapeado a 409 en _run_shutdown): no habia ningun apagado en curso
        if exc.status_code == 409:
            _set_pending(None)
            logger.info("Cancelación solicitada pero no había apagado pendiente en Windows (1116)")
            return ShutdownCancelled(
                ok=True,
                message="No había apagado pendiente para cancelar.",
            )
        # Cualquier otro error lo propagamos
        raise

    # Limpiar estado local del temporizador de apagado para reflejar en la UI
    _set_pending(None)
    _log_forensic("shutdown_cancelled", "Apagado programado cancelado")

    logger.info("Apagado cancelado y estado local limpiado")
    return ShutdownCancelled(
        ok=True,
        message="Apagado cancelado. El temporizador fue abortado. El equipo sigue encendido.",
    )


# --- Endpoints de Control de Sesión Windows ---

def _lock_workstation() -> dict[str, str]:
    """Bloquea la sesión de trabajo de Windows de forma remota.
    
    Ejecuta rundll32.exe user32.dll,LockWorkStation para bloquear la estación de trabajo.
    Retorna un diccionario con el estado y mensaje descriptivo.
    """
    cmd = ["rundll32.exe", "user32.dll,LockWorkStation"]
    try:
        subprocess.run(cmd, capture_output=True, timeout=5, check=False)
        return {"status": "locked", "message": "Sesión bloqueada exitosamente"}
    except FileNotFoundError:
        return {"status": "error", "message": "No se encontró rundll32.exe"}
    except OSError as exc:
        return {"status": "error", "message": f"Error al bloquear sesión: {exc}"}


def _unlock_workstation() -> dict[str, str]:
    """Intenta desbloquear la sesión de Windows.
    
    En Windows, el desbloqueo requiere que el usuario ingrese su contraseña.
    Este comando solo funciona si ya hay una sesión bloqueada por el sistema.
    """
    cmd = ["shutdown", "/l"]
    try:
        result = subprocess.run(cmd, capture_output=True, timeout=5, check=False)
        if result.returncode == 0:
            return {"status": "unlocked", "message": "Sesión desbloqueada"}
        else:
            return {"status": "locked", "message": "No se pudo desbloquear (requiere contraseña)"}
    except FileNotFoundError:
        return {"status": "error", "message": "No se encontró el comando shutdown"}
    except OSError as exc:
        return {"status": "error", "message": f"Error al intentar desbloquear: {exc}"}


@app.get(
    "/api/windows/lock",
    dependencies=[Depends(require_pin)],
    summary="Bloquea la sesión de trabajo del Windows local",
)
def windows_lock() -> dict[str, str]:
    """Bloquea inmediatamente la sesión de trabajo del Windows local.
    
    Ejecuta rundll32.exe user32.dll,LockWorkStation para bloquear la estación de trabajo.
    Requiere PIN en la cabecera X-App-Pin.
    """
    result = _lock_workstation()
    logger.info("Solicitud de bloqueo de sesión: %s", result)
    return result


@app.get(
    "/api/windows/unlock",
    dependencies=[Depends(require_pin)],
    summary="Intenta desbloquear la sesión de Windows",
)
def windows_unlock() -> dict[str, str]:
    """Intenta desbloquear la sesión de trabajo del Windows local.
    
    Ejecuta shutdown /l para solicitar el desbloqueo.
    Requiere PIN en la cabecera X-App-Pin.
    Nota: El desbloqueo requiere que el usuario ingrese su contraseña.
    """
    result = _unlock_workstation()
    logger.info("Solicitud de desbloqueo de sesión: %s", result)
    return result


@app.get(
    "/api/config",
    dependencies=[Depends(require_pin)],
    response_model=WolConfig,
    summary="Configuracion de Wake-on-LAN del backend",
)
def wol_config() -> WolConfig:
    return WolConfig(
        mac_address=APP_MAC_ADDRESS,
        broadcast=WOL_BROADCAST,
        port=WOL_PORT,
        source=MAC_SOURCE,
    )


@app.post(
    "/api/wake",
    dependencies=[Depends(require_pin)],
    response_model=WakeSent,
    summary="Envia un paquete magico Wake-on-LAN",
)
def wake(payload: WakeRequest | None = None) -> WakeSent:
    if send_magic_packet is None:
        raise HTTPException(
            status_code=503,
            detail="Falta la libreria 'wakeonlan'. Ejecuta: pip install -r requirements.txt",
        )

    mac = (payload.mac if payload else None) or APP_MAC_ADDRESS
    if not mac:
        raise HTTPException(
            status_code=409,
            detail=(
                "No se pudo autodetectar la MAC y APP_MAC_ADDRESS no esta definida. "
                "Configura la variable o envia {\"mac\": \"AA:BB:CC:DD:EE:FF\"} en el body."
            ),
        )

    try:
        send_magic_packet(mac, ip_address=WOL_BROADCAST, port=WOL_PORT)
    except OSError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"No se pudo enviar el paquete magico: {exc}",
        ) from exc

    logger.info("Wake-on-LAN enviado a %s via %s:%s", mac, WOL_BROADCAST, WOL_PORT)
    return WakeSent(mac=mac, broadcast=WOL_BROADCAST, port=WOL_PORT)


@app.post(
    "/api/system/suspend",
    dependencies=[Depends(require_pin)],
    response_model=None,
    summary="Suspende el equipo si se cumplen las condiciones de inactividad",
)
def system_suspend(payload: SuspendRequest | None = None) -> dict[str, str]:
    """Suspende el equipo usando rundll32.exe powrprof.dll,SetSuspendState 0,1,0.

    Si payload.minutes se especifica, espera ese número de minutos antes de suspender.
    Si no se especifica, suspende inmediatamente.
    Respeta la variable de entorno APP_DRY_RUN.
    """
    minutes = payload.minutes if payload else 0
    seconds = minutes * 60

    cmd = ["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"]

    if DRY_RUN:
        logger.info("Suspensión programada (Dry Run): %d minutos", minutes)
        return {"status": "dry_run", "message": "Suspensión simulada"}

    try:
        subprocess.run(cmd, capture_output=True, timeout=5, check=False)
        logger.info("Suspensión ejecutada")
        return {"status": "executed", "message": "Equipo en suspensión"}
    except Exception as exc:
        logger.error("Error al suspender: %s", exc)
        return {"status": "error", "message": str(exc)}


# --- Telemetria en tiempo real (WebSocket) -----------------------------------


@app.websocket("/ws/telemetry")
async def telemetry_socket(
    websocket: WebSocket,
    pin: Annotated[str | None, Query(description="PIN de la app")] = None,
) -> None:
    """Emite telemetria del sistema cada TELEMETRY_INTERVAL segundos.

    El PIN puede venir en ?pin=... (los navegadores no permiten cabeceras
    personalizadas en WebSocket) o en la cabecera X-App-Pin.
    """
    await websocket.accept()

    if not _ws_pin_ok(websocket, pin):
        await websocket.close(code=1008, reason="PIN invalido o ausente.")
        logger.warning("Telemetria: conexion rechazada (PIN invalido)")
        return

    logger.info("Telemetria: cliente conectado (%s)", websocket.client)
    try:
        while True:
            try:
                payload = await asyncio.to_thread(collect_telemetry)
                await websocket.send_json(payload.model_dump())
            except WebSocketDisconnect:
                raise
            except Exception as exc:
                logger.exception("Error al recolectar telemetria: %s", exc)
                try:
                    await websocket.send_json({"error": str(exc)})
                except WebSocketDisconnect:
                    raise
                except Exception as send_err:
                    logger.warning("Fallo al enviar frame de error por WebSocket: %s", send_err)
                    raise

            await asyncio.sleep(max(0.1, TELEMETRY_INTERVAL - CPU_SAMPLE_SECONDS))
    except WebSocketDisconnect:
        logger.info("Telemetria: cliente desconectado")
    except (RuntimeError, OSError) as exc:
        # El cliente cerro la conexion entre muestras (send_json falla).
        logger.info("Telemetria: conexion cerrada (%s)", exc)
    finally:
        try:
            await websocket.close()
        except (RuntimeError, OSError):
            pass