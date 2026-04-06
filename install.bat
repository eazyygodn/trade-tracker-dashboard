@echo off
title Trade Tracker Pro EA Installer
echo.
echo  ============================================
echo   Trade Tracker Pro EA Installer
echo  ============================================
echo.
echo  Starting installer...
echo.

powershell -ExecutionPolicy Bypass -File "%~dp0installer.ps1"

if %errorlevel% neq 0 (
    echo.
    echo  If the installer did not open, right-click this file
    echo  and select "Run as administrator"
    echo.
    pause
)
