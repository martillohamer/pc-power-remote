@echo off
setlocal

REM ============================================================
REM  pc-power-remote - inicio rapido del backend (Windows)
REM  - Crea el entorno virtual .venv si no existe
REM  - Instala los requisitos si faltan
REM  - Levanta uvicorn en 0.0.0.0:8000 (accesible desde el movil)
REM ============================================================

cd /d "%~dp0"

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

REM Detectar la IP local (IPv4), ignorando adaptadores APIPA (169.254.x).
set "LAN_IP="
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4" ^| findstr /v "169.254"') do set "LAN_IP=%%i"
if defined LAN_IP set "LAN_IP=%LAN_IP: =%"
if not defined LAN_IP set "LAN_IP=IP_DE_TU_PC"

echo.
echo [3/3] Iniciando servidor en http://0.0.0.0:8000
echo       IP local:  %LAN_IP%
echo       Backend:   http://%LAN_IP%:8000
echo       Docs:      http://%LAN_IP%:8000/docs
echo       Frontend:  http://%LAN_IP%:5173  (run_frontend.bat)
if "%APP_PIN%"=="" (
    echo       PIN:       134113 por defecto - define APP_PIN para cambiarlo
) else (
    echo       PIN:       tomado de la variable APP_PIN
)
if "%APP_DRY_RUN%"=="1" echo       MODO:      APP_DRY_RUN activo - no se apaga el equipo
echo.

"%PY%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload

endlocal
pause
