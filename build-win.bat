@echo off
REM Build the Windows GUI app with the embedded recmeet icon.
REM Run this from "x64 Native Tools Command Prompt for VS 2022" so that
REM both rc.exe and swift are on PATH.
setlocal
cd /d "%~dp0"

REM Close any running instance so the linker can overwrite the .exe.
taskkill /IM RecmeetWin32App.exe >nul 2>&1
if errorlevel 1 (
    REM Wasn't running — that's fine.
    set _RECMEET_WAS_RUNNING=0
) else (
    REM Give Windows a moment to release the file handle.
    timeout /t 1 /nobreak >nul
    set _RECMEET_WAS_RUNNING=1
)

if not exist .build mkdir .build

echo === Compiling icon resource (rc.exe) ===
rc /nologo /fo .build\recmeet.res Sources\RecmeetWin32App\recmeet.rc
if errorlevel 1 goto :error

echo === swift build -c release --product RecmeetWin32App ===
swift build -c release --product RecmeetWin32App ^
    -Xlinker .build\recmeet.res
if errorlevel 1 goto :error

echo.
echo === Build OK ===
echo Run: .build\x86_64-unknown-windows-msvc\release\RecmeetWin32App.exe
goto :eof

:error
echo === Build failed ===
exit /b 1
