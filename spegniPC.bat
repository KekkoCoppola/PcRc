@echo off
title Accensione PC via Home Assistant
echo Invio comando di accensione a Home Assistant...

powershell -NoProfile -Command ^
  "$token = '<HA_TOKEN: vedi secrets.json>';" ^
  "$headers = @{ 'Authorization' = 'Bearer ' + $token; 'Content-Type' = 'application/json' };" ^
  "$body = '{\"entity_id\": \"switch.computer_presa_1\"}';" ^
  "try { $res = Invoke-RestMethod -Uri 'https://casacoppola.top/api/services/switch/turn_off' -Method Post -Headers $headers -Body $body; Write-Host 'ESITO: Presa accesa con successo!' -ForegroundColor Green; $res | Format-List } catch { Write-Host 'ERRORE:' $_.Exception.Message -ForegroundColor Red }"

echo.
pause