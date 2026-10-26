@echo off
setlocal
title RPG Translator - Startup Diagnostics
cd /d "%~dp0"
echo Starting RPG Translator diagnostics...
echo.
if /I not "%~d0"=="D:" (
 echo Please extract ALL files into a folder on D: first.
 echo Current folder: %~dp0
 pause
 exit /b 1
)
if not exist "%~dp0runtime" mkdir "%~dp0runtime"
if not exist "%~dp0runtime" (
 echo Cannot create runtime folder on D:.
 pause
 exit /b 1
)
set "TEMP=%~dp0runtime"
set "TMP=%~dp0runtime"
echo Opening Windows PowerShell. Keep this window open.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Diagnostic.ps1"
echo.
echo Process ended. Exit code: %errorlevel%
echo If startup failed, please send a screenshot of this window.
pause
