@echo off
chcp 65001 >nul 2>&1
title PC Power Remote - Arranque T-800

set "SCRIPT_DIR=%~dp0"

set "LAN_IP="
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /R /C:"IPv4"') do (
    set "cand=%%a"
    set "cand=%cand: =%"
    echo %cand% | findstr /V /R /C:"169\.254\." >nul 2>&1
    if errorlevel 0 if not defined LAN_IP set "LAN_IP=%cand%"
)
if not defined LAN_IP set "LAN_IP=localhost"

echo.
echo ===================================================
echo   INICIANDO SISTEMA T-800 (pc-power-remote)
echo ===================================================
echo.

echo [1/3] Arrancando Backend (FastAPI)...
start "T-800 BACKEND" cmd /k "cd /d "%SCRIPT_DIR%backend" && call run_backend.bat dev"

timeout /t 2 /nobreak >nul

echo [2/3] Arrancando Frontend (Vite)...
start "T-800 FRONTEND" cmd /k "cd /d "%SCRIPT_DIR%frontend" && npm run dev -- --host"

timeout /t 2 /nobreak >nul

echo [3/3] Arrancando Cloudflare Tunnel...
if exist "%SCRIPT_DIR%cloudflared.exe" (
    start "T-800 CLOUDFLARE TUNNEL" cmd /k "cd /d "%SCRIPT_DIR%" && call run_tunnel.bat"
) else (
    echo [ADVERTENCIA] No se encontro cloudflared.exe en la raiz.
)

echo.
echo ===================================================
echo   SISTEMA T-800 DESPLEGADO CON EXITO
echo ===================================================
echo   - Backend Local  : http://localhost:8000
echo   - Frontend Local : http://localhost:5173
echo   - Red Local      : http://%LAN_IP%:5173
echo   - Acceso Remoto  : Copia la URL de la ventana de Cloudflare
echo ===================================================
echo.
pause