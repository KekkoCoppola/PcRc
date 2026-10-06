@echo off
title Stacco presa PC via Home Assistant
echo ATTENZIONE: stacca la presa e toglie corrente al PC di colpo.
echo Per spegnere in sicurezza usa SPEGNI PC nell'app: spegne Windows, poi stacca la presa.
echo.
choice /C SN /M "Staccare comunque la presa"
if errorlevel 2 exit /b
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0presa.ps1" off
echo.
pause
