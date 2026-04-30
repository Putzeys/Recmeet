@echo off
REM Builds the Windows GUI app AND bundles every Swift / Foundation runtime
REM DLL alongside it. Without this, end-user machines that don't have the
REM Swift toolchain installed get "swiftCore.dll not found" on launch.
REM
REM Output: dist\recmeet-windows\           (folder with .exe + DLLs)
REM         dist\recmeet-windows.zip        (zipped, ready to upload)
setlocal enabledelayedexpansion
cd /d "%~dp0"

call build-win.bat
if errorlevel 1 (
    echo *** build-win.bat failed, aborting package step.
    exit /b 1
)

set DIST=dist\recmeet-windows
if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%"

echo === Copying recmeet.exe ===
copy /y .build\x86_64-unknown-windows-msvc\release\RecmeetWin32App.exe "%DIST%\recmeet.exe" >nul

echo === Locating Swift runtime DLLs ===
set SWIFT_RUNTIME=
for /f "delims=" %%i in ('dir /b /ad /od "%LOCALAPPDATA%\Programs\Swift\Runtimes" 2^>nul') do (
    set SWIFT_RUNTIME=%LOCALAPPDATA%\Programs\Swift\Runtimes\%%i\usr\bin
)
if not defined SWIFT_RUNTIME (
    echo *** Couldn't find Swift runtime under %LOCALAPPDATA%\Programs\Swift\Runtimes
    echo *** Is the Swift toolchain installed?
    exit /b 1
)
echo Using runtime: %SWIFT_RUNTIME%

echo === Bundling all *.dll from the Swift runtime ===
copy /y "%SWIFT_RUNTIME%\*.dll" "%DIST%\" >nul
if errorlevel 1 (
    echo *** Failed to copy runtime DLLs.
    exit /b 1
)

echo === Bundling MSVC redistributable shims (if present) ===
REM These usually live in C:\Windows\System32 — some clean Windows installs lack them.
for %%f in (vcruntime140.dll vcruntime140_1.dll msvcp140.dll) do (
    if exist "C:\Windows\System32\%%f" (
        copy /y "C:\Windows\System32\%%f" "%DIST%\" >nul 2>&1
    )
)

echo === Zipping (flat layout — recmeet.exe at root) ===
REM Zip the *contents* of the staging folder, not the folder itself, so
REM extracted archives put recmeet.exe directly at the destination root.
REM This matters for two reasons:
REM   1. End users running Windows "Extract All" already get their own
REM      wrapper folder named after the zip, so a second nested folder
REM      would just be visual clutter.
REM   2. The in-app updater extracts the zip and looks for recmeet.exe
REM      at the staging root — a nested folder breaks it silently.
if exist dist\recmeet-windows.zip del /q dist\recmeet-windows.zip
pushd "%DIST%"
tar -a -c -f ..\recmeet-windows.zip *
popd

echo.
echo === Package OK ===
dir "%DIST%\*.exe" "%DIST%\*.dll" 2>nul | find "File(s)"
echo.
echo Local test: open "%DIST%\recmeet.exe" in Explorer and double-click.
echo Upload:     gh release upload v0.4.0 dist\recmeet-windows.zip --clobber --repo Putzeys/Recmeet
