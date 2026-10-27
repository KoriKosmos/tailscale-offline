@echo off
rem Offline Tailscale installer for Windows, for when PowerShell scripts are
rem blocked. Same steps as install.ps1, minus the signature check.
rem
rem Usage: install.cmd [stable^|unstable^|VERSION]

setlocal EnableDelayedExpansion

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=stable"
set "RELEASES=%~dp0releases"

set "ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"
if /i "%ARCH%"=="AMD64" (
    set "ARCH=amd64"
) else if /i "%ARCH%"=="ARM64" (
    set "ARCH=arm64"
) else if /i "%ARCH%"=="x86" (
    set "ARCH=x86"
) else (
    echo Unsupported architecture: %ARCH% 1>&2
    exit /b 1
)

if /i "%TARGET%"=="stable" goto :pointer
if /i "%TARGET%"=="unstable" goto :pointer
set "VERSION=%TARGET%"
goto :resolved
:pointer
if not exist "%RELEASES%\%TARGET%" (
    echo No %TARGET% version mirrored. Run mirror.sh first. 1>&2
    exit /b 1
)
set /p VERSION=<"%RELEASES%\%TARGET%"
:resolved

set "ARCHDIR=%RELEASES%\%VERSION%\%ARCH%"
set "MSI=%ARCHDIR%\tailscale-setup-%VERSION%-%ARCH%.msi"
if not exist "%MSI%" (
    echo Tailscale %VERSION% for %ARCH% is not in this mirror. 1>&2
    exit /b 1
)
if not exist "%ARCHDIR%\checksum" (
    echo Tailscale %VERSION% for %ARCH% is not in this mirror. 1>&2
    exit /b 1
)

echo Installing Tailscale %VERSION% (%ARCH%)...

set /p EXPECTED=<"%ARCHDIR%\checksum"
set "ACTUAL="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%MSI%" SHA256') do (
    if not defined ACTUAL set "ACTUAL=%%h"
)
rem Older certutil versions print the hash with spaces between bytes.
set "ACTUAL=!ACTUAL: =!"
if /i not "!ACTUAL!"=="!EXPECTED!" (
    echo Checksum verification failed ^(is the clone complete?^) 1>&2
    exit /b 1
)

rem No route to pkgs.tailscale.com, so turn off update checks and auto-updates.
rem Windows shows an admin prompt here if this window isn't elevated.
start "" /wait msiexec.exe /i "%MSI%" /passive /norestart TS_CHECKUPDATES=never TS_INSTALLUPDATES=never
set "RC=%ERRORLEVEL%"
if "%RC%"=="3010" (
    echo Installed. Restart Windows to finish.
) else if "%RC%"=="1602" (
    echo Installation cancelled. 1>&2
    exit /b 1
) else if not "%RC%"=="0" (
    echo msiexec failed with exit code %RC% 1>&2
    exit /b 1
)

if exist "%ProgramFiles%\Tailscale\tailscale.exe" "%ProgramFiles%\Tailscale\tailscale.exe" version

echo.
echo Installation complete!
echo Sign in from the Tailscale tray icon, or run: tailscale up
echo.
