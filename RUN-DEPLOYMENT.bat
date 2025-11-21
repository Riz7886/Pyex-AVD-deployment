@echo off
echo ============================================
echo   NGINX DMZ Proxy Deployment Launcher
echo   Enterprise Security Edition
echo ============================================
echo.

REM Check if running as Administrator
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo ERROR: You need to run this as ADMINISTRATOR
    echo.
    echo Right-click this file and select "Run as administrator"
    echo.
    pause
    exit /b 1
)

echo [OK] Running as Administrator
echo.

REM Change to script directory
cd /d "%~dp0"

REM Check if script file exists
if not exist "Deploy-NGINX-Proxy-SECURE.ps1" (
    echo ERROR: Script file not found!
    echo.
    echo Looking for: Deploy-NGINX-Proxy-SECURE.ps1
    echo In folder: %CD%
    echo.
    echo Files in this folder:
    dir *.ps1
    echo.
    pause
    exit /b 1
)

echo [OK] Script file found
echo.

REM Set execution policy and run
echo Setting execution policy...
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force"

echo.
echo Launching deployment script...
echo.

PowerShell -NoProfile -ExecutionPolicy Bypass -File "Deploy-NGINX-Proxy-SECURE.ps1"

pause
