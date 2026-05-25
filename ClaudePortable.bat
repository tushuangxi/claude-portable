@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

REM Enable ANSI escape codes
for /F %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"

echo.
echo %ESC%[38;5;220m  ██╗   ██╗██╗  ██╗   ██╗ ██████╗%ESC%[0m
echo %ESC%[38;5;220m  ╚██╗ ██╔╝██║  ╚██╗ ██╔╝██╔════╝%ESC%[0m
echo %ESC%[38;5;214m   ╚████╔╝ ██║   ╚████╔╝ ██║  ███╗%ESC%[0m
echo %ESC%[38;5;214m    ╚██╔╝  ██║    ╚██╔╝  ██║   ██║%ESC%[0m
echo %ESC%[38;5;166m     ██║   ███████╗██║   ╚██████╔╝%ESC%[0m
echo %ESC%[38;5;166m     ╚═╝   ╚══════╝╚═╝    ╚═════╝%ESC%[0m
echo.
echo      Claude Code Portable
echo.

set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "PORTABLE_DATA=%SCRIPT_DIR%data"
set "SANDBOX=%PORTABLE_DATA%\_home"
set "LIB_DIR=%SCRIPT_DIR%lib"
set "REAL_USERPROFILE=%USERPROFILE%"

if not exist "%BIN_DIR%\claude.exe" (
  echo [ERROR] Claude Code not found: %BIN_DIR%\claude.exe
  pause & exit /b 1
)

:: =============================================
:: Sandbox setup — hijack USERPROFILE/HOME
:: =============================================
:: All cc-switch and claude data lives in %SANDBOX% (= data\_home).
:: Programs that read %USERPROFILE%\.cc-switch land in our sandbox,
:: never touching the host machine.
if not exist "%PORTABLE_DATA%" mkdir "%PORTABLE_DATA%"
if not exist "%SANDBOX%" mkdir "%SANDBOX%"
if not exist "%SANDBOX%\.cc-switch" mkdir "%SANDBOX%\.cc-switch"
if not exist "%SANDBOX%\.claude" mkdir "%SANDBOX%\.claude"

:: Migrate existing portable DB (from old layout) to sandbox if present
if exist "%PORTABLE_DATA%\cc-switch\cc-switch.db" (
  if not exist "%SANDBOX%\.cc-switch\cc-switch.db" (
    copy /y "%PORTABLE_DATA%\cc-switch\cc-switch.db" "%SANDBOX%\.cc-switch\cc-switch.db" >nul 2>&1
  )
)

:: Hijack environment — cc-switch and claude both read these
set "USERPROFILE=%SANDBOX%"
set "HOME=%SANDBOX%"
set "APPDATA=%SANDBOX%\AppData\Roaming"
set "LOCALAPPDATA=%SANDBOX%\AppData\Local"
if not exist "%APPDATA%" mkdir "%APPDATA%"
if not exist "%LOCALAPPDATA%" mkdir "%LOCALAPPDATA%"

set "CCS_DB=%SANDBOX%\.cc-switch\cc-switch.db"

:: =============================================
:: Check if valid config exists
:: =============================================
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 1024 set "HAS_CONFIG=1"
)
if "!HAS_CONFIG!"=="1" goto :load_config

:: =============================================
:: First-run setup
:: =============================================
echo.
echo =====================================
echo   First Run - Configure API
echo =====================================
echo.
echo   Opening CC Switch GUI...
echo   Add a Provider, save, then close CC Switch.
echo.
start "" "%BIN_DIR%\cc-switch.exe"

:: Wait for cc-switch.exe to fully exit (Electron may fork; we need
:: to poll until no cc-switch.exe process exists at all)
:wait_ccs_close
timeout /t 2 >nul 2>&1
tasklist /fi "ImageName eq cc-switch.exe" 2>nul | find /i "cc-switch.exe" >nul
if !errorlevel! EQU 0 goto :wait_ccs_close

:: Give DB a moment to flush after exit
timeout /t 1 >nul 2>&1

:: Re-check
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 1024 set "HAS_CONFIG=1"
)
if "!HAS_CONFIG!"=="1" (
  echo   [ok] Provider detected
) else (
  echo   [!] No provider found. Please configure in CC Switch and try again.
  pause & exit /b 1
)

:load_config
:: =============================================
:: Read API config from sandbox DB
:: =============================================
set "TMP_URL=%TEMP%\ccs_url_%RANDOM%.txt"
set "TMP_KEY=%TEMP%\ccs_key_%RANDOM%.txt"

if exist "%LIB_DIR%\extract-config.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\extract-config.ps1" "%CCS_DB%" "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
  if exist "!TMP_URL!" (
    set /p ANTHROPIC_BASE_URL=<"!TMP_URL!"
    set /p ANTHROPIC_API_KEY=<"!TMP_KEY!"
    set "ANTHROPIC_AUTH_TOKEN=!ANTHROPIC_API_KEY!"
    del "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
    echo   [ok] Config loaded
  )
)

if "!ANTHROPIC_API_KEY!"=="" (
  echo   [!] Failed to load config. Run again or reconfigure CC Switch.
  pause & exit /b 1
)

:: =============================================
:: Launch Claude Code
:: =============================================
echo   Mode: Direct ^| Sandbox: %SANDBOX%
echo.
"%BIN_DIR%\claude.exe" %*

pause
exit /b 0
