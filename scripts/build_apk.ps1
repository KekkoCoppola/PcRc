# Compila l'APK release con i segreti di ..\secrets.json e copia quello arm64 in dist\.
#   powershell -ExecutionPolicy Bypass -File scripts\build_apk.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$secrets = Join-Path $root 'secrets.json'
if (-not (Test-Path $secrets)) { throw "Manca $secrets (modello: secrets.example.json)" }
if (-not (Test-Path (Join-Path $root 'app\android\app\google-services.json'))) {
    throw 'Manca app\android\app\google-services.json: python tools\firebase_android_app.py'
}

$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = Join-Path $env:USERPROFILE 'flutter\bin\flutter.bat' }

Push-Location (Join-Path $root 'app')
try {
    & $flutter build apk --release --split-per-abi "--dart-define-from-file=$secrets"
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk fallito (codice $LASTEXITCODE)" }
} finally {
    Pop-Location
}

$version = (Select-String -Path (Join-Path $root 'app\pubspec.yaml') -Pattern '^version:\s*([^+\s]+)').Matches[0].Groups[1].Value
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$out = Join-Path $dist "PcRc-$version-arm64-v8a.apk"
Copy-Item (Join-Path $root 'app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk') $out -Force

$apk = Get-Item $out
"APK pronto: $($apk.FullName) ($([math]::Round($apk.Length / 1MB, 1)) MB)"
