@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "CONFIG_DIR=%SCRIPT_DIR%data\.claude"
set "CONFIG_FILE=%SCRIPT_DIR%config\ccswitch\providers.json"
set "FIRST_RUN=%SCRIPT_DIR%data\.configured"

if not exist "%BIN_DIR%\claude.exe" ( echo [ERROR] Claude Code not found & pause & exit /b 1 )
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%SCRIPT_DIR%data" mkdir "%SCRIPT_DIR%data"

:: First-run setup
if not exist "%FIRST_RUN%" (
    echo.
    echo =====================================
    echo   1st Run - Configure API
    echo =====================================
    echo.
    echo   1. Open CC Switch GUI (recommended)
    echo   2. Manual API key entry
    echo.
    set /p CHOICE="  Choose [1/2]: "
    if "!CHOICE!"=="1" (
        echo Opening CC Switch...
        start "" "%BIN_DIR%\cc-switch.exe"
        echo Press any key after configuring...
        pause >nul
        set "HAS_CFG=0"
        if exist "%CONFIG_FILE%" (
            for /f "usebackq delims=" %%x in (`powershell -NoProfile -Command "try { $d = Get-Content '%CONFIG_FILE%' -Raw | ConvertFrom-Json; if ($d.providers.Count -gt 0) { exit 0 } else { exit 1 } } catch { exit 1 }"`) do ( set "dummy=%%x" )
            if !errorlevel! EQU 0 set "HAS_CFG=1"
        )
        if "!HAS_CFG!"=="1" ( type nul > "%FIRST_RUN%" & echo [ok] Provider detected
        ) else ( echo [!] No provider found. Run again after configuring. )
        pause & exit /b 0
    )
    set /p API_BASE="  API Base URL: "
    set /p AKEY=***  API Key: "
    if "%API_BASE%"=="" ( echo [ERROR] Base URL required & pause & exit /b 1 )
    if "%AKEY%"=="" ( echo [ERROR] API Key required & pause & exit /b 1 )
    powershell -NoProfile -Command "$c = @{ providers = @( @{ id='custom'; name='Custom API'; type='anthropic'; base_url='%API_BASE%'; api_key='%AKEY%'; enabled=$true } ); active_provider='custom'; proxy_port=18080; auto_start_proxy=$true }; $c | ConvertTo-Json -Depth 3 | Set-Content '%CONFIG_FILE%'" >nul 2>&1
    type nul > "%FIRST_RUN%"
    echo [ok] Config saved
)

:: Start CC Switch proxy (port 15721 is default for CC Switch 3.15+)
set "CC_SWITCH_PORT=15721"
set "HAS_CCSWITCH=0"

if exist "%BIN_DIR%\cc-switch.exe" (
    echo Starting CC Switch... (port !CC_SWITCH_PORT!)
    start "" "%BIN_DIR%\cc-switch.exe"
    set "TRIES=0"
    :wp_loop
    if !TRIES! GEQ 15 goto :wp_done
    timeout /t 1 >nul 2>&1
    set /a TRIES+=1
    powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient('127.0.0.1', !CC_SWITCH_PORT!); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
    if !errorlevel! EQU 0 ( set "HAS_CCSWITCH=1" & goto :wp_done )
    goto :wp_loop
    :wp_done
)

if "!HAS_CCSWITCH!"=="1" (
    set "ANTHROPIC_BASE_URL=http://127.0.0.1:!CC_SWITCH_PORT!"
    set "ANTHROPIC_API_KEY=***    echo   [ok] CC Switch proxy ready
) else (
    echo [!] Proxy not ready, trying direct mode
    if exist "%CONFIG_FILE%" (
        for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "try { $d = Get-Content '%CONFIG_FILE%' -Raw | ConvertFrom-Json; $p = $d.providers[0]; if ($p) { Write-Output $p.base_url; Write-Output $p.api_key } } catch {}"`) do (
            if not defined ANTHROPIC_BASE_URL ( set "ANTHROPIC_BASE_URL=%%A"
            ) else ( set "ANTHROPIC_API_KEY=
        )
    )
    if not defined ANTHROPIC_API_KEY ( echo [!] No API configured. & pause & exit /b 1 )
)

echo.
echo   Claude Code Portable
echo   Mode: !PROXY_MODE!
echo.
set "CLAUDE_CONFIG_DIR=%CONFIG_DIR%"
set "CLAUDE_HOME=%CONFIG_DIR%"

if "%~1"=="" ( "%BIN_DIR%\claude.exe" ) else ( "%BIN_DIR%\claude.exe" %* )

taskkill /f /im cc-switch.exe >nul 2>&1
taskkill /f /im CC-Switch.exe >nul 2>&1
pause
exit /b 0