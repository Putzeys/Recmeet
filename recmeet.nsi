; recmeet — NSIS installer script.
; Built by make-installer.bat after package-win.bat has produced
; dist\recmeet-windows\ with recmeet.exe + bundled DLLs.

!define APPNAME           "recmeet"
!define COMPANYNAME       "Putzeys"
!define DESCRIPTION       "Mic + system audio recorder for meeting transcription"
!define HELPURL           "https://github.com/Putzeys/Recmeet"

; Version is passed in from the build script via /D:
;   makensis /DVERSION=0.6.0 recmeet.nsi
!ifndef VERSION
    !define VERSION "0.0.0"
!endif

Name              "${APPNAME}"
Icon              "Sources\RecmeetWin32App\recmeet.ico"
UninstallIcon     "Sources\RecmeetWin32App\recmeet.ico"
OutFile           "dist\recmeet-setup.exe"
InstallDir        "$LOCALAPPDATA\${APPNAME}"
RequestExecutionLevel user        ; per-user install — no admin prompt
ShowInstDetails   show
ShowUninstDetails show
SetCompressor /SOLID lzma

VIProductVersion "${VERSION}.0"
VIAddVersionKey  "ProductName"     "${APPNAME}"
VIAddVersionKey  "CompanyName"     "${COMPANYNAME}"
VIAddVersionKey  "FileDescription" "${DESCRIPTION}"
VIAddVersionKey  "FileVersion"     "${VERSION}"

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "install"
    SetOutPath "$INSTDIR"
    File /r "dist\recmeet-windows\*"

    ; Start Menu shortcut
    CreateDirectory "$SMPROGRAMS\${APPNAME}"
    CreateShortcut  "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" \
                    "$INSTDIR\recmeet.exe" "" "$INSTDIR\recmeet.exe" 0

    ; Desktop shortcut
    CreateShortcut  "$DESKTOP\${APPNAME}.lnk" \
                    "$INSTDIR\recmeet.exe" "" "$INSTDIR\recmeet.exe" 0

    ; Uninstaller
    WriteUninstaller "$INSTDIR\uninstall.exe"

    ; "Apps & features" registry entry
    !define UNINST_KEY \
        "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
    WriteRegStr   HKCU "${UNINST_KEY}" "DisplayName"     "${APPNAME}"
    WriteRegStr   HKCU "${UNINST_KEY}" "DisplayIcon"     "$INSTDIR\recmeet.exe,0"
    WriteRegStr   HKCU "${UNINST_KEY}" "DisplayVersion"  "${VERSION}"
    WriteRegStr   HKCU "${UNINST_KEY}" "Publisher"       "${COMPANYNAME}"
    WriteRegStr   HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr   HKCU "${UNINST_KEY}" "URLInfoAbout"    "${HELPURL}"
    WriteRegStr   HKCU "${UNINST_KEY}" "UninstallString" "$INSTDIR\uninstall.exe"
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify"        1
    WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair"        1
SectionEnd

Section "uninstall"
    ; Try to close any running instance before deleting binaries.
    nsExec::Exec 'taskkill /F /IM recmeet.exe'

    Delete "$DESKTOP\${APPNAME}.lnk"
    Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
    RMDir  "$SMPROGRAMS\${APPNAME}"

    Delete "$INSTDIR\uninstall.exe"
    RMDir  /r "$INSTDIR"

    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APPNAME}"
SectionEnd
