@echo off
setlocal

REM ============================================================
REM  pc-power-remote - inicio rapido del frontend (Windows)
REM  - Instala dependencias npm si falta node_modules
REM  - Levanta Vite en 0.0.0.0:5173 (accesible desde el movil)
REM ============================================================

cd /d "%~dp0"

if not exist "node_modules" (
    echo [1/2] Instalando dependencias npm ...
    call npm install
    if errorlevel 1 (
        echo [ERROR] Fallo npm install. Verifica que Node.js 20+ este en el PATH.
        pause
        exit /b 1
    )
) else (
    echo [1/2] node_modules encontrado.
)

REM Detectar la IP local (IPv4), ignorando adaptadores APIPA (169.254.x).
set "LAN_IP="
for /f "tokens=2 delims=:" %%i in ('ipconfig ^| findstr /c:"IPv4" ^| findstr /v "169.254"') do set "LAN_IP=%%i"
if defined LAN_IP set "LAN_IP=%LAN_IP: =%"
if not defined LAN_IP set "LAN_IP=IP_DE_TU_PC"

echo.
echo [2/2] Iniciando Vite en http://0.0.0.0:5173
echo       IP local:  %LAN_IP%
echo       Local:     http://localhost:5173
echo       Red:       http://%LAN_IP%:5173
echo       Backend:   http://%LAN_IP%:8000
echo       Proxy:     /api  -^>  http://127.0.0.1:8000
echo.

call npm run dev

endlocal
pause
