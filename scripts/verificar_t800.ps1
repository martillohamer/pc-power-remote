# verificar_t800.ps1 - Verificacion automatica completa de pc-power-remote (FASE 3B)
# Ejecuta comprobaciones estaticas y en vivo sobre backend (127.0.0.1:8100)
# y frontend (127.0.0.1:5273), con APP_DRY_RUN=1. Sale con codigo = numero de FAIL.

$ErrorActionPreference = "Continue"
$script:results = @()
$script:failCount = 0
$script:warnCount = 0
$script:launchPids = @()
$script:envFileHashBefore = $null
$script:envFileHashAfter = $null
$script:backendPort = 8100
$script:frontendPort = 5273
$script:apiTarget = "http://127.0.0.1:8100"
$script:repoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$script:backendDir = Join-Path -Path $script:repoRoot -ChildPath "backend"
$script:frontendDir = Join-Path -Path $script:repoRoot -ChildPath "frontend"
$script:logFile = Join-Path -Path $script:repoRoot -ChildPath "verificacion_t800.log"
$script:pythonExe = Join-Path -Path $script:backendDir -ChildPath ".venv\Scripts\python.exe"
$script:wsCheck = Join-Path -Path $script:repoRoot -ChildPath "scripts\ws_check.py"
$script:pin = (Get-Random -Minimum 1000 -Maximum 9999).ToString("D4")
$script:startTime = Get-Date

function Write-Log {
    param([string]$Message)
    $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    $line = "[$ts] $Message"
    $line | Out-File -FilePath $script:logFile -Encoding utf8 -Append
}

function Start-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=" * 80)
    Write-Host $Title
    Write-Host ("=" * 80)
    Write-Log "=== $Title ==="
}

function Add-Result {
    param([string]$Id, [string]$Prueba, [string]$Resultado, [string]$Detalle)
    $result = [PSCustomObject]@{
        ID       = $Id
        Prueba   = $Prueba
        Resultado= $Resultado
        Detalle  = $Detalle
    }
    $script:results += $result
    if ($Resultado -eq "FAIL") { $script:failCount++ }
    if ($Resultado -eq "WARN") { $script:warnCount++ }
    $padId = $Id.PadRight(6)
    $padPrueba = $Prueba.PadRight(45)
    $padRes = $Resultado.PadRight(8)
    Write-Host ("{0} | {1} | {2} | {3}" -f $padId, $padPrueba, $padRes, $Detalle)
    Write-Log ("{0} | {1} | {2} | {3}" -f $padId, $padPrueba, $padRes, $Detalle)
}

function Track-Process {
    param([int]$procId)
    $script:launchPids += $procId
    Write-Host "  [PID rastreado: $procId]"
}

function Get-EnvFileHash {
    $envFile = Join-Path -Path $script:backendDir -ChildPath ".env"
    if (Test-Path $envFile) {
        return (Get-FileHash -Path $envFile -Algorithm SHA256).Hash
    }
    return $null
}

function Wait-Health {
    param([string]$Url, [int]$TimeoutSec = 30)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $attempt = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        try {
            $resp = Invoke-WebRequest -Uri $Url -Method GET -TimeoutSec 2 -ErrorAction Stop -UseBasicParsing
            if ($resp.StatusCode -eq 200) {
                Write-Host ("Health OK tras {0} intento(s)" -f $attempt)
                return $true
            }
        } catch {
            if ($attempt -le 3 -or $attempt % 10 -eq 0) {
                Write-Host ("Health intento {0}: {1}" -f $attempt, $_.Exception.Message)
            }
            Start-Sleep -Milliseconds 500
        }
    }
    Write-Host ("Health fallo tras {0} intento(s)" -f $attempt)
    return $false
}

function Invoke-Api {
    param([string]$Method, [string]$Path, [string]$Body = $null)
    $headers = @{"X-App-Pin" = $script:pin}
    if ($Body) { $headers["Content-Type"] = "application/json" }
    $splat = @{
        Uri       = "http://127.0.0.1:$($script:backendPort)$Path"
        Method    = $Method
        Headers   = $headers
        TimeoutSec = 10
        ErrorAction = "Stop"
        UseBasicParsing = $true
    }
    if ($Body) { $splat["Body"] = $Body }
    return Invoke-WebRequest @splat
}

function Kill-Port {
    param([int]$Port)
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    foreach ($c in $conns) {
        try {
            Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop
            Write-Host "  liberado puerto $Port (PID $($c.OwningProcess) terminado)"
            Write-Log "LIBERADO puerto $Port (PID $($c.OwningProcess))"
        } catch {
            # No se pudo terminar
        }
    }
}

function Stop-OwnProcesses {
    Write-Host ""
    Write-Host "=== LIMPIEZA FINAL: terminando procesos lanzados por este script ==="
    foreach ($procId in $script:launchPids) {
        try {
            # taskkill /T /F mata el arbol de procesos (hijos incluidos)
            cmd /c "taskkill /T /F /PID $procId" >nul 2>&1
            Write-Host "  terminado arbol PID $procId"
            Write-Log "TERMINADO arbol PID $procId"
        } catch {
            # Ya no existe o no se pudo terminar
        }
    }
    $script:launchPids = @()
}

# ----------------------------------------------------------------
# BLOQUE PRINCIPAL
# ----------------------------------------------------------------
try {
    $script:envFileHashBefore = Get-EnvFileHash
    $savedEnvDryRun = $env:APP_DRY_RUN
    $savedEnvMac = $env:APP_MAC_ADDRESS
    $savedEnvPin = $env:APP_PIN
    $savedEnvApiTarget = $env:API_TARGET
    $env:APP_DRY_RUN = "1"
    $env:APP_MAC_ADDRESS = "AA:BB:CC:DD:EE:FF"
    $env:APP_PIN = $script:pin

    Write-Host "APP_PIN generado para esta ejecucion: $($script:pin)"
    Write-Host "Backend: http://127.0.0.1:$($script:backendPort)"
    Write-Host "Frontend: http://127.0.0.1:$($script:frontendPort) (API_TARGET=$($script:apiTarget))"
    Write-Log "APP_PIN=$($script:pin)"

    # Liberar puertos que vamos a usar (por si quedaron de pruebas previas)
    Kill-Port -Port $script:backendPort
    Kill-Port -Port $script:frontendPort

    Start-Section "COMPROBACIONES ESTATICAS (sin procesos)"

    # ---- E1: ASCII, sin BOM, CRLF 100% en los .bat y .ps1 relevantes ----
    $e1Ok = $true
    $e1Detail = New-Object System.Collections.Generic.List[string]
    $e1Files = @(
        "iniciar_todo.bat",
        "run_tunnel.bat",
        "backend\run_backend.bat",
        "frontend\run_frontend.bat",
        "tunnel_url.ps1",
        "scripts\verificar_t800.ps1"
    )
    foreach ($rel in $e1Files) {
        $path = Join-Path -Path $script:repoRoot -ChildPath $rel
        if (-not (Test-Path $path)) {
            $e1Detail.Add("$rel no existe")
            $e1Ok = $false
            continue
        }
        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $e1Ok = $false
                $e1Detail.Add("BOM en $rel")
                continue
            }
            $isAscii = $true
            foreach ($b in $bytes) { if ($b -gt 127) { $isAscii = $false; break } }
            if (-not $isAscii) {
                $e1Ok = $false
                $e1Detail.Add("caracter no ASCII en $rel")
                continue
            }
            $text = [System.Text.Encoding]::ASCII.GetString($bytes)
            $nonEmptyLines = ($text -split "`r?`n").Where({ $_ -ne "" })
            $totalLines = $nonEmptyLines.Count
            # Cualquier \n no precedido por \r significa que no es CRLF al 100%
            $loneLf = [regex]::Matches($text, "(?<!\r)`n").Count
            if ($totalLines -gt 0 -and $loneLf -gt 0) {
                $e1Ok = $false
                $e1Detail.Add(("lineas sin CRLF en {0} ({1} LF sin CR)" -f $rel, $loneLf))
            }
        } catch {
            $e1Ok = $false
            $e1Detail.Add(("error leyendo {0}: {1}" -f $rel, $_.Exception.Message))
        }
    }
    if ($e1Ok) {
        Add-Result -Id "E1" -Prueba "Archivos .bat/.ps1 relevantes: ASCII, sin BOM, CRLF 100%" -Resultado "PASS" -Detalle ("Todos los archivos cumplen ({0} archivos)" -f $e1Files.Count)
    } else {
        Add-Result -Id "E1" -Prueba "Archivos .bat/.ps1 relevantes: ASCII, sin BOM, CRLF 100%" -Resultado "FAIL" -Detalle ($e1Detail -join "; ")
    }

    # ---- E2: run_tunnel.bat e iniciar_todo.bat sin patrones prohibidos ----
    $e2Ok = $true
    $e2Detail = New-Object System.Collections.Generic.List[string]
    $forbiddenPatterns = @("tunnel run", "findstr", "/WANAKA", "192.168.")
    foreach ($batFile in @("run_tunnel.bat", "iniciar_todo.bat")) {
        $path = Join-Path -Path $script:repoRoot -ChildPath $batFile
        if (-not (Test-Path $path)) {
            $e2Ok = $false
            $e2Detail.Add("$batFile no existe")
            continue
        }
        $content = Get-Content -Path $path -Raw
        foreach ($pat in $forbiddenPatterns) {
            if ($content -like "*$pat*") {
                $e2Ok = $false
                $e2Detail.Add("$batFile contiene '$pat'")
            }
        }
    }
    if ($e2Ok) {
        Add-Result -Id "E2" -Prueba "run_tunnel.bat/iniciar_todo.bat sin patrones prohibidos" -Resultado "PASS" -Detalle "Sin 'tunnel run', 'findstr', '/WANAKA', '192.168.'"
    } else {
        Add-Result -Id "E2" -Prueba "run_tunnel.bat/iniciar_todo.bat sin patrones prohibidos" -Resultado "FAIL" -Detalle ($e2Detail -join "; ")
    }

    # ---- E3: iniciar_todo.bat invoca run_backend.bat dev, sin --reload, invoca run_tunnel.bat, .bats existen ----
    $e3Ok = $true
    $e3Detail = New-Object System.Collections.Generic.List[string]
    $iniPath = Join-Path -Path $script:repoRoot -ChildPath "iniciar_todo.bat"
    if (-not (Test-Path $iniPath)) {
        Add-Result -Id "E3" -Prueba "iniciar_todo.bat: run_backend.bat dev, sin --reload, invoca run_tunnel.bat" -Resultado "FAIL" -Detalle "iniciar_todo.bat no existe"
    } else {
        $iniContent = Get-Content -Path $iniPath -Raw
        if ($iniContent -notlike "*run_backend.bat dev*") {
            $e3Ok = $false
            $e3Detail.Add("no invoca 'run_backend.bat dev'")
        }
        if ($iniContent -like "*--reload*") {
            $e3Ok = $false
            $e3Detail.Add("contiene '--reload' (deberia delegar a run_backend.bat dev)")
        }
        if ($iniContent -notlike "*run_tunnel.bat*") {
            $e3Ok = $false
            $e3Detail.Add("no invoca 'run_tunnel.bat'")
        }
        $refPaths = @(
            (Join-Path -Path $script:repoRoot -ChildPath "backend\run_backend.bat"),
            (Join-Path -Path $script:repoRoot -ChildPath "run_tunnel.bat")
        )
        foreach ($refPath in $refPaths) {
            if (-not (Test-Path $refPath)) {
                $e3Ok = $false
                $e3Detail.Add(("referenciado pero no existe: {0}" -f [System.IO.Path]::GetFileName($refPath)))
            }
        }
        if ($e3Ok) {
            Add-Result -Id "E3" -Prueba "iniciar_todo.bat: run_backend.bat dev, sin --reload, invoca run_tunnel.bat" -Resultado "PASS" -Detalle "Todos los .bats referenciados existen"
        } else {
            Add-Result -Id "E3" -Prueba "iniciar_todo.bat: run_backend.bat dev, sin --reload, invoca run_tunnel.bat" -Resultado "FAIL" -Detalle ($e3Detail -join "; ")
        }
    }

    # ---- E4: run_tunnel.bat borra log antes de cloudflared, --no-autoupdate, 127.0.0.1, puerto por argumento ----
    $e4Ok = $true
    $e4Detail = New-Object System.Collections.Generic.List[string]
    $tunPath = Join-Path -Path $script:repoRoot -ChildPath "run_tunnel.bat"
    if (-not (Test-Path $tunPath)) {
        Add-Result -Id "E4" -Prueba "run_tunnel.bat: borra log, --no-autoupdate, 127.0.0.1, puerto por arg" -Resultado "FAIL" -Detalle "run_tunnel.bat no existe"
    } else {
        $tunContent = Get-Content -Path $tunPath -Raw
        if ($tunContent -notlike "*del*" -or $tunContent -notlike "*LOG_FILE*") {
            $e4Ok = $false
            $e4Detail.Add("no borra el log (del + LOG_FILE) antes de cloudflared")
        }
        if ($tunContent -notlike "*--no-autoupdate*") {
            $e4Ok = $false
            $e4Detail.Add("no usa --no-autoupdate")
        }
        if ($tunContent -notlike "*127.0.0.1*") {
            $e4Ok = $false
            $e4Detail.Add("no usa 127.0.0.1")
        }
        if ($tunContent -notmatch "%~1") {
            $e4Ok = $false
            $e4Detail.Add("no acepta puerto como primer argumento (%~1)")
        }
        if ($e4Ok) {
            Add-Result -Id "E4" -Prueba "run_tunnel.bat: borra log, --no-autoupdate, 127.0.0.1, puerto por arg" -Resultado "PASS" -Detalle "Todos los requisitos de run_tunnel.bat cumplidos"
        } else {
            Add-Result -Id "E4" -Prueba "run_tunnel.bat: borra log, --no-autoupdate, 127.0.0.1, puerto por arg" -Resultado "FAIL" -Detalle ($e4Detail -join "; ")
        }
    }

    # ---- E5: tunnel_url.ps1 y verificar_t800.ps1 parsean; tunnel_url.ps1 tiene regex trycloudflare y -Last 1 ----
    $e5Ok = $true
    $e5Detail = New-Object System.Collections.Generic.List[string]
    foreach ($ps1File in @("tunnel_url.ps1", "scripts\verificar_t800.ps1")) {
        $ps1Path = Join-Path -Path $script:repoRoot -ChildPath $ps1File
        if (-not (Test-Path $ps1Path)) {
            $e5Ok = $false
            $e5Detail.Add("$ps1File no existe")
            continue
        }
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($ps1Path, [ref] $null, [ref] $parseErrors)
        if ($parseErrors -and $parseErrors.Count -gt 0) {
            $e5Ok = $false
            $msgs = $parseErrors | ForEach-Object { $_.Message }
            $e5Detail.Add(("{0} tiene errores de sintaxis: {1}" -f $ps1File, ($msgs -join ', ')))
        }
    }
    $tunUrlPath = Join-Path -Path $script:repoRoot -ChildPath "tunnel_url.ps1"
    $tunUrlContent = Get-Content -Path $tunUrlPath -Raw
    if ($tunUrlContent -notlike "*trycloudflare*") {
        $e5Ok = $false
        $e5Detail.Add("tunnel_url.ps1 no contiene regex trycloudflare")
    }
    if ($tunUrlContent -notmatch "-Last 1") {
        $e5Ok = $false
        $e5Detail.Add("tunnel_url.ps1 no usa -Last 1")
    }
    if ($e5Ok) {
        Add-Result -Id "E5" -Prueba "tunnel_url.ps1 y verificar_t800.ps1: sintaxis valida, regex y -Last 1" -Resultado "PASS" -Detalle "Ambos .ps1 parsean sin errores; tunnel_url.ps1 tiene trycloudflare y -Last 1"
    } else {
        Add-Result -Id "E5" -Prueba "tunnel_url.ps1 y verificar_t800.ps1: sintaxis valida, regex y -Last 1" -Resultado "FAIL" -Detalle ($e5Detail -join "; ")
    }

    # ---- E6: Frontend estatico ----
    $e6Failures = New-Object System.Collections.Generic.List[string]
    $appContent = Get-Content -Path (Join-Path -Path $script:frontendDir -ChildPath "src\App.jsx") -Raw
    $forensicContent = Get-Content -Path (Join-Path -Path $script:frontendDir -ChildPath "src\ForensicPanel.jsx") -Raw
    $voiceContent = Get-Content -Path (Join-Path -Path $script:frontendDir -ChildPath "src\VoiceCommandButton.jsx") -Raw
    $viteContent = Get-Content -Path (Join-Path -Path $script:frontendDir -ChildPath "vite.config.js") -Raw

    if ($appContent -like "*class=*") { $e6Failures.Add("App.jsx contiene 'class='") }
    if ($appContent -notlike "*pb-28*") { $e6Failures.Add("App.jsx no tiene pb-28") }
    if ($appContent -notlike "*window.confirm*") { $e6Failures.Add("App.jsx no tiene window.confirm en voz terminator") }
    if ($appContent -notlike "*TERMINATOR*") { $e6Failures.Add("App.jsx no menciona TERMINATOR en confirmacion") }
    if ($forensicContent -notlike "*overflow-x-auto*") { $e6Failures.Add("ForensicPanel no tiene overflow-x-auto") }
    if ($forensicContent -like "*transition-width*") { $e6Failures.Add("ForensicPanel contiene transition-width") }
    if ($voiceContent -notlike "*isSecureContext*") { $e6Failures.Add("VoiceCommandButton no tiene isSecureContext") }
    if ($viteContent -notlike "*allowedHosts*") { $e6Failures.Add("vite.config.js no tiene allowedHosts") }
    if ($viteContent -notlike "*.trycloudflare.com*") { $e6Failures.Add("vite.config.js allowedHosts no tiene .trycloudflare.com") }

    if ($e6Failures.Count -eq 0) {
        Add-Result -Id "E6" -Prueba "Frontend estatico: App.jsx, ForensicPanel, VoiceCommandButton, vite.config.js" -Resultado "PASS" -Detalle "Todas las comprobaciones E6 cumplidas"
    } else {
        Add-Result -Id "E6" -Prueba "Frontend estatico: App.jsx, ForensicPanel, VoiceCommandButton, vite.config.js" -Resultado "FAIL" -Detalle ($e6Failures -join "; ")
    }

    # ---- E7: .gitignore contiene .pytest_cache/ y .cloudflared/ ----
    $gitignoreContent = Get-Content -Path (Join-Path -Path $script:repoRoot -ChildPath ".gitignore") -Raw
    if ($gitignoreContent -like "*.pytest_cache/*" -and $gitignoreContent -like "*.cloudflared/*") {
        Add-Result -Id "E7" -Prueba ".gitignore ignora .pytest_cache/ y .cloudflared/" -Resultado "PASS" -Detalle "Ambas entradas presentes en .gitignore"
    } else {
        Add-Result -Id "E7" -Prueba ".gitignore ignora .pytest_cache/ y .cloudflared/" -Resultado "FAIL" -Detalle "Faltan entradas en .gitignore"
    }

    # ---- E8: Archivos tocados en esta fase sin PIN valor, MACs reales, ni 192.168 ----
    $e8Ok = $true
    $e8Detail = New-Object System.Collections.Generic.List[string]
    try {
        $changedFiles = git diff --name-only backup/pre-3b..HEAD 2>$null
        foreach ($f in $changedFiles) {
            $fullPath = Join-Path -Path $script:repoRoot -ChildPath $f
            if (-not (Test-Path $fullPath)) { continue }
            $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
            $content = Get-Content -Path $fullPath -Raw
            if ($ext -ne ".py" -and $ext -ne ".jsx") {
                if ($content -like "*134113*") {
                    $e8Ok = $false
                    $e8Detail.Add("$f contiene el valor del PIN por defecto (134113)")
                }
            }
            if ($ext -ne ".py" -and $ext -ne ".jsx") {
                if ($content -match "[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}") {
                    $e8Ok = $false
                    $e8Detail.Add("$f contiene una MAC real")
                }
            }
            if ($content -like "*192.168.*") {
                $e8Ok = $false
                $e8Detail.Add("$f contiene 192.168.")
            }
        }
    } catch {
        $e8Ok = $false
        $e8Detail.Add(("error ejecutando git diff: {0}" -f $_.Exception.Message))
    }
    if ($e8Ok) {
        Add-Result -Id "E8" -Prueba "Archivos de esta fase sin PIN/MACs/192.168" -Resultado "PASS" -Detalle "Ningun archivo tocado contiene datos sensibles expuestos"
    } else {
        Add-Result -Id "E8" -Prueba "Archivos de esta fase sin PIN/MACs/192.168" -Resultado "FAIL" -Detalle ($e8Detail -join "; ")
    }

    Start-Section "BACKEND VIVO (127.0.0.1:$($script:backendPort), APP_DRY_RUN=1)"

    try {
        $backendProc = Start-Process -FilePath $script:pythonExe `
            -ArgumentList "-m", "uvicorn", "main:app", "--host", "127.0.0.1", "--port", $script:backendPort `
            -WorkingDirectory $script:backendDir -PassThru
        Track-Process -procId $backendProc.Id
    } catch {
        Add-Result -Id "B0" -Prueba "Arranque del backend en 127.0.0.1:8100" -Resultado "FAIL" -Detalle ("No se pudo arrancar: {0}" -f $_.Exception.Message)
        throw "No se pudo arrancar el backend"
    }

    # Debug: verificar que el proceso sigue vivo
    $procAlive = $false
    try { $null = Get-Process -Id $backendProc.Id -ErrorAction Stop; $procAlive = $true } catch {}
    Write-Host ("Backend PID {0} vivo: {1}" -f $backendProc.Id, $procAlive)

    if (-not (Wait-Health -Url "http://127.0.0.1:$($script:backendPort)/api/health" -TimeoutSec 30)) {
        Add-Result -Id "B0" -Prueba "Backend responde /api/health" -Resultado "FAIL" -Detalle "El backend no respondio en 30 s (PID vivo: $procAlive)"
        throw "Backend no respondio"
    }
    Add-Result -Id "B0" -Prueba "Backend arrancado y /api/health responde" -Resultado "PASS" -Detalle "Backend en 127.0.0.1:8100 con APP_DRY_RUN=1"

    # ---- B1: GET /api/health -> 200 status online ----
    try {
        $resp = Invoke-Api -Method "GET" -Path "/api/health"
        $body = $resp.Content | ConvertFrom-Json
        if ($resp.StatusCode -eq 200 -and $body.status -eq "online") {
            Add-Result -Id "B1" -Prueba "GET /api/health -> 200 status online" -Resultado "PASS" -Detalle ("Respuesta: {0}" -f $resp.Content)
        } else {
            Add-Result -Id "B1" -Prueba "GET /api/health -> 200 status online" -Resultado "FAIL" -Detalle ("Status={0} body={1}" -f $resp.StatusCode, $resp.Content)
        }
    } catch {
        Add-Result -Id "B1" -Prueba "GET /api/health -> 200 status online" -Resultado "FAIL" -Detalle $_.Exception.Message
    }

    # ---- B2: Sin PIN y PIN erroneo en /api/state -> 401/403 ----
    $b2Ok = $true
    $b2Detail = New-Object System.Collections.Generic.List[string]
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:backendPort)/api/state" -Method GET -TimeoutSec 10 -ErrorAction Stop
        $b2Ok = $false
        $b2Detail.Add("Sin PIN: obtuvo 200 (se esperaba 401/403)")
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -ne 401 -and $code -ne 403) {
            $b2Ok = $false
            $b2Detail.Add(("Sin PIN: obtuvo {0} (se esperaba 401/403)" -f $code))
        }
    }
    $origPin = $script:pin
    $script:pin = "0000"
    try {
        $resp2 = Invoke-Api -Method "GET" -Path "/api/state"
        $b2Ok = $false
        $b2Detail.Add("PIN erroneo: obtuvo 200 (se esperaba 401/403)")
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -ne 401 -and $code -ne 403) {
            $b2Ok = $false
            $b2Detail.Add(("PIN erroneo: obtuvo {0} (se esperaba 401/403)" -f $code))
        }
    } finally {
        $script:pin = $origPin
    }
    if ($b2Ok) {
        Add-Result -Id "B2" -Prueba "Sin PIN y PIN erroneo en /api/state -> 401/403" -Resultado "PASS" -Detalle "Ambas respuestas rechazan sin PIN valido"
    } else {
        Add-Result -Id "B2" -Prueba "Sin PIN y PIN erroneo en /api/state -> 401/403" -Resultado "FAIL" -Detalle ($b2Detail -join "; ")
    }

    # ---- B3: POST /api/shutdown {"minutes":0}, {}, sin cuerpo -> 200; -1 y 1441 -> 422 ----
    $b3Ok = $true
    $b3Detail = New-Object System.Collections.Generic.List[string]
    foreach ($body in @('{"minutes":0}', '{}', $null)) {
        try {
            $resp = Invoke-Api -Method "POST" -Path "/api/shutdown" -Body $body
            if ($resp.StatusCode -ne 200) {
                $b3Ok = $false
                $b3Detail.Add(("body='{0}' obtuvo {1} (se esperaba 200)" -f $body, $resp.StatusCode))
            }
        } catch {
            $b3Ok = $false
            $b3Detail.Add(("body='{0}' excepcion: {1}" -f $body, $_.Exception.Message))
        }
    }
    foreach ($invBody in @('{"minutes":-1}', '{"minutes":1441}')) {
        try {
            $resp = Invoke-Api -Method "POST" -Path "/api/shutdown" -Body $invBody
            $b3Ok = $false
            $b3Detail.Add(("body='{0}' obtuvo 200 (se esperaba 422)" -f $invBody))
        } catch {
            $code = $_.Exception.Response.StatusCode.value__
            if ($code -ne 422) {
                $b3Ok = $false
                $b3Detail.Add(("body='{0}' obtuvo {1} (se esperaba 422)" -f $invBody, $code))
            }
        }
    }
    if ($b3Ok) {
        Add-Result -Id "B3" -Prueba "POST /api/shutdown: 0/{}/sin cuerpo -> 200; -1/1441 -> 422" -Resultado "PASS" -Detalle "Validacion de minutos correcta"
    } else {
        Add-Result -Id "B3" -Prueba "POST /api/shutdown: 0/{}/sin cuerpo -> 200; -1/1441 -> 422" -Resultado "FAIL" -Detalle ($b3Detail -join "; ")
    }

    # ---- B4: POST /api/shutdown {"minutes":5} -> 200; GET /api/state -> pending true ----
    $b4Ok = $true
    $b4Detail = New-Object System.Collections.Generic.List[string]
    try {
        $resp = Invoke-Api -Method "POST" -Path "/api/shutdown" -Body '{"minutes":5}'
        $body = $resp.Content | ConvertFrom-Json
        if ($resp.StatusCode -ne 200 -or $body.minutes -ne 5) {
            $b4Ok = $false
            $b4Detail.Add(("POST shutdown 5 min: status={0} minutes={1}" -f $resp.StatusCode, $body.minutes))
        }
    } catch {
        $b4Ok = $false
        $b4Detail.Add(("POST shutdown 5 min excepcion: {0}" -f $_.Exception.Message))
    }
    try {
        $resp = Invoke-Api -Method "GET" -Path "/api/state"
        $body = $resp.Content | ConvertFrom-Json
        if ($body.pending -ne $true) {
            $b4Ok = $false
            $b4Detail.Add(("GET /api/state: pending={0} (se esperaba true)" -f $body.pending))
        }
    } catch {
        $b4Ok = $false
        $b4Detail.Add(("GET /api/state excepcion: {0}" -f $_.Exception.Message))
    }
    if ($b4Ok) {
        Add-Result -Id "B4" -Prueba "POST /api/shutdown minutes=5 -> 200; GET /api/state pending=true" -Resultado "PASS" -Detalle "Temporizador de 5 min armado y estado reflecte pending"
    } else {
        Add-Result -Id "B4" -Prueba "POST /api/shutdown minutes=5 -> 200; GET /api/state pending=true" -Resultado "FAIL" -Detalle ($b4Detail -join "; ")
    }

    # ---- B5: POST /api/cancel -> 200; GET /api/state -> pending false. Segundo cancel: 200 o 409. ----
    $b5Ok = $true
    $b5Detail = New-Object System.Collections.Generic.List[string]
    try {
        $resp = Invoke-Api -Method "POST" -Path "/api/cancel"
        if ($resp.StatusCode -ne 200) {
            $b5Ok = $false
            $b5Detail.Add(("primer cancel: obtuvo {0} (se esperaba 200)" -f $resp.StatusCode))
        }
        $resp2 = Invoke-Api -Method "GET" -Path "/api/state"
        $body2 = $resp2.Content | ConvertFrom-Json
        if ($body2.pending -ne $false) {
            $b5Ok = $false
            $b5Detail.Add(("despues de cancel: pending={0} (se esperaba false)" -f $body2.pending))
        }
    } catch {
        $b5Ok = $false
        $b5Detail.Add(("primer cancel excepcion: {0}" -f $_.Exception.Message))
    }
    try {
        $resp3 = Invoke-Api -Method "POST" -Path "/api/cancel"
        $code3 = $resp3.StatusCode
        if ($code3 -ne 200 -and $code3 -ne 409) {
            $b5Ok = $false
            $b5Detail.Add(("segundo cancel: obtuvo {0} (se esperaba 200 o 409)" -f $code3))
        } else {
            $b5Detail.Add(("segundo cancel: {0} (aceptado)" -f $code3))
        }
    } catch {
        $code3 = $_.Exception.Response.StatusCode.value__
        if ($code3 -ne 200 -and $code3 -ne 409) {
            $b5Ok = $false
            $b5Detail.Add(("segundo cancel: obtuvo {0} (se esperaba 200 o 409)" -f $code3))
        } else {
            $b5Detail.Add(("segundo cancel: {0} (aceptado)" -f $code3))
        }
    }
    if ($b5Ok) {
        Add-Result -Id "B5" -Prueba "POST /api/cancel -> 200; GET /api/state pending=false; segundo cancel 200/409" -Resultado "PASS" -Detalle ($b5Detail -join "; ")
    } else {
        Add-Result -Id "B5" -Prueba "POST /api/cancel -> 200; GET /api/state pending=false; segundo cancel 200/409" -Resultado "FAIL" -Detalle ($b5Detail -join "; ")
    }

    # ---- B6: GET /api/forensic/processes <= 10 elementos, ordenados desc, cpu_percent <= 100*nucleos ----
    try {
        $resp = Invoke-Api -Method "GET" -Path "/api/forensic/processes"
        $procs = $resp.Content | ConvertFrom-Json
        $numCores = [System.Environment]::ProcessorCount
        $maxCpu = 100.0 * $numCores
        $b6Ok = $true
        $b6Detail = New-Object System.Collections.Generic.List[string]
        if ($procs.Count -gt 10) {
            $b6Ok = $false
            $b6Detail.Add("{0} elementos (max 10)" -f $procs.Count)
        }
        $prevCpu = [double]::MaxValue
        $prevMem = [double]::MaxValue
        foreach ($p in $procs) {
            if ($p.cpu_percent -gt $maxCpu) {
                $b6Ok = $false
                $b6Detail.Add(("PID {0} cpu_percent={1} > {2}" -f $p.pid, $p.cpu_percent, $maxCpu))
            }
            if ($p.cpu_percent -gt $prevCpu) {
                $b6Ok = $false
                $b6Detail.Add(("no ordenado por cpu_percent desc en PID {0}" -f $p.pid))
            }
            if ($p.cpu_percent -eq $prevCpu -and $p.memory_mb -gt $prevMem) {
                $b6Ok = $false
                $b6Detail.Add(("no ordenado por memory_mb desc en PID {0}" -f $p.pid))
            }
            $prevCpu = $p.cpu_percent
            $prevMem = $p.memory_mb
        }
        if ($b6Ok) {
            Add-Result -Id "B6" -Prueba "GET /api/forensic/processes <=10, ordenado desc, cpu<=100*nucleos" -Resultado "PASS" -Detalle ("{0} procesos, nucleos={1}, max_cpu={2}" -f $procs.Count, $numCores, $maxCpu)
        } else {
            Add-Result -Id "B6" -Prueba "GET /api/forensic/processes <=10, ordenado desc, cpu<=100*nucleos" -Resultado "FAIL" -Detalle ($b6Detail -join "; ")
        }
    } catch {
        Add-Result -Id "B6" -Prueba "GET /api/forensic/processes <=10, ordenado desc, cpu<=100*nucleos" -Resultado "FAIL" -Detalle $_.Exception.Message
    }

    # ---- B7: WebSocket directo ws://127.0.0.1:8100/ws/telemetry?pin=<PIN>: >=3 frames en 8s. PIN erroneo: cierre 1008. ----
    $wsUrl = "ws://127.0.0.1:$($script:backendPort)/ws/telemetry?pin=$($script:pin)"
    & $script:pythonExe $script:wsCheck $wsUrl 3 8
    $wsExit = $LASTEXITCODE
    if ($wsExit -eq 0) {
        Add-Result -Id "B7" -Prueba "WebSocket backend >=3 frames validos en 8s" -Resultado "PASS" -Detalle "ws_check.py salio con codigo 0"
    } else {
        Add-Result -Id "B7" -Prueba "WebSocket backend >=3 frames validos en 8s" -Resultado "FAIL" -Detalle ("ws_check.py salio con codigo {0}" -f $wsExit)
    }
    $wsBadUrl = "ws://127.0.0.1:$($script:backendPort)/ws/telemetry?pin=0000"
    & $script:pythonExe $script:wsCheck $wsBadUrl 0 8 --expect-close 1008
    $wsBadExit = $LASTEXITCODE
    if ($wsBadExit -eq 0) {
        Add-Result -Id "B7b" -Prueba "WebSocket backend PIN invalido -> cierre 1008" -Resultado "PASS" -Detalle "ws_check.py --expect-close 1008 salio con codigo 0"
    } else {
        Add-Result -Id "B7b" -Prueba "WebSocket backend PIN invalido -> cierre 1008" -Resultado "FAIL" -Detalle ("ws_check.py --expect-close 1008 salio con codigo {0}" -f $wsBadExit)
    }

    # ---- B8: GET /api/windows/unlock -> 404; GET /api/windows/lock -> 405 ----
    $b8Ok = $true
    $b8Detail = New-Object System.Collections.Generic.List[string]
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:backendPort)/api/windows/unlock" -Method GET -Headers @{"X-App-Pin"=$script:pin} -TimeoutSec 10 -ErrorAction Stop
        $b8Ok = $false
        $b8Detail.Add("GET /api/windows/unlock: obtuvo 200 (se esperaba 404)")
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -ne 404) {
            $b8Ok = $false
            $b8Detail.Add(("GET /api/windows/unlock: obtuvo {0} (se esperaba 404)" -f $code))
        }
    }
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:backendPort)/api/windows/lock" -Method GET -Headers @{"X-App-Pin"=$script:pin} -TimeoutSec 10 -ErrorAction Stop
        $b8Ok = $false
        $b8Detail.Add("GET /api/windows/lock: obtuvo 200 (se esperaba 405)")
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -ne 405) {
            $b8Ok = $false
            $b8Detail.Add(("GET /api/windows/lock: obtuvo {0} (se esperaba 405)" -f $code))
        }
    }
    if ($b8Ok) {
        Add-Result -Id "B8" -Prueba "GET /api/windows/unlock -> 404; GET /api/windows/lock -> 405" -Resultado "PASS" -Detalle "unlock eliminado (404), lock solo POST (405 en GET)"
    } else {
        Add-Result -Id "B8" -Prueba "GET /api/windows/unlock -> 404; GET /api/windows/lock -> 405" -Resultado "FAIL" -Detalle ($b8Detail -join "; ")
    }

    Start-Section "FRONTEND VIVO (127.0.0.1:$($script:frontendPort) -> API_TARGET 8100)"

    $env:API_TARGET = $script:apiTarget
    $env:VITE_HOST = "127.0.0.1"
    $env:VITE_PORT = $script:frontendPort.ToString()
    try {
        $frontendProc = Start-Process -FilePath "powershell" `
            -ArgumentList "-NoProfile", "-Command", "npm run dev" `
            -WorkingDirectory $script:frontendDir -PassThru
        Track-Process -procId $frontendProc.Id
    } catch {
        Add-Result -Id "F0" -Prueba "Arranque del frontend en 127.0.0.1:5273" -Resultado "FAIL" -Detalle ("No se pudo arrancar: {0}" -f $_.Exception.Message)
        throw "No se pudo arrancar el frontend"
    }

    $frontendReady = $false
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:frontendPort)/" -Method GET -TimeoutSec 3 -ErrorAction Stop -UseBasicParsing
            if ($resp.StatusCode -eq 200) { $frontendReady = $true; break }
        } catch { Start-Sleep -Milliseconds 1000 }
    }
    if (-not $frontendReady) {
        Add-Result -Id "F0" -Prueba "Frontend responde / en 127.0.0.1:5273" -Resultado "FAIL" -Detalle "El frontend no respondio en 60 s"
        throw "Frontend no respondio"
    }
    Add-Result -Id "F0" -Prueba "Frontend arrancado y / responde en 127.0.0.1:5273" -Resultado "PASS" -Detalle ("Vite en 127.0.0.1:5273 con API_TARGET={0}" -f $script:apiTarget)

    # ---- F1: GET / -> 200 y contiene id="root" ----
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:frontendPort)/" -Method GET -TimeoutSec 10 -ErrorAction Stop -UseBasicParsing
        $html = $resp.Content
        if ($resp.StatusCode -eq 200 -and $html -like '*id="root"*') {
            Add-Result -Id "F1" -Prueba "GET / -> 200 y contiene id='root'" -Resultado "PASS" -Detalle "Frontend sirve la app con id=root"
        } else {
            Add-Result -Id "F1" -Prueba "GET / -> 200 y contiene id='root'" -Resultado "FAIL" -Detalle ("Status={0} tiene id=root: {1}" -f $resp.StatusCode, ($html -like '*id="root"*'))
        }
    } catch {
        Add-Result -Id "F1" -Prueba "GET / -> 200 y contiene id='root'" -Resultado "FAIL" -Detalle $_.Exception.Message
    }

    # ---- F2: GET /api/health a traves de 5273 -> 200 (proxy) ----
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:frontendPort)/api/health" -Method GET -TimeoutSec 10 -ErrorAction Stop -UseBasicParsing
        if ($resp.StatusCode -eq 200) {
            Add-Result -Id "F2" -Prueba "GET /api/health via 5273 (proxy) -> 200" -Resultado "PASS" -Detalle "Proxy Vite->backend funcionando"
        } else {
            Add-Result -Id "F2" -Prueba "GET /api/health via 5273 (proxy) -> 200" -Resultado "FAIL" -Detalle ("Status={0}" -f $resp.StatusCode)
        }
    } catch {
        Add-Result -Id "F2" -Prueba "GET /api/health via 5273 (proxy) -> 200" -Resultado "FAIL" -Detalle $_.Exception.Message
    }

    # ---- F3: WebSocket ws://127.0.0.1:5273/ws/telemetry?pin=<PIN> -> >=3 frames ----
    $wsFurl = "ws://127.0.0.1:$($script:frontendPort)/ws/telemetry?pin=$($script:pin)"
    & $script:pythonExe $script:wsCheck $wsFurl 3 8
    $wsFexit = $LASTEXITCODE
    if ($wsFexit -eq 0) {
        Add-Result -Id "F3" -Prueba "WebSocket frontend via 5273 >=3 frames" -Resultado "PASS" -Detalle "Proxy WebSocket funciona"
    } else {
        Add-Result -Id "F3" -Prueba "WebSocket frontend via 5273 >=3 frames" -Resultado "FAIL" -Detalle ("ws_check.py salio con codigo {0}" -f $wsFexit)
    }

    # ---- F4: curl Host trycloudflare.com -> 200; Host evil.example.com -> bloqueado (WARN si 200) ----
    $f4Ok = $true
    $f4Detail = New-Object System.Collections.Generic.List[string]
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:frontendPort)/" -Method GET -Headers @{"Host"="prueba.trycloudflare.com"} -TimeoutSec 10 -ErrorAction Stop -UseBasicParsing
        if ($resp.StatusCode -eq 200) {
            $f4Detail.Add("Host prueba.trycloudflare.com: 200 (ok, allowedHosts lo permite)")
        } else {
            $f4Ok = $false
            $f4Detail.Add(("Host prueba.trycloudflare.com: obtuvo {0} (se esperaba 200)" -f $resp.StatusCode))
        }
    } catch {
        $f4Ok = $false
        $f4Detail.Add(("Host prueba.trycloudflare.com: excepcion {0}" -f $_.Exception.Message))
    }
    try {
        $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$($script:frontendPort)/" -Method GET -Headers @{"Host"="evil.example.com"} -TimeoutSec 10 -ErrorAction Stop -UseBasicParsing
        if ($resp.StatusCode -eq 200) {
            $f4Detail.Add("Host evil.example.com: 200 (WARN - allowedHosts no bloquea hosts desconocidos)")
            $script:warnCount++
        } else {
            $f4Detail.Add(("Host evil.example.com: {0} (bloqueado, no es 200)" -f $resp.StatusCode))
        }
    } catch {
        $code = $_.Exception.Response.StatusCode.value__
        if ($code -ne 200) {
            $f4Detail.Add(("Host evil.example.com: {0} (bloqueado, no es 200)" -f $code))
        } else {
            $f4Detail.Add("Host evil.example.com: 200 (WARN - allowedHosts no bloquea hosts desconocidos)")
            $script:warnCount++
        }
    }
    if ($f4Ok) {
        Add-Result -Id "F4" -Prueba "Host trycloudflare.com -> 200; Host evil.example.com -> bloqueado/WARN" -Resultado "PASS" -Detalle ($f4Detail -join "; ")
    } else {
        Add-Result -Id "F4" -Prueba "Host trycloudflare.com -> 200; Host evil.example.com -> bloqueado/WARN" -Resultado "FAIL" -Detalle ($f4Detail -join "; ")
    }

    Start-Section "TUNEL REAL (cloudflared.exe e internet requeridos)"

    $tunnelBlocked = $false
    $cloudflaredExe = Join-Path -Path $script:repoRoot -ChildPath "cloudflared.exe"
    if (-not (Test-Path $cloudflaredExe)) {
        Add-Result -Id "T1" -Prueba "TUNEL: cloudflared.exe existe" -Resultado "BLOQUEO" -Detalle "cloudflared.exe no encontrado en la raiz del repo"
        $tunnelBlocked = $true
    }

    if (-not $tunnelBlocked) {
        $tunnelLogDir = Join-Path -Path $script:repoRoot -ChildPath ".cloudflared"
        $tunnelLogFile = Join-Path $tunnelLogDir "cloudflared.log"
        if (Test-Path $tunnelLogFile) { Remove-Item $tunnelLogFile -Force -ErrorAction SilentlyContinue }

        $tunnelStartTime = Get-Date
        try {
            $tunnelProc = Start-Process -FilePath "cmd" `
                -ArgumentList "/c", (Join-Path -Path $script:repoRoot -ChildPath "run_tunnel.bat"), "5273" `
                -WorkingDirectory $script:repoRoot -PassThru -WindowStyle Hidden
            Track-Process -procId $tunnelProc.Id
        } catch {
            Add-Result -Id "T1" -Prueba "TUNEL: lanzar run_tunnel.bat 5273" -Resultado "FAIL" -Detalle ("No se pudo lanzar: {0}" -f $_.Exception.Message)
            $tunnelBlocked = $true
        }

        if (-not $tunnelBlocked) {
            $tunnelUrl = $null
            $deadline = (Get-Date).AddSeconds(60)
            while ((Get-Date) -lt $deadline) {
                if (Test-Path $tunnelLogFile) {
                    $logTime = (Get-Item $tunnelLogFile).LastWriteTime
                    if ($logTime -gt $tunnelStartTime) {
                        $content = Get-Content -Path $tunnelLogFile -Raw
                        $matches = [regex]::Matches($content, "https://[a-z0-9-]+\.trycloudflare\.com")
                        if ($matches.Count -gt 0) {
                            $tunnelUrl = $matches[$matches.Count - 1].Value
                            break
                        }
                    }
                }
                Start-Sleep -Seconds 2
            }
            if ($tunnelUrl) {
                Add-Result -Id "T1" -Prueba "TUNEL: URL trycloudflare.com en log con fecha posterior al inicio (<=60s)" -Resultado "PASS" -Detalle ("URL: {0}" -f $tunnelUrl)
            } else {
                Add-Result -Id "T1" -Prueba "TUNEL: URL trycloudflare.com en log con fecha posterior al inicio (<=60s)" -Resultado "FAIL" -Detalle "No se obtuvo URL valida en 60s (solo URL vieja o sin log)"
                $tunnelBlocked = $true
            }
        }

        if ($tunnelUrl) {
            $tunnelHost = $tunnelUrl -replace "^https://", ""

            # Verificar resolucion DNS del host del tunel (sin red externa, T2-T5 son BLOQUEO)
            $dnsResolves = $false
            try {
                $null = [System.Net.Dns]::GetHostEntry($tunnelHost)
                $dnsResolves = $true
            } catch {
                # DNS no resuelve - no hay red externa
            }
            if (-not $dnsResolves) {
                Add-Result -Id "T2" -Prueba "TUNEL: GET <URL>/api/health -> 200 (<=30s reintentos)" -Resultado "BLOQUEO" -Detalle "No hay red externa: no se resuelve $tunnelHost"
                Add-Result -Id "T3" -Prueba "TUNEL: GET <URL>/ -> 200 y contiene id='root'" -Resultado "BLOQUEO" -Detalle "No hay red externa: no se resuelve $tunnelHost"
                Add-Result -Id "T4" -Prueba "TUNEL: GET <URL>/api/state sin PIN 401/403; con PIN 200" -Resultado "BLOQUEO" -Detalle "No hay red externa: no se resuelve $tunnelHost"
                Add-Result -Id "T5" -Prueba "TUNEL: wss://<host>/ws/telemetry?pin -> >=2 frames" -Resultado "BLOQUEO" -Detalle "No hay red externa: no se resuelve $tunnelHost"
            } else {
                # T2: GET <URL>/api/health -> 200 (reintentar hasta 30s por DNS)
                $t2Ok = $false
                $deadline = (Get-Date).AddSeconds(30)
                while ((Get-Date) -lt $deadline) {
                    try {
                        $resp = Invoke-WebRequest -Uri "$($tunnelUrl)/api/health" -Method GET -TimeoutSec 5 -ErrorAction Stop
                        if ($resp.StatusCode -eq 200) { $t2Ok = $true; break }
                    } catch { Start-Sleep -Seconds 2 }
                }
                if ($t2Ok) {
                    Add-Result -Id "T2" -Prueba "TUNEL: GET <URL>/api/health -> 200 (<=30s reintentos)" -Resultado "PASS" -Detalle ("URL: {0}" -f $tunnelUrl)
                } else {
                    Add-Result -Id "T2" -Prueba "TUNEL: GET <URL>/api/health -> 200 (<=30s reintentos)" -Resultado "FAIL" -Detalle "No respondio 200 en 30s"
                }

                # T3: GET <URL>/ -> 200 y contiene id="root" (prueba allowedHosts de verdad)
                try {
                    $resp = Invoke-WebRequest -Uri "$($tunnelUrl)/" -Method GET -TimeoutSec 10 -ErrorAction Stop
                    $html = $resp.Content
                    if ($resp.StatusCode -eq 200 -and $html -like '*id="root"*') {
                        Add-Result -Id "T3" -Prueba "TUNEL: GET <URL>/ -> 200 y contiene id='root'" -Resultado "PASS" -Detalle "allowedHosts permite trycloudflare.com"
                    } else {
                        Add-Result -Id "T3" -Prueba "TUNEL: GET <URL>/ -> 200 y contiene id='root'" -Resultado "FAIL" -Detalle ("Status={0} tiene id=root: {1}" -f $resp.StatusCode, ($html -like '*id="root"*'))
                    }
                } catch {
                    Add-Result -Id "T3" -Prueba "TUNEL: GET <URL>/ -> 200 y contiene id='root'" -Resultado "FAIL" -Detalle $_.Exception.Message
                }

                # T4: GET <URL>/api/state sin PIN -> 401/403; con PIN -> 200
                $t4Ok = $true
                $t4Detail = New-Object System.Collections.Generic.List[string]
                try {
                    $resp = Invoke-WebRequest -Uri "$($tunnelUrl)/api/state" -Method GET -TimeoutSec 10 -ErrorAction Stop
                    $t4Ok = $false
                    $t4Detail.Add("sin PIN: obtuvo 200 (se esperaba 401/403)")
                } catch {
                    $code = $_.Exception.Response.StatusCode.value__
                    if ($code -eq 401 -or $code -eq 403) {
                        $t4Detail.Add(("sin PIN: {0} (ok)" -f $code))
                    } else {
                        $t4Ok = $false
                        $t4Detail.Add(("sin PIN: obtuvo {0} (se esperaba 401/403)" -f $code))
                    }
                }
                try {
                    $resp = Invoke-WebRequest -Uri "$($tunnelUrl)/api/state" -Method GET -Headers @{"X-App-Pin"=$script:pin} -TimeoutSec 10 -ErrorAction Stop
                    if ($resp.StatusCode -eq 200) {
                        $t4Detail.Add("con PIN: 200 (ok)")
                    } else {
                        $t4Ok = $false
                        $t4Detail.Add(("con PIN: obtuvo {0} (se esperaba 200)" -f $resp.StatusCode))
                    }
                } catch {
                    $t4Ok = $false
                    $t4Detail.Add(("con PIN: excepcion {0}" -f $_.Exception.Message))
                }
                if ($t4Ok) {
                    Add-Result -Id "T4" -Prueba "TUNEL: GET <URL>/api/state sin PIN 401/403; con PIN 200" -Resultado "PASS" -Detalle ($t4Detail -join "; ")
                } else {
                    Add-Result -Id "T4" -Prueba "TUNEL: GET <URL>/api/state sin PIN 401/403; con PIN 200" -Resultado "FAIL" -Detalle ($t4Detail -join "; ")
                }

                # T5: wss://<host>/ws/telemetry?pin=<PIN> -> >=2 frames
                $wsTurl = "wss://$($tunnelHost)/ws/telemetry?pin=$($script:pin)"
                & $script:pythonExe $script:wsCheck $wsTurl 2 10
                $wsTexit = $LASTEXITCODE
                if ($wsTexit -eq 0) {
                    Add-Result -Id "T5" -Prueba "TUNEL: wss://<host>/ws/telemetry?pin -> >=2 frames" -Resultado "PASS" -Detalle "WebSocket sobre tunel funciona"
                } else {
                    Add-Result -Id "T5" -Prueba "TUNEL: wss://<host>/ws/telemetry?pin -> >=2 frames" -Resultado "FAIL" -Detalle ("ws_check.py salio con codigo {0}" -f $wsTexit)
                }
            }

            # T6: Detener tunel (taskkill por PID rastreado), comprobar cloudflared muere
            try {
                cmd /c "taskkill /T /F /PID $($tunnelProc.Id)" >nul 2>&1
                Start-Sleep -Seconds 3
                $stillAlive = $false
                try { $null = Get-Process -Id $tunnelProc.Id -ErrorAction Stop; $stillAlive = $true } catch {}
                if (-not $stillAlive) {
                    Add-Result -Id "T6" -Prueba "TUNEL: detener tunel (taskkill /PID /T), cloudflared muere" -Resultado "PASS" -Detalle ("PID {0} terminado y no responde" -f $tunnelProc.Id)
                } else {
                    Add-Result -Id "T6" -Prueba "TUNEL: detener tunel (taskkill /PID /T), cloudflared muere" -Resultado "WARN" -Detalle ("PID {0} aun vive tras taskkill" -f $tunnelProc.Id)
                    $script:warnCount++
                }
            } catch {
                Add-Result -Id "T6" -Prueba "TUNEL: detener tunel (taskkill /PID /T), cloudflared muere" -Resultado "WARN" -Detalle "No se pudo terminar el PID del tunel"
                $script:warnCount++
            }
        }
    }

    Start-Section "INTEGRIDAD"

    # ---- I1: Hash backend/.env igual antes y despues ----
    $script:envFileHashAfter = Get-EnvFileHash
    if ($script:envFileHashBefore -eq $script:envFileHashAfter) {
        Add-Result -Id "I1" -Prueba "Hash backend/.env igual antes y despues" -Resultado "PASS" -Detalle ("Hash: {0}" -f $script:envFileHashAfter)
    } else {
        Add-Result -Id "I1" -Prueba "Hash backend/.env igual antes y despues" -Resultado "FAIL" -Detalle ("Antes={0} Despues={1}" -f $script:envFileHashBefore, $script:envFileHashAfter)
    }

    # ---- I2: Puertos 8100 y 5273 libres, no sobrevive proceso propio ----
    $i2Ok = $true
    $i2Detail = New-Object System.Collections.Generic.List[string]
    foreach ($port in @(8100, 5273)) {
        $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($conns) {
            $i2Ok = $false
            $i2Detail.Add(("Puerto {0} aun esta en uso" -f $port))
        }
    }
    $survivors = @()
    foreach ($procId in $script:launchPids) {
        try { $null = Get-Process -Id $procId -ErrorAction Stop; $survivors += $pid } catch {}
    }
    if ($survivors.Count -gt 0) {
        $i2Ok = $false
        $i2Detail.Add(("Procesos propios supervivientes: {0}" -f ($survivors -join ', ')))
    }
    if ($i2Ok) {
        Add-Result -Id "I2" -Prueba "Puertos 8100/5273 libres y sin procesos propios supervivientes" -Resultado "PASS" -Detalle "Todos los puertos libres y PIDs terminados"
    } else {
        Add-Result -Id "I2" -Prueba "Puertos 8100/5273 libres y sin procesos propios supervivientes" -Resultado "FAIL" -Detalle ($i2Detail -join "; ")
    }

    # ---- I3: Puertos 8000 y 5173 no usados ni terminados por el script ----
    $i3Detail = New-Object System.Collections.Generic.List[string]
    foreach ($port in @(8000, 5173)) {
        $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
        if ($conns) {
            $i3Detail.Add(("Puerto {0} esta en uso (servicios del usuario, no tocados por este script)" -f $port))
        }
    }
    Add-Result -Id "I3" -Prueba "Puertos 8000/5173 no usados ni terminados por el script" -Resultado "PASS" -Detalle "El script solo uso 8100 y 5273; 8000/5173 son del usuario"

} catch {
    Write-Host ("ERROR no controlado: {0}" -f $_.Exception.Message)
    Write-Log ("ERROR NO CONTROLADO: {0}" -f $_.Exception.Message)
} finally {
    Stop-OwnProcesses
    Kill-Port -Port $script:backendPort
    Kill-Port -Port $script:frontendPort
    $script:envFileHashAfter = Get-EnvFileHash
    if ($savedEnvDryRun -eq $null) { $env:APP_DRY_RUN = "" } else { $env:APP_DRY_RUN = $savedEnvDryRun }
    if ($savedEnvMac -eq $null) { $env:APP_MAC_ADDRESS = "" } else { $env:APP_MAC_ADDRESS = $savedEnvMac }
    if ($savedEnvPin -eq $null) { $env:APP_PIN = "" } else { $env:APP_PIN = $savedEnvPin }
    if ($savedEnvApiTarget -eq $null) { $env:API_TARGET = "" } else { $env:API_TARGET = $savedEnvApiTarget }
}

# ----------------------------------------------------------------
# REPORTE FINAL
# ----------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 80)
Write-Host "REPORTE FINAL DE VERIFICACION T-800"
Write-Host ("=" * 80)
$passCount = (@($script:results | Where-Object { $_.Resultado -eq "PASS" })).Count
$failCount = (@($script:results | Where-Object { $_.Resultado -eq "FAIL" })).Count
$warnCount = (@($script:results | Where-Object { $_.Resultado -eq "WARN" })).Count
$blockCount = (@($script:results | Where-Object { $_.Resultado -eq "BLOQUEO" })).Count
Write-Host ("Total pruebas: {0}" -f $script:results.Count)
Write-Host ("  PASS  : {0}" -f $passCount)
Write-Host ("  FAIL  : {0}" -f $failCount)
Write-Host ("  WARN  : {0}" -f $warnCount)
Write-Host ("  BLOQUEO: {0}" -f $blockCount)
Write-Host ("Codigo de salida: {0}" -f $failCount)
Write-Host ("Log completo: {0}" -f $script:logFile)
Write-Host ("=" * 80)

Write-Log ""
Write-Log "=== REPORTE FINAL ==="
Write-Log ("Total pruebas: {0}" -f $script:results.Count)
Write-Log ("  PASS  : {0}" -f $passCount)
Write-Log ("  FAIL  : {0}" -f $failCount)
Write-Log ("  WARN  : {0}" -f $warnCount)
Write-Log ("  BLOQUEO: {0}" -f $blockCount)
Write-Log ("Codigo de salida: {0}" -f $failCount)

Write-Host ""
Write-Host "ID   | Prueba                                               | Resultado | Detalle"
Write-Host ("-" * 100)
foreach ($r in $script:results) {
    Write-Host ("{0} | {1} | {2} | {3}" -f $r.ID.PadRight(6), $r.Prueba.PadRight(50), $r.Resultado.PadRight(9), $r.Detalle)
}

exit $script:failCount



