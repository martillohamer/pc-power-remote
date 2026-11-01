@echo off
setlocal
chcp 65001 >nul 2>&1
title Cloudflare Tunnel - PC Power Remote

REM ============================================================
REM  pc-power-remote - run_tunnel.bat
REM  Inicia un tunel Cloudflare Quick Tunnel hacia Vite
REM  (con proxy transparente al backend en /api y /ws)
REM ============================================================

set "SCRIPT_DIR=%~dp0"
set "CLOUDFLARED_EXE=%SCRIPT_DIR%cloudflared.exe"
if "%~1"=="" (set "TARGET_PORT=5173") else (set "TARGET_PORT=%~1")
set "LOG_DIR=%SCRIPT_DIR%.cloudflared"
set "LOG_FILE=%LOG_DIR%\cloudflared.log"
set "OUTPUT_FILE=%SCRIPT_DIR%tunnel_output.txt"

echo.
echo ============================================================
echo   Iniciando tunel Cloudflare Quick Tunnel...
echo ============================================================
echo.

REM --- 1. Validar binario cloudflared.exe ---
if not exist "%CLOUDFLARED_EXE%" (
    echo [ERROR] No se encontro cloudflared.exe en "%SCRIPT_DIR%".
    echo Descargalo desde: https://github.com/cloudflare/cloudflared/releases/latest
    echo.
    pause
    exit /b 1
)

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if exist "%OUTPUT_FILE%" del /f /q "%OUTPUT_FILE%" >nul 2>&1

REM Borrar el log de cloudflared ANTES de lanzarlo para no leer URLs viejas
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%" >nul 2>&1

REM Lanzar el detector de URL del tunel en segundo plano
start "" /b powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tunnel_url.ps1"

echo Exponiendo http://127.0.0.1:%TARGET_PORT% a Internet...
echo (La URL publica aparecera en la ventana del detector de URL)
echo.

REM --- 2. Ejecutar cloudflared de forma limpia ---
REM La sintaxis correcta para Quick Tunnel es:
REM cloudflared.exe tunnel --url http://127.0.0.1:PORT --no-autoupdate --logfile PATH
"%CLOUDFLARED_EXE%" tunnel --url http://127.0.0.1:%TARGET_PORT% --no-autoupdate --logfile "%LOG_FILE%"

echo.
echo ============================================================
echo   El tunel Cloudflare se ha cerrado.
echo ============================================================
echo.
pause
endlocal
