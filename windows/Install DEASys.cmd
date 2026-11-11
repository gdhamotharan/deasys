@echo off
rem Double-click installer for DEASys. It asks Windows for administrator rights, runs install.ps1 and keeps the window open
rem so that every message can be read. Nothing is installed until you have read the summary and accepted the terms.
setlocal
title DEASys installer
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo DEASys needs administrator rights to install. Windows will now ask for permission...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
cd /d "%~dp0"
if not exist "%~dp0install.ps1" (
  echo install.ps1 was not found next to this file. Unzip the whole DEASys package first, then run this again.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set RC=%errorlevel%
echo.
if %RC% neq 0 (
  echo The installer stopped with code %RC%. The messages above say why; the log is in %ProgramData%\DEASys\logs.
) else (
  echo The installer finished.
)
pause
exit /b %RC%
