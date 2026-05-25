@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

REM Clear conflicting auth vars from inherited environment
set "ANTHROPIC_API_KEY="
set "ANTHROPIC_AUTH_TOKEN="
set "ANTHROPIC_BASE_URL="

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
set "PORTABLE_CCS=%PORTABLE_DATA%\.cc-switch"
set "PORTABLE_CLAUDE=%PORTABLE_DATA%\.claude"
set "LIB_DIR=%SCRIPT_DIR%lib"

set "SYS_CCS=%USERPROFILE%\.cc-switch"
set "SYS_CLAUDE=%USERPROFILE%\.claude"

if not exist "%BIN_DIR%\claude.exe" (
  echo [ERROR] Claude Code not found: %BIN_DIR%\claude.exe
  pause & exit /b 1
)

:: =============================================
:: Setup portable directories
:: =============================================
if not exist "%PORTABLE_DATA%" mkdir "%PORTABLE_DATA%"
if not exist "%PORTABLE_CCS%" mkdir "%PORTABLE_CCS%"
if not exist "%PORTABLE_CLAUDE%" mkdir "%PORTABLE_CLAUDE%"

:: Migrate existing system data into portable folder (one-time)
if exist "%SYS_CCS%\cc-switch.db" (
  if not exist "%PORTABLE_CCS%\cc-switch.db" (
    echo   [migrate] Copying existing cc-switch data into portable folder...
    xcopy /e /i /y /q "%SYS_CCS%" "%PORTABLE_CCS%" >nul 2>&1
  )
)
if exist "%SYS_CLAUDE%" (
  if not exist "%PORTABLE_CLAUDE%\settings.json" (
    if not exist "%PORTABLE_CLAUDE%\.claude.json" (
      echo   [migrate] Copying existing claude data into portable folder...
      xcopy /e /i /y /q "%SYS_CLAUDE%" "%PORTABLE_CLAUDE%" >nul 2>&1
    )
  )
)

:: =============================================
:: Replace system .cc-switch and .claude with junctions to portable
:: =============================================
:: We keep the system path %USERPROFILE%\.cc-switch but make it a junction
:: pointing into our portable folder. cc-switch and claude write what they
:: think is the system path, but data lands in the portable folder.

call :ensure_junction "%SYS_CCS%" "%PORTABLE_CCS%"
if !errorlevel! NEQ 0 (
  echo   [ERROR] Cannot create junction for .cc-switch
  echo   Make sure no cc-switch.exe is running, then try again.
  pause & exit /b 1
)
call :ensure_junction "%SYS_CLAUDE%" "%PORTABLE_CLAUDE%"
if !errorlevel! NEQ 0 (
  echo   [ERROR] Cannot create junction for .claude
  pause & exit /b 1
)

set "CCS_DB=%PORTABLE_CCS%\cc-switch.db"

:: =============================================
:: Check if valid config exists
:: =============================================
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 1024 set "HAS_CONFIG=1"
)
if "!HAS_CONFIG!"=="1" goto :load_config

:: =============================================
:: First-run: open CC Switch and wait for DB
:: =============================================
echo.
echo =====================================
echo   First Run - Configure API
echo =====================================
echo.
echo   Opening CC Switch GUI...
echo   Add a Provider and save (no need to close CC Switch).
echo.
start "" "%BIN_DIR%\cc-switch.exe"

echo   Waiting for provider configuration...
set "WAIT_COUNT=0"
:wait_db
timeout /t 2 >nul 2>&1
set /a WAIT_COUNT+=1
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 1024 set "HAS_CONFIG=1"
)
if "!HAS_CONFIG!"=="1" goto :db_ready
if !WAIT_COUNT! GEQ 150 (
  echo   [!] Timeout waiting for provider config.
  pause & exit /b 1
)
goto :wait_db

:db_ready
echo   [ok] Provider detected, continuing...
timeout /t 1 >nul 2>&1

:load_config
:: =============================================
:: Read API config from DB
:: =============================================
set "TMP_URL=%TEMP%\ccs_url_%RANDOM%.txt"
set "TMP_KEY=%TEMP%\ccs_key_%RANDOM%.txt"

if exist "%LIB_DIR%\extract-config.ps1" (
  :: Retry up to 3 times in case DB is still being written
  for /l %%I in (1,1,3) do (
    if "!ANTHROPIC_AUTH_TOKEN!"=="" (
      powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\extract-config.ps1" "%CCS_DB%" "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
      if exist "!TMP_URL!" (
        set /p ANTHROPIC_BASE_URL=<"!TMP_URL!"
        set /p ANTHROPIC_AUTH_TOKEN=<"!TMP_KEY!"
        del "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
        echo   [ok] Config loaded
      ) else (
        timeout /t 2 >nul 2>&1
      )
    )
  )
)

if "!ANTHROPIC_AUTH_TOKEN!"=="" (
  echo   [!] Failed to load config.
  pause & exit /b 1
)

:: =============================================
:: Launch Claude Code
:: =============================================
echo   Mode: Direct ^| Data: portable folder
echo.
"%BIN_DIR%\claude.exe" %*

:: =============================================
:: Cleanup: remove junctions to leave no trace on host
:: =============================================
:: Only remove if they are still junctions (user might have replaced them)
call :remove_junction "%SYS_CCS%"
call :remove_junction "%SYS_CLAUDE%"

pause
exit /b 0

:: =============================================
:: Subroutine: ensure %1 is a junction pointing to %2
:: =============================================
:ensure_junction
set "LINK=%~1"
set "TARGET=%~2"
:: If LINK doesn't exist — create junction
if not exist "%LINK%" (
  mklink /J "%LINK%" "%TARGET%" >nul 2>&1
  if !errorlevel! EQU 0 (exit /b 0) else (exit /b 1)
)
:: Check if LINK is already a reparse point (junction or symlink)
fsutil reparsepoint query "%LINK%" >nul 2>&1
if !errorlevel! EQU 0 (
  :: Already a junction — assume it points correctly (idempotent)
  exit /b 0
)
:: It's a real directory. We already migrated content above, so remove and re-link.
rd "%LINK%" 2>nul
if exist "%LINK%" (
  rd /s /q "%LINK%" 2>nul
)
mklink /J "%LINK%" "%TARGET%" >nul 2>&1
if !errorlevel! EQU 0 (exit /b 0) else (exit /b 1)

:: =============================================
:: Subroutine: remove junction (only if it IS a junction, not real dir)
:: =============================================
:remove_junction
set "LINK=%~1"
if not exist "%LINK%" exit /b 0
:: Use fsutil to verify it's a reparse point before deleting
fsutil reparsepoint query "%LINK%" >nul 2>&1
if !errorlevel! EQU 0 (
  rd "%LINK%" >nul 2>&1
)
exit /b 0
