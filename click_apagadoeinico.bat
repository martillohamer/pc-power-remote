@echo off
title T-800 Cyberdyne Launcher - pc-power-remote
color 0A

echo ================================================================
echo           INICIANDO SISTEMA T-800 (pc-power-remote)             
echo ================================================================
echo.

:: 1. Iniciar Backend (FastAPI :8000) usando el entorno virtual si existe
echo [1/3] Arrancando Backend (FastAPI)...
if exist venv\Scripts\activate.bat (
    start "T-800 BACKEND" cmd /k "call venv\Scripts\activate.bat && python -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000"
) else (
    start "T-800 BACKEND" cmd /k "python -m uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000"
)

:: Esperar 2 segundos para estabilizar el backend
timeout /t 2 /nobreak >nul

:: 2. Iniciar Frontend (Vite :5173) entrando a la carpeta frontend
echo [2/3] Arrancando Frontend (Vite)...
start "T-800 FRONTEND" cmd /k "cd frontend && npm run dev -- --host"

:: Esperar 3 segundos para estabilizar Vite
timeout /t 3 /nobreak >nul

:: 3. Iniciar Cloudflare Tunnel usando run_tunnel.bat de la raíz
echo [3/3] Abriendo Túnel Seguro Cloudflare...
start "T-800 CLOUDFLARE TUNNEL" cmd /k "call run_tunnel.bat"

echo.
echo ================================================================
echo  ¡SISTEMA T-800 DESPLEGADO CON ÉXITO!
echo ================================================================
echo  - Frontend Local     : http://localhost:5173
echo  - Backend Local      : http://localhost:8000
echo  - Móvil / Remoto     : Copia la URL https://*.trycloudflare.com
echo                         de la ventana de Cloudflare Tunnel.
echo ================================================================
echo.
pause