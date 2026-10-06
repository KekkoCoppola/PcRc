# Accende o spegne la presa smart del PC tramite Home Assistant.
# Indirizzo, token ed entita' vengono da ..\secrets.json.
#   powershell -ExecutionPolicy Bypass -File scripts\presa.ps1 on|off
param(
    [Parameter(Mandatory)][ValidateSet('on', 'off')][string]$Stato
)

$ErrorActionPreference = 'Stop'
$secrets = Get-Content (Join-Path $PSScriptRoot '..\secrets.json') -Raw | ConvertFrom-Json
$uri = "$($secrets.HA_BASE_URL.TrimEnd('/'))/api/services/switch/turn_$Stato"
$headers = @{ Authorization = "Bearer $($secrets.HA_TOKEN)"; 'Content-Type' = 'application/json' }
$body = @{ entity_id = $secrets.HA_SWITCH_ENTITY } | ConvertTo-Json

try {
    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body | Out-Null
    $esito = if ($Stato -eq 'on') { 'Presa accesa: il PC si avvia.' } else { 'Presa spenta.' }
    Write-Host "ESITO: $esito" -ForegroundColor Green
} catch {
    Write-Host "ERRORE: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
