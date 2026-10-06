@echo off
title Accensione PC via Home Assistant
echo Accendo la presa del PC via Home Assistant...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0presa.ps1" on
echo.
pause
