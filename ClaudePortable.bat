@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "CONFIG_DIR=%SCRIPT_DIR%data\.claude"
set "CONFIG_FILE=%SCRIPT_DIR%config\ccswitch\providers.json"
set "PORTABLE_CCS=%SCRIPT_DIR%data\cc-switch"
set "CCS_DB=%USERPROFILE%\.cc-switch\cc-switch.db"

if not exist "%BIN_DIR%\claude.exe" (
  echo [ERROR] Claude Code not found: %BIN_DIR%\claude.exe
  pause & exit /b 1
)
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%SCRIPT_DIR%data" mkdir "%SCRIPT_DIR%data"
if not exist "%PORTABLE_CCS%" mkdir "%PORTABLE_CCS%"

:: Sync DB from portable to home (only if portable is newer or home doesn't exist)
if exist "%PORTABLE_CCS%\cc-switch.db" (
  for %%F in ("%CCS_DB%") do if not exist "%%~dpF" mkdir "%%~dpF"
  if not exist "%CCS_DB%" (
    copy /y "%PORTABLE_CCS%\cc-switch.db" "%CCS_DB%" >nul 2>&1
  ) else (
    :: Compare timestamps: copy only if portable is newer
    set "CP_SYNC_SRC=%PORTABLE_CCS%\cc-switch.db"
    set "CP_SYNC_DST=%CCS_DB%"
    powershell -NoProfile -Command "if ((Get-Item $env:CP_SYNC_SRC).LastWriteTime -gt (Get-Item $env:CP_SYNC_DST).LastWriteTime) { exit 0 } else { exit 1 }" >nul 2>&1
    if !errorlevel! EQU 0 copy /y "%PORTABLE_CCS%\cc-switch.db" "%CCS_DB%" >nul 2>&1
  )
)

:: =============================================
:: Check if valid config exists (DB or JSON)
:: =============================================
set "HAS_CONFIG=0"

:: Check DB via sqlite3.exe (bundled)
if exist "%CCS_DB%" (
  if exist "%BIN_DIR%\sqlite3.exe" (
    for /f "usebackq delims=" %%N in (`"%BIN_DIR%\sqlite3.exe" "%CCS_DB%" "SELECT COUNT(*) FROM providers WHERE app_type='claude'" 2^>nul`) do (
      echo(%%N| findstr /r "^[0-9][0-9]*$" >nul 2>&1
      if !errorlevel! EQU 0 if %%N GTR 0 set "HAS_CONFIG=1"
    )
  )
)

:: Check providers.json as fallback
if "!HAS_CONFIG!"=="0" (
  if exist "%CONFIG_FILE%" (
    set "CP_CHK_FILE=%CONFIG_FILE%"
    powershell -NoProfile -Command "try { $d = Get-Content $env:CP_CHK_FILE -Raw | ConvertFrom-Json; foreach ($p in $d.providers) { if ($p.enabled -and $p.base_url -and $p.api_key) { exit 0 } }; exit 1 } catch { exit 1 }" >nul 2>&1
    if !errorlevel! EQU 0 set "HAS_CONFIG=1"
  )
)

if "!HAS_CONFIG!"=="1" goto :skip_first_run

:: =============================================
:: First-run setup
:: =============================================
echo.
echo =====================================
echo   1st Run - Configure API
echo =====================================
echo.
echo   1. Open CC Switch GUI (recommended)
echo   2. Manual API key entry
set /p CHOICE="  Choose [1/2]: "
if "!CHOICE!"=="" pause & exit /b 0
if "!CHOICE!"=="1" goto :first_run_gui
goto :first_run_manual

:first_run_gui
echo Opening CC Switch...
start /wait "" "%BIN_DIR%\cc-switch.exe"
:: If start /wait returned immediately (Electron app), wait for user
if not exist "%CCS_DB%" (
  echo   If CC Switch is still open, configure it then press any key...
  pause >nul
)
:: Re-check after GUI closes
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  if exist "%BIN_DIR%\sqlite3.exe" (
    for /f "usebackq delims=" %%N in (`"%BIN_DIR%\sqlite3.exe" "%CCS_DB%" "SELECT COUNT(*) FROM providers WHERE app_type='claude'" 2^>nul`) do (
      echo(%%N| findstr /r "^[0-9][0-9]*$" >nul 2>&1
      if !errorlevel! EQU 0 if %%N GTR 0 set "HAS_CONFIG=1"
    )
  )
)
if "!HAS_CONFIG!"=="1" (
  echo [ok] Provider detected
  if exist "%CCS_DB%" copy /y "%CCS_DB%" "%PORTABLE_CCS%\cc-switch.db" >nul
) else (
  echo [!] No provider found. Please try again.
  pause & exit /b 1
)
goto :skip_first_run

:first_run_manual
set /p API_BASE="  API Base URL: "
set /p AKEY="  API Key: "
if "!API_BASE!"=="" echo [ERROR] Required & pause & exit /b 1
if "!AKEY!"=="" echo [ERROR] Required & pause & exit /b 1
:: Write config via PowerShell using environment variables (avoid injection)
set "CP_API_BASE=!API_BASE!"
set "CP_API_KEY=!AKEY!"
set "CP_CONFIG_FILE=%CONFIG_FILE%"
powershell -NoProfile -Command "$base = $env:CP_API_BASE; $key = $env:CP_API_KEY; $out = $env:CP_CONFIG_FILE; $c = @{ providers = @( @{ id='custom'; name='Custom API'; type='anthropic'; base_url=$base; api_key=$key; enabled=$true } ); active_provider='custom'; proxy_port=15721; auto_start_proxy=$true }; $c | ConvertTo-Json -Depth 3 | Set-Content -Path $out -Encoding UTF8" >nul 2>&1
if !errorlevel! NEQ 0 (
  echo [ERROR] Failed to save config
  pause & exit /b 1
)
echo [ok] Config saved
:: Manual config: skip proxy, use direct mode with configured values
set "ANTHROPIC_BASE_URL=!API_BASE!"
set "ANTHROPIC_API_KEY=!AKEY!"
set "ANTHROPIC_AUTH_TOKEN=!AKEY!"
goto :run_claude

:skip_first_run
:: =============================================
:: Start CC Switch proxy
:: =============================================
set "CC_SWITCH_PORT=15721"
set "HAS_CCSWITCH=0"
set "WE_STARTED_CCS=0"

if not exist "%BIN_DIR%\cc-switch.exe" goto :no_ccswitch

:: Read port from DB if available
if exist "%CCS_DB%" (
  if exist "%BIN_DIR%\sqlite3.exe" (
    for /f "usebackq delims=" %%P in (`"%BIN_DIR%\sqlite3.exe" "%CCS_DB%" "SELECT listen_port FROM proxy_config WHERE app_type='claude' LIMIT 1" 2^>nul`) do (
      set "CC_SWITCH_PORT=%%P"
    )
  )
)

:: Check if already running
tasklist /fi "ImageName eq cc-switch.exe" 2>nul | find /i "cc-switch" >nul
if !errorlevel! EQU 0 (
  echo   CC Switch [already running]
) else (
  echo   Starting CC Switch... port !CC_SWITCH_PORT!
  start "" "%BIN_DIR%\cc-switch.exe"
  set "WE_STARTED_CCS=1"
)

:: Wait for proxy to be ready
set "TRIES=0"
:wp_loop
if !TRIES! GEQ 30 goto :wp_done
timeout /t 1 >nul 2>&1
set /a TRIES+=1
powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient('127.0.0.1', !CC_SWITCH_PORT!); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if !errorlevel! EQU 0 (
  set "HAS_CCSWITCH=1"
  goto :wp_done
)
goto :wp_loop
:wp_done

:no_ccswitch
if "!HAS_CCSWITCH!"=="1" (
  set "ANTHROPIC_BASE_URL=http://127.0.0.1:!CC_SWITCH_PORT!"
  set "ANTHROPIC_API_KEY=portable-key"
  set "ANTHROPIC_AUTH_TOKEN=portable-key"
  echo [ok] CC Switch proxy ready
  goto :run_claude
)

:: =============================================
:: Direct mode: read API config from DB or JSON
:: =============================================
echo [!] Proxy not ready, trying direct mode

:: Try sqlite3.exe first (bundled by CI)
if exist "%CCS_DB%" (
  if exist "%BIN_DIR%\sqlite3.exe" (
    :: Write raw JSON to temp file (unique name to avoid collision)
    set "CCS_TMP=%TEMP%\ccs_%RANDOM%%RANDOM%"
    set "CCS_TMP_RAW=!CCS_TMP!_raw.txt"
    "%BIN_DIR%\sqlite3.exe" "%CCS_DB%" "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1" > "!CCS_TMP_RAW!" 2>nul
    if exist "!CCS_TMP_RAW!" (
      :: Parse via PowerShell — use [IO.File]::WriteAllText to avoid BOM
      set "CCS_TMP_RAW=!CCS_TMP!_raw.txt"
      set "CCS_TMP_URL=!CCS_TMP!_url.txt"
      set "CCS_TMP_KEY=!CCS_TMP!_key.txt"
      powershell -NoProfile -Command "try { $raw = Get-Content $env:CCS_TMP_RAW -Raw -ErrorAction Stop; $cfg = $raw | ConvertFrom-Json; $e = $cfg.env; $k = $e.ANTHROPIC_AUTH_TOKEN; if (-not $k) { $k = $e.ANTHROPIC_API_KEY }; if ($e.ANTHROPIC_BASE_URL -and $k) { [IO.File]::WriteAllText($env:CCS_TMP_URL, $e.ANTHROPIC_BASE_URL); [IO.File]::WriteAllText($env:CCS_TMP_KEY, $k) } } catch {}" >nul 2>&1
      if exist "!CCS_TMP_URL!" (
        set /p ANTHROPIC_BASE_URL=<"!CCS_TMP_URL!"
        set /p ANTHROPIC_API_KEY=<"!CCS_TMP_KEY!"
        set /p ANTHROPIC_AUTH_TOKEN=<"!CCS_TMP_KEY!"
        del "!CCS_TMP_URL!" "!CCS_TMP_KEY!" >nul 2>&1
      )
      del "!CCS_TMP_RAW!" >nul 2>&1
    )
  )
)

:: Fallback: read from providers.json
if "!ANTHROPIC_API_KEY!"=="" (
  if exist "%CONFIG_FILE%" (
    set "CP_CONFIG_FILE=%CONFIG_FILE%"
    set "CCS_TMP2=%TEMP%\ccs_%RANDOM%%RANDOM%"
    set "CCS_TMP2_URL=!CCS_TMP2!_url.txt"
    set "CCS_TMP2_KEY=!CCS_TMP2!_key.txt"
    powershell -NoProfile -Command "$f = $env:CP_CONFIG_FILE; try { $d = Get-Content $f -Raw | ConvertFrom-Json; foreach ($p in $d.providers) { if ($p.enabled -and $p.base_url -and $p.api_key) { [IO.File]::WriteAllText($env:CCS_TMP2_URL, $p.base_url); [IO.File]::WriteAllText($env:CCS_TMP2_KEY, $p.api_key); break } } } catch {}" >nul 2>&1
    if exist "!CCS_TMP2_URL!" (
      set /p ANTHROPIC_BASE_URL=<"!CCS_TMP2_URL!"
      set /p ANTHROPIC_API_KEY=<"!CCS_TMP2_KEY!"
      del "!CCS_TMP2_URL!" "!CCS_TMP2_KEY!" >nul 2>&1
    )
  )
)

if "!ANTHROPIC_API_KEY!"=="" (
  echo [!] No API configured. Open CC Switch to add a Provider, then run again.
  pause & exit /b 1
)

:run_claude
:: =============================================
:: Launch Claude Code
:: =============================================
set "PROXY_TEXT=Direct mode"
if "!HAS_CCSWITCH!"=="1" set "PROXY_TEXT=CC Switch Proxy (port !CC_SWITCH_PORT!)"
echo.
echo =====================================
echo   Claude Code Portable
echo   Mode: !PROXY_TEXT!
echo =====================================
echo.
set "CLAUDE_CONFIG_DIR=%CONFIG_DIR%"
set "CLAUDE_HOME=%CONFIG_DIR%"
if "%~1"=="" (
  "%BIN_DIR%\claude.exe"
) else (
  "%BIN_DIR%\claude.exe" %*
)

:: Save DB back to portable on exit
:: First kill cc-switch (if we started it), then copy DB
if "!WE_STARTED_CCS!"=="1" goto :do_kill
goto :after_kill

:do_kill
:: Try graceful close first (WM_CLOSE)
taskkill /im cc-switch.exe >nul 2>&1
:: Wait up to 5 seconds for graceful exit
set "KWAIT=0"
:kill_wait
if !KWAIT! GEQ 5 goto :force_kill
timeout /t 1 >nul 2>&1
set /a KWAIT+=1
tasklist /fi "ImageName eq cc-switch.exe" 2>nul | find /i "cc-switch" >nul
if !errorlevel! NEQ 0 goto :after_kill
goto :kill_wait
:force_kill
taskkill /f /im cc-switch.exe >nul 2>&1

:after_kill
:: Now cc-switch is stopped, safe to copy DB
if exist "%CCS_DB%" (
  copy /y "%CCS_DB%" "%PORTABLE_CCS%\cc-switch.db" >nul 2>&1
  if !errorlevel! NEQ 0 (
    timeout /t 1 >nul 2>&1
    copy /y "%CCS_DB%" "%PORTABLE_CCS%\cc-switch.db" >nul 2>&1
  )
)
pause
exit /b 0
