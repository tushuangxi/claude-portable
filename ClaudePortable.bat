@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

REM Enable ANSI escape codes (Windows 10+)
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
set "CONFIG_DIR=%SCRIPT_DIR%data\.claude"
set "CONFIG_FILE=%SCRIPT_DIR%config\ccswitch\providers.json"
set "PORTABLE_CCS=%SCRIPT_DIR%data\cc-switch"
set "CCS_DB=%USERPROFILE%\.cc-switch\cc-switch.db"
set "LIB_DIR=%SCRIPT_DIR%lib"

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
  )
)

:: =============================================
:: Check if valid config exists
:: =============================================
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 1024 set "HAS_CONFIG=1"
)
if "!HAS_CONFIG!"=="0" (
  if exist "%CONFIG_FILE%" (
    for %%F in ("%CONFIG_FILE%") do if %%~zF GTR 10 set "HAS_CONFIG=1"
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
timeout /t 2 >nul 2>&1
:: Re-check
set "HAS_CONFIG=0"
if exist "%CCS_DB%" (
  for %%F in ("%CCS_DB%") do if %%~zF GTR 1024 set "HAS_CONFIG=1"
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
set "CP_API_BASE=!API_BASE!"
set "CP_API_KEY=!AKEY!"
set "CP_CONFIG_FILE=%CONFIG_FILE%"
powershell -NoProfile -Command "$base = $env:CP_API_BASE; $key = $env:CP_API_KEY; $out = $env:CP_CONFIG_FILE; $c = @{ providers = @( @{ id='custom'; name='Custom API'; type='anthropic'; base_url=$base; api_key=$key; enabled=$true } ); active_provider='custom'; proxy_port=15721; auto_start_proxy=$true }; $c | ConvertTo-Json -Depth 3 | Set-Content -Path $out -Encoding UTF8" >nul 2>&1
if !errorlevel! NEQ 0 (
  echo [ERROR] Failed to save config
  pause & exit /b 1
)
echo [ok] Config saved
:: Use the values directly
set "ANTHROPIC_BASE_URL=!API_BASE!"
set "ANTHROPIC_API_KEY=!AKEY!"
set "ANTHROPIC_AUTH_TOKEN=!AKEY!"
goto :run_claude

:skip_first_run
:: =============================================
:: Read API config from DB using lib\extract-config.ps1
:: =============================================
set "TMP_URL=%TEMP%\ccs_url_%RANDOM%.txt"
set "TMP_KEY=%TEMP%\ccs_key_%RANDOM%.txt"

:: Method 1: Use bundled PowerShell helper script
if exist "%LIB_DIR%\extract-config.ps1" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%LIB_DIR%\extract-config.ps1" "%CCS_DB%" "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
  if exist "!TMP_URL!" (
    set /p ANTHROPIC_BASE_URL=<"!TMP_URL!"
    set /p ANTHROPIC_API_KEY=<"!TMP_KEY!"
    set "ANTHROPIC_AUTH_TOKEN=!ANTHROPIC_API_KEY!"
    del "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
    echo   [ok] Config loaded from CC Switch DB
    goto :run_claude
  )
)

:: Method 2: sqlite3.exe (bundled by CI)
if exist "%CCS_DB%" (
  if exist "%BIN_DIR%\sqlite3.exe" (
    set "TMP_RAW=%TEMP%\ccs_raw_%RANDOM%.txt"
    "%BIN_DIR%\sqlite3.exe" "%CCS_DB%" "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1" > "!TMP_RAW!" 2>nul
    if exist "!TMP_RAW!" (
      set "CCS_TMP_URL=!TMP_URL!"
      set "CCS_TMP_KEY=!TMP_KEY!"
      set "CCS_TMP_RAW=!TMP_RAW!"
      powershell -NoProfile -Command "try { $raw = Get-Content $env:CCS_TMP_RAW -Raw -ErrorAction Stop; $cfg = $raw | ConvertFrom-Json; $e = $cfg.env; $k = $e.ANTHROPIC_AUTH_TOKEN; if (-not $k) { $k = $e.ANTHROPIC_API_KEY }; if ($e.ANTHROPIC_BASE_URL -and $k) { [IO.File]::WriteAllText($env:CCS_TMP_URL, $e.ANTHROPIC_BASE_URL); [IO.File]::WriteAllText($env:CCS_TMP_KEY, $k) } } catch {}" >nul 2>&1
      if exist "!TMP_URL!" (
        set /p ANTHROPIC_BASE_URL=<"!TMP_URL!"
        set /p ANTHROPIC_API_KEY=<"!TMP_KEY!"
        set "ANTHROPIC_AUTH_TOKEN=!ANTHROPIC_API_KEY!"
        del "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
        echo   [ok] Config loaded from CC Switch DB
      )
      del "!TMP_RAW!" >nul 2>&1
    )
  )
)

:: Method 3: providers.json fallback
if "!ANTHROPIC_API_KEY!"=="" (
  if exist "%CONFIG_FILE%" (
    set "CP_CONFIG_FILE=%CONFIG_FILE%"
    set "CCS_TMP2_URL=!TMP_URL!"
    set "CCS_TMP2_KEY=!TMP_KEY!"
    powershell -NoProfile -Command "$f = $env:CP_CONFIG_FILE; try { $d = Get-Content $f -Raw | ConvertFrom-Json; foreach ($p in $d.providers) { if ($p.enabled -and $p.base_url -and $p.api_key) { [IO.File]::WriteAllText($env:CCS_TMP2_URL, $p.base_url); [IO.File]::WriteAllText($env:CCS_TMP2_KEY, $p.api_key); break } } } catch {}" >nul 2>&1
    if exist "!TMP_URL!" (
      set /p ANTHROPIC_BASE_URL=<"!TMP_URL!"
      set /p ANTHROPIC_API_KEY=<"!TMP_KEY!"
      set "ANTHROPIC_AUTH_TOKEN=!ANTHROPIC_API_KEY!"
      del "!TMP_URL!" "!TMP_KEY!" >nul 2>&1
      echo   [ok] Config loaded from providers.json
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
echo   Mode: Direct (API configured)
echo.
set "CLAUDE_CONFIG_DIR=%CONFIG_DIR%"
set "CLAUDE_HOME=%CONFIG_DIR%"
"%BIN_DIR%\claude.exe" %*

:: Save DB back to portable on exit
if exist "%CCS_DB%" (
  copy /y "%CCS_DB%" "%PORTABLE_CCS%\cc-switch.db" >nul 2>&1
)
pause
exit /b 0
