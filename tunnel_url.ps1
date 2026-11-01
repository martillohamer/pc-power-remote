# Espera hasta 40 s a .cloudflared\cloudflared.log, extrae la URL
# de trycloudflare.com, la imprime y la copia al portapapeles.
$logFile = Join-Path $PSScriptRoot ".cloudflared\cloudflared.log"
$timeout = 40
$elapsed = 0
$url = $null

while ($elapsed -lt $timeout) {
    if (Test-Path $logFile) {
        $match = Select-String -Path $logFile -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' | Select-Object -First 1
        if ($match) {
            $url = $match.Matches[0].Value
            break
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
