@echo off
setlocal
chcp 65001 >nul 2>&1
title Backend FastAPI - PC Power Remote

REM ============================================================
REM  pc-power-remote - inicio rápido del backend (Windows)
REM  - Crea el entorno virtual .venv si no existe
REM  - Instala los requisitos si faltan
REM  - Levanta uvicorn en 0.0.0.0:8000
REM  - Uso: run_backend.bat [dev|prod]
REM ============================================================

cd /d "%~dp0"

set "MODE=%~1"
if "%MODE%"=="" set "MODE=%APP_MODE%"
if "%MODE%"=="" set "MODE=%APP_ENV%"
if "%MODE%"=="" set "MODE=dev"

if not exist ".venv\Scripts\python.exe" (
    echo [1/3] Creando entorno virtual .venv ...
    python -m venv .venv
    if errorlevel 1 (
        echo [ERROR] No se pudo crear el entorno virtual. Verifica que Python 3.10+ este en el PATH.
        pause
        exit /b 1
    )
) else (
    echo [1/3] Entorno virtual .venv encontrado.
)

set "PY=.venv\Scripts\python.exe"

REM Instalar dependencias solo si los paquetes clave no estan disponibles en el venv.
"%PY%" -c "import fastapi, uvicorn, pydantic, wakeonlan, psutil" >nul 2>&1
if errorlevel 1 (
    echo [2/3] Instalando dependencias de requirements.txt ...
    "%PY%" -m pip install --upgrade pip >nul
    "%PY%" -m pip install -r requirements.txt
    if errorlevel 1 (
        echo [ERROR] Fallo la instalacion de dependencias.
        pause
        exit /b 1
    )
) else (
    echo [2/3] Dependencias ya instaladas.
)

set "LAN_IP="
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /R /C:"IPv4"') do (
    set "cand=%%a"
    set "cand=%cand: =%"
    echo %cand% | findstr /V /R /C:"169\.254\." >nul 2>&1
    if errorlevel 0 if not defined LAN_IP set "LAN_IP=%cand%"
)
if not defined LAN_IP set "LAN_IP=localhost"

echo.
echo [3/3] Iniciando servidor en http://0.0.0.0:8000
echo       Entorno:   %MODE%
echo       Local:     http://localhost:8000
echo       Docs:      http://localhost:8000/docs
echo       Red Local: http://%LAN_IP%:8000
if "%APP_PIN%"=="" (
    echo       PIN:       134113 por defecto
) else (
    echo       PIN:       definido por variable APP_PIN
)
if "%APP_DRY_RUN%"=="1" echo       MODO:      APP_DRY_RUN activo - simulacion
echo.

if /i "%MODE%"=="prod" (
    echo Iniciando uvicorn en modo PRODUCCION (sin --reload)...
    "%PY%" -m uvicorn main:app --host 0.0.0.0 --port 8000
) else (
    echo Iniciando uvicorn en modo DESARROLLO (--reload en *.py)...
    "%PY%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload --reload-dir . --reload-include "*.py"
)

endlocal
pause
