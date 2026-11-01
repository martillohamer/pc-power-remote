@echo off
setlocal
chcp 65001 >nul 2>&1
title Frontend Vite - PC Power Remote

REM ============================================================
REM  pc-power-remote - inicio rapido del frontend (Windows)
REM  - Instala dependencias npm si falta node_modules
REM  - Levanta Vite en 0.0.0.0:5173 (accesible desde LAN/movil)
REM ============================================================

cd /d "%~dp0"

if not exist "node_modules" (
    echo [1/2] Instalando dependencias npm ...
    call npm install
    if errorlevel 1 (
        echo [ERROR] Fallo npm install. Verifica que Node.js este en el PATH.
        pause
        exit /b 1
    )
) else (
    echo [1/2] node_modules encontrado.
)

set "LAN_IP=192.168.1.129"

echo.
echo [2/2] Iniciando Vite en http://0.0.0.0:5173
echo       Local:     http://localhost:5173
echo       Red Local: http://%LAN_IP%:5173
echo       Proxy API: http://127.0.0.1:8000
echo.

call npm run dev

endlocal
pause
