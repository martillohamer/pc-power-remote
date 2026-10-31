# pc-power-remote - System T-800

**Remote control of a Windows PC's state/energy from the local network (including mobile).**

**Version**: 0.6.0 | **Status**: 🟢 Production Ready | **Date**: October 2026

---

## 📖 Table of Contents

- [Project Overview](#-project-overview)
- [Architecture](#-architecture)
- [Quick Start (Windows)](#-quick-start-windows)
- [Manual Installation](#-manual-installation)
- [Environment Variables](#-environment-variables)
- [Wake-on-LAN Auto](#-wake-on-lan-auto)
- [Secure Tunnel (Cloudflare)](#-secure-tunnel-cloudflare-tunnel)
- [Endpoints](#-endpoints)
- [Real-time Telemetry](#-real-time-telemetry-fase-2)
- [Frontend](#-frontend)
- [Mobile Access](#-mobile-access)
- [Architecture Notes](#-architecture-notes)
- [Known Security Limits](#-known-security-limits)
- [Project Phases](#-project-phases)

---

## 🚀 Project Overview

`pc-power-remote` is a complete local API solution for remote PC control from mobile devices on the same local network. The system features a cyberpunk **T-800 aesthetic** interface implemented with **React + Tailwind CSS v4**, providing full power management, Wake-on-LAN, smart sleep diagnostics, voice commands, and forensic process monitoring.

The architecture comprises three tiers:

1. **Frontend** (React + Tailwind v4, port 5173) - User interface with cyberpunk aesthetics
2. **Backend** (FastAPI + Python, port 8000) - API with authentication, process control, and telemetry
3. **Cloudflare Tunnel** (cloudflared.exe v2026.10.7, local binary) - Secure external access without exposing ports

All **5 phases** are implemented:
- **Phase 1**: PIN / Auth authentication
- **Phase 2**: Wake-on-LAN (WOL)
- **Phase 3**: Cloudflare Tunnel
- **Phase 4.2**: Smart Sleep (automatic suspend)
- **Phase 4.3**: Voice Commands (Web Speech API `es-ES`)
- **Phase 4.4**: Forensic Diagnostics (Process & Crash)

---

## ⚡ Quick Start (Windows)

The fastest way to get everything running is using the master launcher:

```bat
iniciar_todo.bat
```

This single script launches **all services in parallel**:
- ✅ Backend FastAPI (port 8000)
- ✅ Frontend Vite (port 5173)
- ✅ Cloudflare Tunnel (to backend)

### Manual Step-by-Step

If you prefer to start each service independently:

#### 1. Backend FastAPI

```bat
cd backend
run_backend.bat
# or: call backend\run_backend.bat
```

#### 2. Frontend Vite

```bat
cd frontend
run_frontend.bat
# or: npm install && npm run dev
```

#### 3. Cloudflare Tunnel

```bat
run_tunnel.bat
```

The tunnel will start and display a public URL like `https://xyz.trycloudflare.com`. This URL already has the PIN embedded - no need to add the `X-App-Pin` header when accessing through it.

#### 4. Access the Interface

- **Frontend**: Open `http://127.0.0.1:5173` in your browser
- **API Docs**: Open `http://127.0.0.1:8000/docs`
- **Health Check**: `http://127.0.0.1:8000/api/health`

---

## 🛠️ Manual Installation

### Prerequisites

- **Windows** 10/11
- **Python** 3.10+
- **Node.js** 20+ (for frontend)
- **Cloudflare Tunnel** binary (`cloudflared.exe`) - included in project root

### Backend Setup

```bat
cd backend
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
set APP_PIN=134113  # Change default PIN for production
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Frontend Setup

```bat
cd frontend
npm install
npm run dev
```

### Tunnel Setup

Ensure `cloudflared.exe` exists in the project root (included). Then:

```bat
run_tunnel.bat
```

---

## 🌐 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_PIN` | `134113` | PIN required in `X-App-Pin` header. **Change before production** |
| `APP_DRY_RUN` | _(empty)_ | `1` = simulate shutdown without executing `shutdown.exe` (for testing) |
| `APP_MAC_ADDRESS` | _(autodetected)_ | MAC for WOL. If defined in real environment has priority; if missing, detected and saved to `.env` |
| `APP_WOL_BROADCAST` | `255.255.255.255` | Broadcast address for Wake-on-LAN packet |
| `APP_WOL_PORT` | `9` | UDP port for Wake-on-LAN |

---

## 🔓 Wake-on-LAN Auto

No need to manually write the MAC. On startup, the backend:

1. Reads `backend/.env` without overwriting existing variables
2. If `APP_MAC_ADDRESS` is defined in the **real environment**, uses it as-is
3. If not, detects the active NIC main:
   - **Windows**: `ipconfig /all`, crossing the default route IP with the adapter block and its *Physical Address*
   - Portable fallback: `uuid.getnode()` (discards if random MAC is returned)
4. Saves result to `backend/.env` as `APP_MAC_ADDRESS=AA:BB:CC:DD:EE:FF`
   (only rewrites if changed, to avoid infinite reloads with `--reload`)

The `/api/wake` endpoint works with a single click and no body needed. The terminal log confirms:

```
13:38:57 [INFO] Wake-on-LAN listo: MAC 34:5A:60:7E:14:B2 (origen: auto)
13:39:17 [INFO] Wake-on-LAN enviado a 34:5A:60:7E:14:B2 via 255.255.255.255:9
```

The frontend shows this MAC with the **AUTODETECTED** label. If the user saves a different MAC in the browser, that has priority for sends; the *Use backend's MAC* button clears it and returns to the autodetected one.

To force a different MAC (e.g., from a different PC), define `APP_MAC_ADDRESS` in the environment before starting; the `.env` will not overwrite it.

---

## 🛡️ Secure Tunnel (Cloudflare Tunnel)

To access the project from anywhere (mobile data, foreign Wi-Fi, etc.) without exposing ports 8000/5173 directly to the internet, use **Cloudflare Tunnel** (`cloudflared`).

The script `run_tunnel.bat` automates the entire process:

1. Detects or downloads `cloudflared`
2. Starts a secure tunnel pointing to the local frontend port (default `5173`)
3. Prints the public URL, e.g.: `https://xyz.trycloudflare.com`
4. That URL already has the PIN embedded - no need to add the `X-App-Pin` header manually when accessing through that domain
5. The tunnel remains active while the script runs; stop it with `Ctrl+C`

### Quick Usage

```bat
run_tunnel.bat
```

Copy the URL that appears and share it with whoever needs remote access. The tunnel will manage the encrypted connection and header routing.

### Tunnel Configuration

- **Binary**: `cloudflared.exe` v2026.10.7 (local, no system PATH required)
- **Port**: Points to backend local port 8000
- **Security**: LAN-local only; no registry modifications
- **Robustness**: Uses `%~dp0` absolute paths based on script location

---

## 📡 Endpoints

| Method | Route | Auth | Description |
|--------|-------|------|-------------|
| GET | `/` | — | Healthcheck: `{"status":"online","system":"Windows"}` |
| GET | `/api/health` | — | Same as `/`, for Vite proxy consumption |
| GET | `/api/state` | PIN | Timer state (`pending`, `seconds_left`) |
| POST | `/api/shutdown` | PIN | Body `{"minutes": int}` (1-1440) → `shutdown /s /t N` |
| POST | `/api/cancel` | PIN | `shutdown /a` |
| GET | `/api/config` | PIN | MAC/broadcast/puerto WOL + `source` (`auto`, `env`, `env-file`, `none`) |
| POST | `/api/wake` | PIN | Sends a Wake-on-LAN magic packet |
| WS | `/ws/telemetry` | PIN (query `?pin=` or header) | Live telemetry every 1.5 s |
| GET | `/docs` | — | Swagger UI (try with *Authorize* button) |

**Mandatory header**: `X-App-Pin`. Without it or with an incorrect value the API responds `401`.

### Example curl calls

```bat
curl -X POST http://localhost:8000/api/shutdown ^
  -H "X-App-Pin: 134113" -H "Content-Type: application/json" ^
  -d "{"minutes": 15}"

curl -X POST http://localhost:8000/api/cancel -H "X-App-Pin: 134113"

curl -X POST http://localhost:8000/api/wake -H "X-App-Pin: 134113"

curl -X POST http://localhost:8000/api/wake ^
  -H "X-App-Pin: 134113" -H "Content-Type: application/json" ^
  -d "{"mac": "AA:BB:CC:DD:EE:FF"}"
```

### Wake-on-LAN responses

- `200` with `{mac, broadcast, port}`
- `401` without valid PIN
- `409` if no MAC configured
- `422` if MAC is invalid
- `503` if `wakeonlan` library is missing

---

## 📊 Real-time Telemetry (Phase 2)

The backend opens `WS /ws/telemetry` and emits a sample every **1.5 s**. The PIN is validated by `?pin=...` (browsers don't allow custom headers in WebSocket) or by the `X-App-Pin` header; if invalid the socket closes with code **1008**.

Each frame is exactly:

```json
{
  "cpu_usage": 12.4,
  "ram_usage": 87.5,
  "ram_used_mb": 12453.4,
  "ram_total_mb": 14229.1,
  "disk_usage": 58.9,
  "uptime_seconds": 1228
}
```

- Collection (`psutil`) runs with `asyncio.to_thread`, so the event loop never blocks
- Disconnections are captured with `WebSocketDisconnect`
- Last sample is preserved and reused during reconnection with exponential backoff (1.5 s → 8 s)

Quick Python test:

```python
import asyncio, json, websockets

async def main():
    async with websockets.connect("ws://localhost:8000/ws/telemetry?pin=134113") as ws:
        print(json.loads(await ws.recv()))

asyncio.run(main())
```

---

## 🎨 Frontend

- **Default PIN** `134113` (`DEFAULT_PIN` in `App.jsx`): if `localStorage` doesn't have a saved PIN, this value is sown, so the app works without manual configuration. Sent as `X-App-Pin` in every call; if the backend rejects it (`401`), it's cleared and the modal is shown to ask for the correct one.
- Quick buttons: 5, 15, 30, 60 and 90 minutes, with prior confirmation
- Live countdown (synchronized with `/api/state` every 10 s) and prominent **Cancel Shutdown** button
- Success/error notifications and connection status (online/offline)
- **Wake-on-LAN** card with prominent **Turn On PC** button. MAC can be edited in a modal (`MAC · edit`), saved to `localStorage` (`pc-power-remote.mac`) and automatically formatted to `AA:BB:CC:DD:EE:FF`.
- If no local MAC exists, the **autodetected** one is used (label *AUTODETECTED*); if that doesn't exist either, the API responds `409` and the modal opens
- **System Telemetry Panel** (`TelemetryPanel.jsx`): connects to WebSocket on authentication and shows CPU, RAM (% and GB) and disk with dynamic bars, uptime and the **LIVE TELEMETRY / RECONNECTING** indicator

### Frontend Components

| Component | Description |
|-----------|-------------|
| `App.jsx` | Main integration - all phases, VoiceCommandButton, ForensicPanel |
| `TelemetryPanel.jsx` | CPU/RAM/Disk real-time bars with live indicators |
| `VoiceCommandButton.jsx` | Web Speech API Spanish commands (apagar, estado, suspender, etc.) |
| `ForensicPanel.jsx` | Process/top 10 consumers and critical events log |
| `PinModal.jsx` | PIN authentication modal |
| `MacModal.jsx` | MAC address editing for WOL |

---

## 📱 Mobile Access

1. `ipconfig` → note your PC's IPv4 (e.g. `192.168.0.42`)
2. Both devices on the same Wi-Fi network
3. Open `http://192.168.0.42:5173` (frontend) or `http://192.168.0.42:8000/docs` (API)
4. If it doesn't load, allow Python/Node in Windows Firewall for private networks

---

## 🏗️ Architecture Notes

### Authentication

- Single `require_pin` Dependency validates `X-App-Pin` against `APP_PIN` with `hmac.compare_digest` (constant-time comparison). Applied per endpoint with `dependencies=[Depends(require_pin)]`; `GET /` remains public.
- WebSocket reuses the same comparison via `_ws_pin_ok` (query or header) and closes with `1008` if the PIN doesn't match.

### Timer State

- Stored in memory (protected by `threading.Lock`), not in OS. `shutdown /a` is the source of truth: if Windows responds "no pending shutdown" (code 1116) return `409` and clean state.

### OS Errors

- `FileNotFoundError`, `TimeoutExpired`, `OSError` and non-zero exit codes are translated to `HTTPException` with the original `shutdown.exe` message (decoded from cp850, Windows Spanish encoding).

### Local IP in Console

On startup, the backend detects the IPv4 of the default route using a UDP socket (without sending traffic) and prints it along with ports `8000` (API) and `5173` (Vite). The `.bat` scripts do the same with `ipconfig`.

### CORS

The backend allows any origin because the frontend in dev runs on another port. In production, restrict `allow_origins`.

### Wake-on-LAN

On startup, `_resolve_mac()` applies priority: `APP_MAC_ADDRESS` real → autodetection (`ipconfig /all` + `uuid.getnode()`) → `.env`. The detected MAC persists in `backend/.env` without touching other keys.

`POST /api/wake` normalizes the MAC (accepts `-`, `:` or no separators) and calls `wakeonlan.send_magic_packet(mac, ip_address=APP_WOL_BROADCAST, port=APP_WOL_PORT)`. The send is UDP broadcast: the target PC doesn't need to be powered on, but the backend must keep running (or run on another PC to wake a third one). In BIOS/UEFI and the network adapter, *Wake on Magic Packet* / *Wake on LAN* must be enabled.

### Vite Proxy

The frontend calls `/api/*` and `/ws/*`; Vite forwards them without rewriting to `127.0.0.1:8000` (the backend already exposes its routes under `/api` and `/ws`, and the proxy uses `ws: true` for WebSocket). So the mobile browser never needs to know the backend IP and there's no CORS issue. With `API_TARGET=http://127.0.0.1:8010 npm run dev` you can point to another port.

### Tailwind v4

Doesn't require `tailwind.config.js`; the theme is declared in `src/index.css` with `@theme` and activated with the `@tailwindcss/vite` plugin.

---

## ⚠️ Known Security Limits

- The PIN travels in plain text over HTTP and is stored in `localStorage`: anyone with local network access could intercept it. For real use, publish the backend behind HTTPS (Tailscale, Caddy, Cloudflare Tunnel) and don't expose it to the Internet.
- No attempt limit: add rate limiting (e.g. `slowapi`) if the machine is on a shared network.
- `shutdown /s /t N` only schedules shutdown; there are no restart or suspend endpoints yet (though Fase 4.2 implements smart suspend automatically).

---

## 📦 Project Phases

| Phase | Description | Status |
|-------|-------------|--------|
| **1** | PIN / Auth authentication | ✅ Complete |
| **2** | Wake-on-LAN (WOL) | ✅ Complete |
| **3** | Cloudflare Tunnel | ✅ Complete |
| **4.2** | Smart Sleep (automatic suspend) | ✅ Complete |
| **4.3** | Voice Commands (Web Speech API `es-ES`) | ✅ Complete |
| **4.4** | Forensic Diagnostics (Process & Crash) | ✅ Complete |

**All phases implemented and tested. Project version 0.6.0.**

---

## 📦 Dependencies

### Backend (`backend/requirements.txt`)

```
fastapi>=0.109.0
uvicorn[standard]>=0.27.0
psutil>=5.9.0
python-multipart>=0.0.1
pydantic>=2.5.0
wakeonlan>=3.1.0
```

### Frontend (`frontend/package.json`)

```
react@18.0.0
react-dom@18.0.0
tailwindcss@4.0.0
```

---

## 👥 Support & Maintenance

### Common Issues

1. **PIN authentication failed** - Verify `APP_PIN` in `.env` and `X-App-Pin` header
2. **Cloudflare tunnel not starting** - Ensure `cloudflared.exe` is in project root
3. **Backend not responding** - Check COM port/MAC address detection
4. **Frontend not loading** - Verify Vite dev server on port 5173

### Backup & Recovery

- PIN stored in `backend/.env`
- MAC address auto-detected and saved
- Telemetry data in WebSocket streams
- Tunnel logs in `.cloudflared\cloudflared.log`

### Update Procedure

1. Pull latest changes: `git pull`
2. Reinstall dependencies: `cd backend && python -m pip install -r requirements.txt`
3. Rebuild frontend: `cd frontend && npm run build`
4. Restart services: `iniciar_todo.bat`

---

## 📞 Contact

- **Project**: pc-power-remote - System T-800
- **Version**: 0.6.0
- **Date**: October 2026
- **Status**: Production Ready / Complete

---

*This project implements 6 phases of development: PIN/auth (1), WOL (2), Cloudflare Tunnel (3), Smart Sleep (4.2), Voice Commands (4.3), and Forensic Diagnostics (4.4). All phases are complete and the system is production-ready.*

---

*Generated as part of the official project closure and handoff process. Documentation updated October 2026.*