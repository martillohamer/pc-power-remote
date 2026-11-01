@echo off
setlocal
chcp 65001 >nul 2>&1
title Cloudflare Tunnel — PC Power Remote

REM ============================================================
REM  pc-power-remote - run_tunnel.bat
REM  Inicia un túnel Cloudflare Quick Tunnel hacia Vite (:5173)
REM  (con proxy transparente al backend :8000 en /api y /ws)
REM ============================================================

set "SCRIPT_DIR=%~dp0"
set "CLOUDFLARED_EXE=%SCRIPT_DIR%cloudflared.exe"
set "TARGET_PORT=5173"
set "LOG_DIR=%SCRIPT_DIR%.cloudflared"
set "LOG_FILE=%LOG_DIR%\cloudflared.log"
set "OUTPUT_FILE=%SCRIPT_DIR%tunnel_output.txt"

echo.
echo ============================================================
echo   Iniciando túnel Cloudflare Quick Tunnel...
echo ============================================================
echo.

REM --- 1. Validar binario cloudflared.exe ---
if not exist "%CLOUDFLARED_EXE%" (
    echo [ERROR] No se encontró cloudflared.exe en "%SCRIPT_DIR%".
    echo Descárgalo desde: https://github.com/cloudflare/cloudflared/releases/latest
    echo.
    pause
    exit /b 1
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if exist "%OUTPUT_FILE%" del /f /q "%OUTPUT_FILE%" >nul 2>&1

echo Exponiendo http://localhost:%TARGET_PORT% a Internet...
echo (La URL pública aparecerá a continuación sin filtros que bloqueen la consola)
echo.

REM --- 2. Ejecutar cloudflared de forma limpia ---
REM La sintaxis correcta para Quick Tunnel es:
REM cloudflared.exe tunnel --url http://localhost:PORT --logfile PATH
REM y redirigir stderr a stdout para visualización y logging.
"%CLOUDFLARED_EXE%" tunnel --url http://localhost:%TARGET_PORT% --logfile "%LOG_FILE%"

echo.
echo ============================================================
echo   El túnel Cloudflare se ha cerrado.
echo ============================================================
echo.
pause
endlocal