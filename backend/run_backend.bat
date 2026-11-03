@echo off
setlocal
chcp 65001 >nul 2>&1
title Backend FastAPI - PC Power Remote

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [1/3] Creando entorno virtual .venv ...
    python -m venv .venv
    if errorlevel 1 (
        echo [ERROR] No se pudo crear el entorno virtual.
        pause
        exit /b 1
    )
) else (
    echo [1/3] Entorno virtual .venv encontrado.
)

set "PY=.venv\Scripts\python.exe"

"%PY%" -c "import fastapi, uvicorn, pydantic, wakeonlan, psutil" >nul 2>&1
if errorlevel 1 (
    echo [2/3] Instalando dependencias...
    "%PY%" -m pip install --upgrade pip >nul
    "%PY%" -m pip install -r requirements.txt
) else (
    echo [2/3] Dependencias ya instaladas.
)

echo.
set "MODE=%1"
if "%MODE%"=="" set "MODE=dev"

if /i "%MODE%"=="prod" (
    echo [3/3] Iniciando servidor en produccion (sin reload) en http://0.0.0.0:8000
    "%PY%" -m uvicorn main:app --host 0.0.0.0 --port 8000
) else (
    echo [3/3] Iniciando servidor en desarrollo (con reload) en http://0.0.0.0:8000
    "%PY%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload --reload-dir . --reload-include "*.py"
)
endlocal
pause
