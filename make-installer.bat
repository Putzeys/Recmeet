@echo off
REM Builds dist\recmeet-setup.exe — the NSIS installer.
REM Calls package-win.bat first so dist\recmeet-windows is fresh, then
REM compiles the .nsi.
REM
REM Pre-req: NSIS installed (winget install NSIS.NSIS).
setlocal
cd /d "%~dp0"

call package-win.bat
if errorlevel 1 (
    echo *** package-win.bat failed, aborting installer step.
    exit /b 1
)

REM Find makensis.exe — installed default location is C:\Program Files (x86)\NSIS
set MAKENSIS=
for %%d in (
    "%PROGRAMFILES(X86)%\NSIS\makensis.exe"
    "%PROGRAMFILES%\NSIS\makensis.exe"
) do (
    if exist %%d set MAKENSIS=%%d
)
if not defined MAKENSIS (
    echo *** makensis.exe not found.
    echo *** Install NSIS first:
    echo ***     winget install NSIS.NSIS
    exit /b 1
)

REM Read RECMEET_CURRENT_VERSION out of AppVersion.swift to keep the
REM installer version in lock-step with the in-app version.
set VERSION=0.0.0
for /f "tokens=2 delims=()" %%v in ('findstr /c:"RECMEET_CURRENT_VERSION = AppVersion" Sources\RecmeetCore\Updater\AppVersion.swift') do (
    set VTUPLE=%%v
)
REM VTUPLE is now "0, 6, 0" — strip spaces, swap commas to dots
if defined VTUPLE (
    set VERSION=%VTUPLE: =%
    setlocal enabledelayedexpansion
    set VERSION=!VERSION:,=.!
    endlocal & set VERSION=%VERSION%
)

echo === makensis /DVERSION=%VERSION% recmeet.nsi ===
%MAKENSIS% /V2 /DVERSION=%VERSION% recmeet.nsi
if errorlevel 1 (
    echo *** makensis failed.
    exit /b 1
)

echo.
echo === Installer ready ===
dir dist\recmeet-setup.exe
echo.
echo Test:    dist\recmeet-setup.exe
echo Upload:  gh release upload v%VERSION% dist\recmeet-setup.exe --clobber
