@echo off
setlocal

REM ============================================================
REM  pc-power-remote - run_tunnel.bat
REM  Inicia un túnel Cloudflare seguro al backend local (puerto 8000)
REM ============================================================

REM --- Configuración ---
set TUNNEL_PORT=8000
set "CLOUDFLARED_NAME=cloudflared.exe"

REM --- 1. Validar existencia del binario ---
REM Usamos ruta absoluta basada en la ubicación del script (%~dp0)
REM Esto evita errores de expansión como "CLOUDFLARE_EXEI" o "No se esperaba I"
if not exist "%~dp0%CLOUDFLARED_NAME%" (
  echo.
  echo ERROR: No se encuentra %CLOUDFLARED_NAME% en la carpeta del script.
  echo.
  echo Ubicación esperada: %~dp0% CLOUDFLARED_NAME%
  echo.
  echo Solución: Coloca cloudflared.exe en la misma carpeta que este script,
  echo o descárgalo desde: https://github.com/cloudflare/cloudflared/releases/latest
  echo.
  pause
  exit /b 1
)

REM --- 2. Mostrar estado de validación ---
echo.
echo [1/3] Validando binario %CLOUDFLARED_NAME%...
echo %CLOUDFLARED_NAME% encontrado en: "%~dp0%CLOUDFLARED_NAME%"
echo.

REM --- 3. Iniciar túnel Cloudflare ---
echo [2/3] Iniciando túnel Cloudflare al backend local...
echo.

REM Asegurar carpetas necesarias
if not exist ".cloudflared" mkdir ".cloudflared"

REM Iniciar túnel apuntando al backend local (puerto 8000)
REM Usamos llamada directa y literal al binario sin variables intermedias
REM Usamos expansión segura sin espacios entre ruta y nombre: %~dp0%CLOUDFLARED_NAME%
"%~dp0%CLOUDFLARED_NAME%" tunnel --url http://localhost:%TUNNEL_PORT% --logfile ".cloudflared\cloudflared.log" run > "tunnel_output.txt" 2>&1 &

REM Esperar a que el tunnel genere inicio
timeout /t 15 >nul

REM --- 4. Mostrar URL pública ---
echo.
echo [3/3] Obteniendo URL pública...
echo.

for /f "usebacktokens=2 delims=:" %%A in ('findstr /i "trycloudflare" "tunnel_output.txt"') do (
  set "PUBLIC_URL=%%A"
  goto :show_url
)

echo No se encontro la URL automaticamente. Revisando el log...
type ".cloudflared\cloudflared.log" | find /i "trycloudflare"

:show_url
echo.
if defined PUBLIC_URL (
  echo.
  echo ============================================================
  echo  URL PUBLICA CLOUDFLARE:
  echo %PUBLIC_URL%
  echo ============================================================
  echo.
  echo Copia esta URL y comparta con quien necesite acceso remoto desde movil.
  echo El tunnel permanece activo mientras este script corra.
  echo.
) else (
  echo.
  echo No se pudo obtener la URL publica automaticamente.
  echo Revisa .cloudflared\cloudflared.log y tunnel_output.txt para detalles.
)

echo.
echo Tunnel activo en segundo plano.
echo Presiona Ctrl+C para detener o cierra esta ventana.
echo.

:loop
echo Presiona Ctrl+C para detener el tunnel o cierra esta ventana.
timeout /t 15 >nul
tasklist /FI "PID eq %TUNNEL_PID%" | find "%TUNNEL_PID%" >nul && goto :loop
echo Tunnel detenido.
endlocal