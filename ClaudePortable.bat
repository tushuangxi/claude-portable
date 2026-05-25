@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "CONFIG_DIR=%SCRIPT_DIR%data\.claude"
set "CONFIG_FILE=%SCRIPT_DIR%config\ccswitch\providers.json"
set "FIRST_RUN=%SCRIPT_DIR%data\.configured"
set "PORTABLE_CCS=%SCRIPT_DIR%data\cc-switch"
set "CCS_DB=%USERPROFILE%\.cc-switch\cc-switch.db"

if not exist "%BIN_DIR%\claude.exe" (
  echo [ERROR] Claude Code not found
  pause & exit /b 1
)
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%SCRIPT_DIR%data" mkdir "%SCRIPT_DIR%data"
if not exist "%PORTABLE_CCS%" mkdir "%PORTABLE_CCS%"

:: Sync DB from portable to home
if exist "%PORTABLE_CCS%\cc-switch.db" (
  for %%F in ("%CCS_DB%") do if not exist "%%~dpF" mkdir "%%~dpF"
  if exist "%CCS_DB%" copy /y "%PORTABLE_CCS%\cc-switch.db" "%CCS_DB%" >nul
)

:: First-run setup
if not exist "%FIRST_RUN%" (
  echo.
  echo =====================================
  echo   1st Run - Configure API
  echo =====================================
  echo.
  echo   1. Open CC Switch GUI (recommended)
  echo   2. Manual API key entry
set /p CHOICE="  Choose [1/2]: "
  if "!CHOICE!"=="" pause & exit /b 0
  if "!CHOICE!"=="1" (
    echo Opening CC Switch...
    start "" "%BIN_DIR%\cc-switch.exe"
    echo Press any key after configuring...
    pause >nul
    powershell -NoProfile -Command "if (Test-Path (Join-Path $env:USERPROFILE '.cc-switch\cc-switch.db')) { exit 0 } else { exit 1 }" >nul 2>&1
    if !errorlevel! EQU 0 (
      type nul > "%FIRST_RUN%"
      echo [ok] Provider detected
    ) else (
      if exist "%CONFIG_FILE%" (
        for /f "usebackq delims=" %%x in (`powershell -NoProfile -Command "try { $d = Get-Content '%CONFIG_FILE%' -Raw | ConvertFrom-Json; if ($d.providers.Count -gt 0) { exit 0 } else { exit 1 } } catch { exit 1 }"`) do set "dummy=%%x"
        if !errorlevel! EQU 0 (
          type nul > "%FIRST_RUN%"
          echo [ok] Provider detected
        ) else (
          echo [!] No provider found
        )
      ) else (
        echo [!] No provider found
      )
    )
    pause & exit /b 0
  )
  set /p API_BASE="  API Base URL: "
  set /p AKEY="  API Key: "
  if "%API_BASE%"=="" echo [ERROR] Required & pause & exit /b 1
  if "%AKEY%"=="" echo [ERROR] Required & pause & exit /b 1
  powershell -NoProfile -Command "$c = @{ providers = @( @{ id='custom'; name='Custom API'; type='anthropic'; base_url='%API_BASE%'; api_key='%AKEY%'; enabled=$true } ); active_provider='custom'; proxy_port=15721; auto_start_proxy=$true }; $c | ConvertTo-Json -Depth 3 | Set-Content '%CONFIG_FILE%'" >nul 2>&1
  type nul > "%FIRST_RUN%"
  echo [ok] Config saved
)

:: Start CC Switch proxy
set "CC_SWITCH_PORT=15721"
set "HAS_CCSWITCH=0"
set "PROXY_MODE=Direct"

if exist "%BIN_DIR%\cc-switch.exe" (
  echo Starting CC Switch... (port !CC_SWITCH_PORT!)
  tasklist /fi "ImageName eq cc-switch.exe" 2>nul | find /i "cc-switch" >nul
  if !errorlevel! NEQ 0 (
    start "" "%BIN_DIR%\cc-switch.exe"
  ) else (
    echo   [already running]
  )
  set "TRIES=0"
  :wp_loop
  if !TRIES! GEQ 30 goto :wp_done
  timeout /t 1 >nul 2>&1
  set /a TRIES+=1
  powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient('127.0.0.1', !CC_SWITCH_PORT!); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
  if !errorlevel! EQU 0 set "HAS_CCSWITCH=1" & goto :wp_done
  goto :wp_loop
  :wp_done
)

if "!HAS_CCSWITCH!"=="1" (
  set "ANTHROPIC_BASE_URL=http://127.0.0.1:!CC_SWITCH_PORT!"
  set "ANTHROPIC_API_KEY=***
  set "ANTHROPIC_AUTH_TOKEN=***
  echo [ok] CC Switch proxy ready
  goto :run_claude
)

:: Direct mode: try SQLite DB first, then providers.json
echo [!] Proxy not ready, trying direct mode

:: 尝试从 SQLite 数据库读取（优先用 sqlite3.exe，回退 PowerShell）
if exist "%CCS_DB%" (
  if exist "%BIN_DIR%\sqlite3.exe" (
    for /f "usebackq tokens=1,2 delims=|" %%A in (`""%BIN_DIR%\sqlite3.exe" "%CCS_DB%" "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1"" 2^>nul`) do (
      for /f "usebackq delims=" %%X in (`powershell -NoProfile -Command "try { $cfg = '%%A' | ConvertFrom-Json; $env = $cfg.env; Write-Output $env.ANTHROPIC_BASE_URL; Write-Output $env.ANTHROPIC_AUTH_TOKEN } catch { }"`) do (
        if not defined ANTHROPIC_BASE_URL ( set "ANTHROPIC_BASE_URL=%%X"
        ) else ( set "ANTHROPIC_API_KEY=%%X & set "ANTHROPIC_AUTH_TOKEN=%%X )
      )
    )
  ) else (
    :: sqlite3.exe 不可用，尝试 PowerShell System.Data.SQLite
    for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { Add-Type -ErrorAction Stop; $c = [System.Data.SQLite.SQLiteConnection]::new('Data Source=%CCS_DB%'); $c.Open(); $cmd = $c.CreateCommand(); $cmd.CommandText = 'SELECT settings_config FROM providers WHERE app_type=''claude'' AND is_current=1 LIMIT 1'; $r = $cmd.ExecuteScalar(); $c.Close(); if ($r) { $cfg = $r | ConvertFrom-Json; $env = $cfg.env; Write-Output $env.ANTHROPIC_BASE_URL; Write-Output $env.ANTHROPIC_AUTH_TOKEN } } catch { }" 2^>nul`) do (
      if not defined ANTHROPIC_BASE_URL ( set "ANTHROPIC_BASE_URL=%%A"
      ) else ( set "ANTHROPIC_API_KEY=%%A & set "ANTHROPIC_AUTH_TOKEN=%%A )
    )
  )
)

:: 回退：从 providers.json 读取
if not defined ANTHROPIC_API_KEY (
  if exist "%CONFIG_FILE%" (
    for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { $d = Get-Content '%CONFIG_FILE%' -Raw | ConvertFrom-Json; $p = $d.providers[0]; if ($p) { Write-Output $p.base_url; Write-Output $p.api_key } } catch {}"`) do (
      if not defined ANTHROPIC_BASE_URL ( set "ANTHROPIC_BASE_URL=%%A"
      ) else ( set "ANTHROPIC_API_KEY=%%A" )
    )
  )
)

if not defined ANTHROPIC_API_KEY (
  echo [!] No API configured. Open CC Switch to add a Provider, then run again.
  pause & exit /b 1
)

:run_claude
set "PROXY_TEXT=Direct mode"
if "!HAS_CCSWITCH!"=="1" set "PROXY_TEXT=CC Switch Proxy (port !CC_SWITCH_PORT!)"
echo Claude Code Portable - Mode: !PROXY_TEXT!
set "CLAUDE_CONFIG_DIR=%CONFIG_DIR%"
set "CLAUDE_HOME=%CONFIG_DIR%"
if "%~1"=="" ( "%BIN_DIR%\claude.exe"
) else ( "%BIN_DIR%\claude.exe" %* )

:: Save DB back to portable
if exist "%CCS_DB%" (
  copy /y "%CCS_DB%" "%PORTABLE_CCS%\cc-switch.db" >nul
)
taskkill /f /im cc-switch.exe >nul 2>&1
taskkill /f /im CC-Switch.exe >nul 2>&1
pause
exit /b 0