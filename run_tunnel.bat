@echo off
setlocal

REM ============================================================
REM  pc-power-remote - run_tunnel.bat
REM  Inicia un túnel Cloudflare seguro al frontend (puerto 5173)
REM ============================================================

REM --- Configuración ---
set TUNNEL_PORT=5173
set "CLOUDFLARED_EXE=cloudflared"
set "CLOUDFLARED_URL=https://developers.cloudflare.com/cloudflared/download"

REM --- 1. Detectar cloudflared ---
echo [1/4] Buscando %CLOUDFLARED_EXE%...

REM Busca en PATH del sistema usando el nombre directamente
set "CLOUDFLARED_PATH="
for /f "tokens=*" %I in ('where cloudflared.exe 2^>nul') do set "CLOUDFLARED_PATH=%I"

REM Si no está en PATH, intentar con nombre fijo en la misma carpeta que este script
if not defined CLOUDFLARED_PATH (
  if exist "%~dp0cloudflared.exe" (
    set "CLOUDFLARED_PATH=%~dp0cloudflared.exe"
  )
)

REM Si aún no se encuentra, descargar la última versión stable
if not defined CLOUDFLARED_PATH (
  echo %CLOUDFLARED_EXE% no encontrado en PATH ni en la carpeta del script.
  echo Descargando desde %CLOUDFLARED_URL%...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "
    $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
    $out = '%~dp0.cloudflared\cloudflared.exe'
    if (-not (Test-Path (Split-Path $out))) { mkdir (Split-Path $out) }
    try {
      Invoke-WebRequest -Uri $url -OutFile $out
      write-host 'Descarga completada' -ForegroundColor Green
    } catch {
      write-host 'Fallo al descargar' -ForegroundColor Red
      exit /b 1
    }
  "
  if exist "%~dp0.cloudflared\cloudflared.exe" (
    set "CLOUDFLARED_PATH=%~dp0.cloudflared\cloudflared.exe"
  ) else (
    echo.
    echo No se pudo descargar %CLOUDFLARED_EXE% automáticamente.
    echo Por favor descarga manualmente:
    echo   %CLOUDFLARED_URL%
    echo y coloca %CLOUDFLARED_EXE%.exe en el PATH o en la misma carpeta que este script.
    pause
    exit /b 1
  )
)

REM Mostrar resultado (usando comillas para protección)
echo %CLOUDFLARED_EXE% encontrado en: "%CLOUDFLARED_PATH%"

REM --- 2. Verificar que el backend y frontend estén corriendo ---
echo.
echo [2/4] Verificando conexiones locales...

if not exist ".\backend\run_backend.bat" (
  echo ERROR: No encuentra backend\run_backend.bat
  pause
  exit /b 1
)
if not exist ".\frontend\run_frontend.bat" (
  echo ERROR: No encuentra frontend\run_frontend.bat
  pause
  exit /b 1
)

REM Verificar que el backend responde
echo Verificando que el backend este accesible en http://127.0.0.1:%TUNNEL_PORT%...

REM --- 3. Iniciar túnel ---
echo.
echo [3/4] Iniciando túnel Cloudflare...

REM Asegurar carpetas necesarias
if not exist ".cloudflared" mkdir ".cloudflared"

REM Iniciar túnel apuntando al frontend local, salida a archivo de log y URL temporal
echo Iniciando tunnel... (esto puede tardar unos segundos)
%CLOUDFLARED_PATH% tunnel --url http://localhost:%TUNNEL_PORT% --logfile ".cloudflared\cloudflared.log" run > "tunnel_output.txt" 2>&1 &

REM Esperar a que el tunnel genere la URL
timeout /t 10 >nul

REM --- 4. Mostrar URL pública ---
echo.
echo [4/4] Obteniendo URL pública...

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
echo Presiona Ctrl+C para detener el tunnel o cierra esta ventana.
echo.

:loop
echo Presiona Ctrl+C para detener el tunnel o cierra esta ventana.
timeout /t 15 >nul
tasklist /FI "PID eq %TUNNEL_PID%" | find "%TUNNEL_PID%" >nul && goto :loop
echo Tunnel detenido.
endlocal