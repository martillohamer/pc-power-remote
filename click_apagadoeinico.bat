@echo off
setlocal
chcp 65001 >nul 2>&1
title T-800 Cyberdyne Launcher - pc-power-remote
color 0A

REM ================================================================
REM           INICIANDO SISTEMA T-800 (pc-power-remote)             
REM ================================================================

set "SCRIPT_DIR=%~dp0"

echo ================================================================
echo           INICIANDO SISTEMA T-800 (pc-power-remote)             
echo ================================================================
echo.

:: 1. Iniciar Backend (FastAPI :8000)
echo [1/3] Arrancando Backend (FastAPI :8000)...
start "T-800 BACKEND" cmd /k "cd /d "%SCRIPT_DIR%backend" && call run_backend.bat"
timeout /t 3 /nobreak >nul

:: 2. Iniciar Frontend (Vite :5173)
echo [2/3] Arrancando Frontend (Vite :5173)...
start "T-800 FRONTEND" cmd /k "cd /d "%SCRIPT_DIR%frontend" && call run_frontend.bat"
timeout /t 3 /nobreak >nul

:: 3. Iniciar Cloudflare Tunnel
echo [3/3] Abriendo Túnel Seguro Cloudflare...
if exist "%SCRIPT_DIR%cloudflared.exe" (
    start "T-800 CLOUDFLARE TUNNEL" cmd /k "cd /d "%SCRIPT_DIR%" && call run_tunnel.bat"
) else (
    echo [ADVERTENCIA] No se encontró cloudflared.exe en la raíz.
)

echo.
echo ================================================================
echo  ¡SISTEMA T-800 DESPLEGADO CON ÉXITO!
echo ================================================================
echo  - Frontend Local     : http://localhost:5173
echo  - Backend Local      : http://localhost:8000
echo  - Red Local (PC)     : http://192.168.1.129:5173
echo  - Móvil / Remoto     : Copia la URL https://*.trycloudflare.com
echo                         de la ventana de Cloudflare Tunnel.
echo ================================================================
echo.
pause
endlocal