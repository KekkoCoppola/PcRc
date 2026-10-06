# Installa l'agent PcRc su questo PC: dipendenze Python, avvio automatico all'accesso, riavvio.
# Va rilanciato se la cartella del progetto cambia posto o nome.
#   powershell -ExecutionPolicy Bypass -File scripts\install_agent.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$agentDir = Join-Path $root 'agent'
$agent = Join-Path $agentDir 'agent.pyw'
if (-not (Test-Path (Join-Path $agentDir 'firebase_key.json'))) {
    throw 'Manca agent\firebase_key.json (chiave dell''account di servizio Firebase)'
}

# 1. Dipendenze
$pythonw = (Get-Command pythonw -ErrorAction Stop).Source
$python = Join-Path (Split-Path $pythonw) 'python.exe'
& $python -m pip install --quiet --disable-pip-version-check -r (Join-Path $agentDir 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'pip install fallito' }

# 2. Ferma gli agent PcRc attivi, anche se avviati da una vecchia cartella (es. RCPC)
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" |
    Where-Object { $_.CommandLine -match 'agent\.pyw' -and $_.CommandLine -match 'PcRc|RCPC' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force; "Agent fermato (PID $($_.ProcessId))" }

# 3. Avvio automatico all'accesso: un solo collegamento, verso questa cartella
$startup = [Environment]::GetFolderPath('Startup')
$old = Join-Path $startup 'agent.pyw - collegamento.lnk'
if (Test-Path $old) {
    Remove-Item $old
    'Rimosso il vecchio collegamento agent.pyw - collegamento.lnk'
}
$lnk = Join-Path $startup 'PcRc agent.lnk'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$shortcut.TargetPath = $pythonw
$shortcut.Arguments = "`"$agent`""
$shortcut.WorkingDirectory = $agentDir
$shortcut.Description = 'PcRc: agent per il controllo remoto del PC'
$shortcut.Save()
"Avvio automatico: $lnk"

# 4. Avvio adesso
Start-Process $pythonw -ArgumentList "`"$agent`"" -WorkingDirectory $agentDir
"Agent avviato da $agentDir (log: agent\agent.log)"
