# Rinomina la cartella del progetto D:\PROGETTI\RCPC -> D:\PROGETTI\PcRc.
#
# Va eseguito con Claude CHIUSO (la sessione tiene la cartella in uso) da un
# terminale aperto fuori dalla cartella, per esempio:
#   powershell -ExecutionPolicy Bypass -File D:\PROGETTI\RCPC\tools\rename_root_to_PcRc.ps1
#
# Passi: ferma l'agent, rinomina, aggiorna il collegamento di avvio automatico
# e .claude\launch.json, copia la memoria di Claude Code, riavvia l'agent.

$ErrorActionPreference = 'Stop'
$old = 'D:\PROGETTI\RCPC'
$new = 'D:\PROGETTI\PcRc'
Set-Location D:\PROGETTI

# 1. Ferma l'agent avviato da questa cartella
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -like "*$old\agent.pyw*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; "Agent fermato (PID $($_.ProcessId))" }
Start-Sleep -Seconds 1

# 2. Rinomina la cartella
Rename-Item $old 'PcRc'
"Cartella rinominata: $new"

# 3. Collegamento di avvio automatico dell'agent
$lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\agent.pyw - collegamento.lnk'
if (Test-Path $lnk) {
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $shortcut.TargetPath = "$new\agent.pyw"
    $shortcut.WorkingDirectory = $new
    $shortcut.Save()
    "Collegamento aggiornato: $($shortcut.TargetPath)"
}

# 4. Percorso del server di anteprima usato da Claude Code
$launch = "$new\.claude\launch.json"
if (Test-Path $launch) {
    (Get-Content $launch -Raw).Replace('D:\\PROGETTI\\RCPC\\', 'D:\\PROGETTI\\PcRc\\') |
        Set-Content $launch -NoNewline -Encoding utf8
    "launch.json aggiornato"
}

# 5. Memoria di Claude Code: la cartella progetto cambia nome, la memoria segue
$memOld = Join-Path $env:USERPROFILE '.claude\projects\D--PROGETTI-RCPC\memory'
$memNew = Join-Path $env:USERPROFILE '.claude\projects\D--PROGETTI-PcRc\memory'
if ((Test-Path $memOld) -and -not (Test-Path $memNew)) {
    New-Item -ItemType Directory -Force (Split-Path $memNew) | Out-Null
    Copy-Item $memOld $memNew -Recurse
    "Memoria Claude copiata in $memNew"
}

# 6. Riavvia l'agent dalla nuova cartella
Start-Process "$new\agent.pyw" -WorkingDirectory $new
"Agent riavviato da $new"
