@echo off
setlocal

REM ============================================================
REM  pc-power-remote - iniciar_todo.bat
REM  Arranca en paralelo: Backend, Frontend y Cloudflare Tunnel
REM ============================================================

REM --- Configuración de Rutas Seguras ---
REM Usamos %~dp0 para referenciar siempre la carpeta donde está este script
SET SCRIPT_DIR=%~dp0

REM --- Puerto Configuración ---
set BACKEND_PORT=8000
set FRONTEND_PORT=5173

REM --- 1. Arrancar Backend FastAPI en ventana independiente ---
echo.
echo ==========================================
echo  INICIANDO BACKEND FASTAPI
echo ==========================================
echo.
echo Ubicación: %SCRIPT_DIR%backend\run_backend.bat
echo Puerto: %BACKEND_PORT%
echo.

start /B /WANAKA "Backend FastAPI" cmd /c "cd /d "%SCRIPT_DIR%" && call backend\run_backend.bat"

REM Espera breve para permitir que el backend inicie
timeout /t 3 >nul

REM --- 2. Arrancar Frontend Vite en ventana independiente ---
echo.
echo ==========================================
echo  INICIANDO FRONTEND VITE
echo ==========================================
echo.
echo Ubicación: %SCRIPT_DIR%frontend
echo Puerto: %FRONTEND_PORT%
echo.

start /B /WANAKA "Frontend Vite" cmd /c "cd /d "%SCRIPT_DIR%frontend" && npm run dev"

REM Espera breve para permitir que el frontend inicie
timeout /t 5 >nul

REM --- 3. Arrancar Cloudflare Tunnel en ventana independiente ---
echo.
echo ==========================================
echo  INICIANDO CLOUDFLARE TUNNEL
echo ==========================================
echo.
echo Ubicación: %SCRIPT_DIR%
echo Destino: http://localhost:%BACKEND_PORT% (backend local)
echo.

REM Validar que cloudflared.exe existe antes de intentar arrancar
if not exist "%SCRIPT_DIR%cloudflared.exe" (
  echo ERROR: No se encuentra cloudflared.exe en la carpeta del script.
  echo Ubicación esperada: %SCRIPT_DIR%cloudflared.exe
  echo.
  echo Por favor descárgalo desde:
  echo   https://github.com/cloudflare/cloudflared/releases/latest
  echo.
  pause
  exit /b 1
)

echo Iniciando túnel Cloudflare hacia el backend local...
echo.

start /B /WANAKA "Cloudflare Tunnel" cmd /c "
  cd /d "%SCRIPT_DIR%"
  echo Ejecutando: cloudflared.exe tunnel --url http://localhost:%BACKEND_PORT%
  %SCRIPT_DIR%cloudflared.exe tunnel --url http://localhost:%BACKEND_PORT% --logfile .cloudflared\cloudflared.log run > tunnel_output.txt 2>&1
"

REM Espera para que el tunnel inicie
timeout /t 20 >nul

REM --- Validación Final ---
echo.
echo ==========================================
echo  VALIDACIÓN DE SERVICIOS
echo ==========================================
echo.

REM Verificar que el backend esté corriendo
echo Verificando Backend en http://127.0.0.1:%BACKEND_PORT%/health...
curl -s http://127.0.0.1:%BACKEND_PORT%/health >nul 2>&1 && echo "✓ Backend ACTIVO" || echo "⚠ Backend: Verifica que se esté iniciando..."

REM Verificar que el túnel generó salida
if exist "%SCRIPT_DIR%tunnel_output.txt" (
  echo "✓ Archivo tunnel_output.txt generado"
  findstr /i "trycloudflare" "%SCRIPT_DIR%tunnel_output.txt" >nul && echo "✓ URL pública detectada" || echo "⚓ Tunnel activo (URL por verificar)"
) else (
  echo "⚠ Archivo tunnel_output.txt aún por generarse"
)

echo.
echo ==========================================
echo  INSTRUCCIONES FINALES
echo ==========================================
echo.
echo "1. Espera a que los 3 servicios estén ACTIVOS (puede tardar ~30s)"
echo "2. Abre tu navegador en: http://127.0.0.1:%FRONTEND_PORT%"
echo "3. La URL pública de Cloudflare aparecerá en la ventana del Tunnel"
echo "4. Presiona Ctrl+C para detener cualquier servicio"
echo.
echo "Para ver logs en tiempo real, revisa:"
echo "  - .cloudflared\cloudflared.log (túnel)"
echo "  - tunnel_output.txt (URL pública)"
echo.
echo Presiona cualquier tecla para continuar o Ctrl+C para salir...
pause >nul

endlocal