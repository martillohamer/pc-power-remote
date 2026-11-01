# Espera hasta 40 s a .cloudflared\cloudflared.log, extrae la URL
# de trycloudflare.com (la mas reciente), la imprime y la copia al portapapeles.
# Solo acepta un log cuya fecha de modificacion sea posterior al inicio del script.
$logFile = Join-Path $PSScriptRoot ".cloudflared\cloudflared.log"
$timeout = 40
$elapsed = 0
$startTime = Get-Date
$url = $null

while ($elapsed -lt $timeout) {
    if (Test-Path $logFile) {
        $logTime = (Get-Item $logFile).LastWriteTime
        if ($logTime -gt $startTime) {
            $match = Select-String -Path $logFile -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -Last 1
            if ($match) {
                $url = $match.Matches[0].Value
                break
            }
        }
    }
    Start-Sleep -Seconds 2
    $elapsed += 2
}

if ($url) {
    Write-Host "URL del tunel Cloudflare: $url"
    $url | clip.exe
} else {
    Write-Host "No se encontro URL de trycloudflare.com en el log despues de ${timeout}s."
}
