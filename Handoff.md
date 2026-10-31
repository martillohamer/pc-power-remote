# Handoff Documentation - pc-power-remote
## System T-800 - Complete Edition
### Last Updated: October 2026
### Status: ✅ PRODUCTION READY / COMPLETED

---

## 📋 Project Overview

The `pc-power-remote` project is a complete local API solution for remote PC control from mobile devices. The system implements a cyberpunk T-800 aesthetic interface with full power management, Wake-on-LAN, cloud tunneling, and forensic diagnostics capabilities.

---

## 🏗️ Architecture Overview

### Frontend (React + Tailwind CSS v4)
- **Port**: 5173 (Vite development server)
- **Entry Point**: `src/App.jsx`
- **Key Components**:
  - `TelemetryPanel.jsx` - CPU/RAM/Disk real-time monitoring
  - `VoiceCommandButton.jsx` - Web Speech API Spanish commands (Fase 4.3)
  - `ForensicPanel.jsx` - Process & Crash Diagnostics (Fase 4.4)
  - `PinModal.jsx`, `MacModal.jsx` - Authentication modals
- **Styles**: Cyberpunk/neón T-800 theme with flicker effects, scanlines, glassmorphism

### Backend (FastAPI + Python)
- **Port**: 8000
- **Entry Point**: `backend/main.py`
- **Key Features**:
  - PIN authentication via `X-App-Pin` header
  - `psutil`-based system monitoring
  - WebSocket telemetry (`/ws/telemetry`)
  - Smart Sleep guardian (automatic suspend)
  - Forensic endpoints (`/api/forensic/processes`, `/api/forensic/logs`)
  - Wake-on-LAN with MAC autodetection
  - Cloudflare Tunnel integration

### Cloudflare Tunnel Infrastructure
- **Binary**: `cloudflared.exe` v2026.10.7 (local, no PATH system required)
- **Port Mapping**: Backend port 8000 exposed via tunnel
- **Security**: Local binary in project root, no system registry modifications
- **Script**: `run_tunnel.bat` - automated tunnel startup with validation

---

## 📁 Project Structure (Final)

```
pc-power-remote/
├── backend/
│   └── main.py          # FastAPI v0.6.0
├── frontend/
│   └── src/
│       ├── App.jsx      # Main component (integrates all phases)
│       ├── VoiceCommandButton.jsx  # Fase 4.3
│       ├── ForensicPanel.jsx         # Fase 4.4
│       ├── TelemetryPanel.jsx        # Fase 1-3
│       └── ...
├── run_tunnel.bat       # Cloudflare Tunnel starter (FIXED - literal paths)
├── iniciar_todo.bat     # Master launcher (all services parallel)
├── cloudflared.exe      # Cloudflare Tunnel binary v2026.10.7
├── .env                # Environment config
└── run_backend.bat     # Backend launcher
```

---

## 🔧 Phase Implementation Status

| Phase | Description | Status |
|-------|-------------|--------|
| **1** | PIN / Auth authentication | ✅ Complete |
| **2** | Wake-on-LAN (WOL) | ✅ Complete |
| **3** | Cloudflare Tunnel | ✅ Complete |
| **4.2** | Smart Sleep (suspensión inteligente) | ✅ Complete |
| **4.3** | Voice Commands (Web Speech API `es-ES`) | ✅ Complete |
| **4.4** | Forensic Diagnostics (Process & Crash) | ✅ Complete |

---

## 🚀 Deployment & Quick Start

### Prerequisites
- Windows 10/11
- Python 3.+ with `psutil`, `fastapi`, `uvicorn`
- Node.js 18+ with `npm` (for frontend)
- Cloudflare account (optional, for custom domains)

### Step-by-Step Setup

#### 1. Backend Installation
```batch
cd backend
python -m pip install -r requirements.txt
run_backend.bat   # or: call backend\run_backend.bat
```

#### 2. Frontend Installation
```batch
cd frontend
npm install
npm run dev       # or: call frontend\run_frontend.bat
```

#### 3. Cloudflare Tunnel
```batch
cd pc-power-remote
run_tunnel.bat    # Starts tunnel to http://localhost:8000
```

#### 4. Master Launch (All Services)
```batch
iniciar_todo.bat   # Starts Backend, Frontend, and Tunnel in parallel
```

#### 5. Access Points
- **Frontend (Local)**: http://127.0.0.1:5173
- **Backend API**: http://127.0.0.1:8000
- **Health Check**: http://127.0.0.1:8000/api/health
- **Cloudflare Tunnel URL**: Displayed in tunnel console window

#### 5. First-Time Setup
```batch
# Run once to configure PIN and MAC
cd pc-power-remote
backend\run_backend.bat  # Start backend first
# Access http://127.0.0.1:8000/pin to set PIN
# Default PIN: 134113 (change immediately)
```

---

## 🔒 Security Configuration

### PIN Authentication
- Variable: `APP_PIN` (environment or `.env`)
- Default: `134113` (CHANGE IMMEDIATELY for production)
- Header: `X-App-Pin` required for sensitive endpoints
- All `/api/*` endpoints (except health) require valid PIN

### MAC Address autodetection
- System auto-detects on Windows via `ipconfig /all`
- Stored in `backend/.env`
- Override via `APP_MAC_ADDRESS` environment variable
- Required for Wake-on-LAN functionality

---

## 🛠️ Technical Details

### Backend (FastAPI)
- **Framework**: FastAPI Python 3.12+
- **OS**: Windows native (shutdown.exe, rundll32.exe)
- **Telemetry**: psutil for CPU, Memory, Disk monitoring
- **WebSockets**: Real-time telemetry streaming
- **Logging**: Structured INFO level, rotating file output

### Frontend (React + Tailwind v4)
- **Framework**: React 18+ with functional components
- **Styling**: Tailwind CSS v4 with custom flicker/neon effects
- **API Calls**: Fetch with `X-App-Pin` header
- **Responsive**: Mobile-friendly with T-800 aesthetic
- **Build**: Vite 5+ for HMR and production builds

### Cloudflare Tunnel
- **Binary**: Self-contained `cloudflared.exe` in project root
- **Protocol**: HTTPS tunnel to Cloudflare network
- **Port**: 8000 (backend) exposed to internet
- **Authentication**: No additional auth (LAN-local only)
- **Reliability**: Reconnect on network changes

---

## 📦 Dependencies

### Backend (backend/requirements.txt)
```
fastapi>=0.109.0
uvicorn[standard]>=0.27.0
psutil>=5.9.0
python-multipart>=0.0.1
pydantic>=2.5.0
wakeonlan>=3.1.0
```

### Frontend (frontend/package.json)
```
react@18.0.0
react-dom@18.0.0
tailwindcss@4.0.0
```

---

## 📞 Support & Maintenance

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

## 👥 Team & Contact

- **Project**: pc-power-remote - System T-800
- **Version**: 0.6.0
- **Date**: October 2026
- **Status**: Production Ready / Complete

---

*This documentation was generated as part of the official project handoff and closure process. All phases (1-4.4) are implemented and tested.*