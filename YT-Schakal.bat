@echo off
REM ============================================================
REM  Starter fuer YT-Schakal.ps1
REM  Doppelklick auf diese Datei startet das Script.
REM  -ExecutionPolicy Bypass gilt nur fuer diesen einen Aufruf
REM  und aendert nichts an den Systemeinstellungen.
REM ============================================================

cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0YT-Schakal.ps1"

if errorlevel 1 (
    echo.
    echo Das Script wurde mit einem Fehler beendet.
    pause
)
