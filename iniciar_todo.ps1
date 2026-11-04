# =====================================================================
#  SISTEMA T-800: SCRIPT DE ARRANQUE MAESTRO (NIVEL DIOS FINAL)
# =====================================================================

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "   INICIANDO MOTOR COMPLETO DEL T-800 (WEB)" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

# 1. Limpieza segura de puertos
Write-Host "[1/4] Comprobando puertos 8000 y 5173..." -ForegroundColor Yellow
$connections = Get-NetTCPConnection -LocalPort 8000,5173 -ErrorAction SilentlyContinue
if ($connections) {
    $connections.OwningProcess | Get-Unique | ForEach-Object {
        Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue
    }
    Write-Host " > Puertos liberados con éxito." -ForegroundColor Green
} else {
    Write-Host " > Los puertos ya estaban libres." -ForegroundColor Green
}

# 2. Arrancar Backend (FastAPI) en una ventana secundaria
Write-Host "[2/4] Arrancando Backend (FastAPI en puerto 8000)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd backend; .venv\Scripts\python.exe -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

# 3. Arrancar Frontend (Vite) en una ventana secundaria
Write-Host "[3/4] Arrancando Frontend (Vite en puerto 5173)..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd frontend; npm run dev"

# 4. Esperar 3 segundos para estabilizar servicios
Start-Sleep -Seconds 3

# 5. Arrancar Cloudflare Tunnel apuntando a la Interfaz Web (Puerto 5173)
Write-Host "[4/4] Estableciendo túnel HTTPS con la Interfaz Web (Puerto 5173)..." -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Green
Write-Host "  SISTEMA T-800 DESPLEGADO CON ÉXITO" -ForegroundColor Green
Write-Host "  - Localhost : http://localhost:5173" -ForegroundColor White
Write-Host "  - Remoto    : Copia la URL 'trycloudflare.com' que aparecerá abajo" -ForegroundColor White
Write-Host "===================================================" -ForegroundColor Green

if (Get-Command "cloudflared" -ErrorAction SilentlyContinue) {
    cloudflared tunnel --url http://127.0.0.1:5173
} elseif (Test-Path ".\cloudflared.exe") {
    .\cloudflared tunnel --url http://127.0.0.1:5173
} else {
    Write-Host "⚠️ No se encontró 'cloudflared' en el sistema ni en la carpeta actual." -ForegroundColor Red
}
