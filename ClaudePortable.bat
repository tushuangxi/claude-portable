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
set "LOCK_FILE=%PORTABLE_DATA%\.lock"
set "LOCK_FILE2=%PORTABLE_CCS%\.bind"
set "RUN_LOCK=%PORTABLE_DATA%\.running"

REM SCRIPT_DIR ends with \ (from %~dp0). When passed to PowerShell as
REM "value\", the trailing backslash escapes the closing quote, merging
REM the next argument. Use SCRIPT_DIR_PS without trailing backslash.
set "SCRIPT_DIR_PS=%SCRIPT_DIR%"
if "%SCRIPT_DIR_PS:~-1%"=="\" set "SCRIPT_DIR_PS=%SCRIPT_DIR_PS:~0,-1%"

set "SYS_CCS=%USERPROFILE%\.cc-switch"
set "SYS_CLAUDE=%USERPROFILE%\.claude"

if not exist "%BIN_DIR%\claude.exe" (
  echo [ERROR] Claude Code not found
  pause
  exit /b 1
)

:: =============================================
:: Handle --unlock argument
:: =============================================
if /i "%~1"=="--unlock" goto :do_unlock

goto :after_unlock

:do_unlock
if exist "%LOCK_FILE%" del /f /q "%LOCK_FILE%" >nul 2>&1
if exist "%LOCK_FILE2%" del /f /q "%LOCK_FILE2%" >nul 2>&1
echo   [ok] Unlock complete. Next run will rebind to current location.
pause
exit /b 0

:after_unlock

:: =============================================
:: Single-instance check (best effort)
:: =============================================
if not exist "%PORTABLE_DATA%" mkdir "%PORTABLE_DATA%" >nul 2>&1
if not exist "%RUN_LOCK%" goto :run_lock_done

set "PREV_PID="
for /f "usebackq delims=" %%P in ("%RUN_LOCK%") do if not defined PREV_PID set "PREV_PID=%%P"
if not defined PREV_PID goto :clear_stale_lock

tasklist /fi "PID eq !PREV_PID!" 2>nul | find "!PREV_PID!" >nul
if !errorlevel! EQU 0 (
  echo   [info] Another instance is already running.
  timeout /t 5 >nul 2>&1
  exit /b 1
)

:clear_stale_lock
del /f /q "%RUN_LOCK%" >nul 2>&1

:run_lock_done

:: =============================================
:: Drive binding check (BEFORE any side effects)
:: =============================================
set "LOCK_PRESENT=0"
if exist "%LOCK_FILE%" set "LOCK_PRESENT=1"
if exist "%LOCK_FILE2%" set "LOCK_PRESENT=1"
if "!LOCK_PRESENT!"=="0" goto :binding_done
if not exist "%LIB_DIR%\binding.ps1" goto :binding_done

set "ACTIVE_LOCK=%LOCK_FILE%"
if not exist "%LOCK_FILE%" set "ACTIVE_LOCK=%LOCK_FILE2%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\binding.ps1" check "%SCRIPT_DIR_PS%" "!ACTIVE_LOCK!" >nul 2>&1
set "BIND_RESULT=!errorlevel!"
if "!BIND_RESULT!"=="1" goto :binding_failed
if "!BIND_RESULT!"=="3" echo   [warn] Could not verify drive binding (continuing).
goto :binding_done

:binding_failed
echo.
echo   ============================================================
echo   [ERROR] This portable is locked to its original USB drive.
echo   ============================================================
echo.
echo   The current location does not match the bound device.
echo   This portable cannot be copied to other drives.
echo.
echo   Original owner can unbind with:
echo     ClaudePortable.bat --unlock
echo.
pause
exit /b 1

:binding_done

:: =============================================
:: Kill any existing cc-switch (junction creation/removal needs the path free)
:: =============================================
set "WE_STARTED_CCS=0"
tasklist /fi "ImageName eq cc-switch.exe" 2>nul | find /i "cc-switch.exe" >nul
if !errorlevel! EQU 0 (
  echo   [info] Stopping existing CC Switch...
  taskkill /im cc-switch.exe /t >nul 2>&1
  timeout /t 2 >nul 2>&1
  taskkill /f /im cc-switch.exe /t >nul 2>&1
)

:: =============================================
:: Setup portable directories
:: =============================================
if not exist "%PORTABLE_DATA%" mkdir "%PORTABLE_DATA%"
if not exist "%PORTABLE_CCS%" mkdir "%PORTABLE_CCS%"
if not exist "%PORTABLE_CLAUDE%" mkdir "%PORTABLE_CLAUDE%"

:: ensure_link below handles the system-data migration in a single pass:
:: it copies system data when portable is empty and backs up otherwise.
:: We removed the previous separate "migrate" xcopy that ran before
:: ensure_link because it would leave both system + portable populated,
:: forcing ensure_link into the "backup" branch unnecessarily.

:: =============================================
:: Create junctions (or symlinks if cross-volume)
:: =============================================
call :ensure_link "%SYS_CCS%" "%PORTABLE_CCS%"
if !errorlevel! NEQ 0 (
  echo   [ERROR] Cannot create link for .cc-switch
  echo   Try enabling Developer Mode in Windows Settings.
  pause
  exit /b 1
)
call :ensure_link "%SYS_CLAUDE%" "%PORTABLE_CLAUDE%"
if !errorlevel! NEQ 0 (
  echo   [ERROR] Cannot create link for .claude
  pause
  exit /b 1
)

set "CCS_DB=%PORTABLE_CCS%\cc-switch.db"

:: Write run-lock now that we own the session.
:: We need cmd.exe's PID (this script's host), not PowerShell's
:: (which exits immediately, making the lock useless for stale-detection).
:: wmic was deprecated and removed in Windows 11 24H2+; use PowerShell's
:: CIM API to get the parent (i.e. our cmd.exe) process id.
for /f "delims=" %%P in ('powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter ('ProcessId = ' + $PID)).ParentProcessId" 2^>nul') do set "MY_PID=%%P"
if not defined MY_PID set "MY_PID=%RANDOM%%RANDOM%"
echo !MY_PID! > "%RUN_LOCK%"

:: =============================================
:: Check config exists
:: =============================================
call :check_config
if "!HAS_CONFIG!"=="1" goto :load_config

:: =============================================
:: First-run: open CC Switch and wait
:: =============================================
echo.
echo =====================================
echo   First Run - Configure API
echo =====================================
echo.
echo   Opening CC Switch GUI...
echo   Add a Provider and save.
echo.
start "" "%BIN_DIR%\cc-switch.exe"
set "WE_STARTED_CCS=1"

echo   Waiting for provider configuration...
set "WAIT_COUNT=0"
:wait_db
timeout /t 2 >nul 2>&1
set /a WAIT_COUNT+=1
call :check_config
if "!HAS_CONFIG!"=="1" goto :db_ready
if !WAIT_COUNT! GEQ 150 (
  echo   [!] Timeout waiting for provider config.
  goto :error_cleanup
)
goto :wait_db

:db_ready
echo   [ok] Provider detected.
timeout /t 1 >nul 2>&1

:load_config
:: =============================================
:: Read API config
:: =============================================
set "TMP_URL=%TEMP%\ccs_url_%RANDOM%%RANDOM%.txt"
set "TMP_KEY=%TEMP%\ccs_key_%RANDOM%%RANDOM%.txt"

if exist "%LIB_DIR%\extract-config.ps1" (
  for /l %%I in (1,1,3) do (
    if "!ANTHROPIC_AUTH_TOKEN!"=="" (
      powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\extract-config.ps1" "%CCS_DB%" "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
      if exist "!TMP_URL!" (
        set /p ANTHROPIC_BASE_URL=<"!TMP_URL!"
        set /p ANTHROPIC_AUTH_TOKEN=<"!TMP_KEY!"
        REM Always delete temp files, even if set /p failed.
        REM These contain the API key; leaving them in %TEMP% is a
        REM credential leak that Windows may not clean up for weeks.
        del /f /q "!TMP_URL!" >nul 2>&1
        del /f /q "!TMP_KEY!" >nul 2>&1
        echo   [ok] Config loaded
      ) else (
        timeout /t 2 >nul 2>&1
      )
    )
  )
)
REM Defense in depth: clean up any stale temp files left from a
REM crashed previous run (best-effort match by prefix).
if exist "!TMP_URL!" del /f /q "!TMP_URL!" >nul 2>&1
if exist "!TMP_KEY!" del /f /q "!TMP_KEY!" >nul 2>&1

if "!ANTHROPIC_AUTH_TOKEN!"=="" (
  echo   [!] Failed to load config.
  goto :error_cleanup
)

:: =============================================
:: Create binding lock (first run only) + ensure mirror
:: =============================================
if not exist "%LIB_DIR%\binding.ps1" goto :binding_create_done
if exist "%LOCK_FILE%" goto :create_mirror

powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\binding.ps1" create "%SCRIPT_DIR_PS%" "%LOCK_FILE%" >nul 2>&1
if exist "%LOCK_FILE%" echo   [ok] Bound to current drive.

:create_mirror
if exist "%LOCK_FILE2%" goto :binding_create_done
powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\binding.ps1" create "%SCRIPT_DIR_PS%" "%LOCK_FILE2%" >nul 2>&1

:binding_create_done

:: =============================================
:: Launch Claude Code
:: =============================================
echo   Mode: Direct ^| Data: portable folder
echo.
"%BIN_DIR%\claude.exe" %*
goto :final_cleanup

:error_cleanup
call :do_cleanup
pause
exit /b 1

:final_cleanup
call :do_cleanup
pause
exit /b 0

:do_cleanup
if "!WE_STARTED_CCS!"=="1" (
  taskkill /im cc-switch.exe /t >nul 2>&1
  timeout /t 2 >nul 2>&1
  taskkill /f /im cc-switch.exe /t >nul 2>&1
)
call :remove_link "%SYS_CCS%"
call :remove_link "%SYS_CLAUDE%"
if exist "%RUN_LOCK%" del /f /q "%RUN_LOCK%" >nul 2>&1
exit /b 0

:check_config
set "HAS_CONFIG=0"
if not exist "%CCS_DB%" exit /b 0
if exist "%LIB_DIR%\check-config.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\check-config.ps1" "%CCS_DB%" >nul 2>&1
  if !errorlevel! EQU 0 set "HAS_CONFIG=1"
) else (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 4096 set "HAS_CONFIG=1"
)
exit /b 0

:ensure_link
set "LINK=%~1"
set "TARGET=%~2"
if not exist "%LINK%" (
  mklink /J "%LINK%" "%TARGET%" >nul 2>&1
  if !errorlevel! EQU 0 exit /b 0
  mklink /D "%LINK%" "%TARGET%" >nul 2>&1
  exit /b !errorlevel!
)
REM Check if it's already a junction/symlink pointing to our target
fsutil reparsepoint query "%LINK%" >nul 2>&1
if !errorlevel! EQU 0 exit /b 0
REM It's a real directory (not a junction). This means the user has
REM a pre-existing system install. Migrate its contents into our
REM portable folder BEFORE replacing with a junction. Never rd /s /q
REM a real user directory — that would destroy their data.
if exist "%LINK%\*" (
  REM Only migrate if portable target is empty. If it already has data,
  REM rename system dir as backup instead of merging — merging would
  REM let system files clobber portable files.
  set "TARGET_EMPTY=1"
  for /f %%X in ('dir /b /a "%TARGET%" 2^>nul ^| findstr /r ".*"') do set "TARGET_EMPTY=0"
  if "!TARGET_EMPTY!"=="1" (
    echo   [migrate] Moving existing %LINK% into portable folder...
    xcopy /e /i /y /q "%LINK%" "%TARGET%" >nul 2>&1
    REM CRITICAL: only rd if xcopy actually succeeded.
    REM xcopy returns 0 on success, 1-5 on partial/full failure.
    REM Previously rd ran unconditionally → on disk-full or locked
    REM file, user's data was destroyed.
    if !errorlevel! EQU 0 (
      rd /s /q "%LINK%" 2>nul
    ) else (
      echo   [ERROR] xcopy failed (code !errorlevel!^), keeping %LINK% intact
      exit /b 1
    )
  ) else (
    REM Portable target not empty — back up system dir with timestamp.
    REM wmic was removed in Windows 11 24H2+. Use PowerShell to get
    REM the local time. Format: yyyyMMddHHmmss (14 chars), matching
    REM the previous wmic LocalDateTime layout.
    for /f "delims=" %%T in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMddHHmmss" 2^>nul') do set "TS=%%T"
    if not defined TS set "TS=%RANDOM%%RANDOM%"
    echo   [warn] Portable target not empty, backing up system dir...
    ren "%LINK%" "%~n1.before-portable.!TS!" >nul 2>&1
  )
  if exist "%LINK%" (
    REM Could not remove or rename — files may be locked. Last-resort rename.
    ren "%LINK%" "%~n1.bak.%RANDOM%" >nul 2>&1
  )
)
if exist "%LINK%" rd "%LINK%" 2>nul
mklink /J "%LINK%" "%TARGET%" >nul 2>&1
if !errorlevel! EQU 0 exit /b 0
mklink /D "%LINK%" "%TARGET%" >nul 2>&1
exit /b !errorlevel!

:remove_link
set "LINK=%~1"
if not exist "%LINK%" exit /b 0
fsutil reparsepoint query "%LINK%" >nul 2>&1
if !errorlevel! EQU 0 rd "%LINK%" >nul 2>&1
exit /b 0
