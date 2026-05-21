@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

:: Claude Code Portable + CC Switch — Windows

set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "CC_SWITCH_PORT=18080"
set "CONFIG_DIR=%SCRIPT_DIR%data\.claude"
set "CONFIG_FILE=%SCRIPT_DIR%config\ccswitch\providers.json"

:: 检查 Claude Code
if not exist "%BIN_DIR%\claude.exe" (
    echo [ERROR] Claude Code not found: %BIN_DIR%\claude.exe
    pause
    exit /b 1
)

:: 创建数据目录
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%SCRIPT_DIR%data" mkdir "%SCRIPT_DIR%data"

:: 复制默认配置
if not exist "%CONFIG_DIR%\settings.json" (
    if exist "%SCRIPT_DIR%config\claude\settings.json" (
        copy "%SCRIPT_DIR%config\claude\settings.json" "%CONFIG_DIR%\settings.json" >nul
    )
)

echo.
echo   Claude Code Portable + CC Switch
echo   ==================================
echo.

:: 启动 CC Switch
set "HAS_CCSWITCH=0"
if exist "%BIN_DIR%\cc-switch.exe" (
    echo   Starting CC Switch...
    start "" "%BIN_DIR%\cc-switch.exe"
    call :wait_for_proxy
) else (
    echo   [!] CC Switch not found, direct mode
)

:: 设置环境变量
if "!HAS_CCSWITCH!"=="1" (
    set "ANTHROPIC_BASE_URL=http://127.0.0.1:%CC_SWITCH_PORT%"
    set "ANTHROPIC_API_KEY=portable-key"
    echo   [ok] CC Switch proxy ready
) else (
    echo   Direct mode - checking config...
    if not defined ANTHROPIC_API_KEY (
        if not defined ANTHROPIC_BASE_URL (
            echo.
            echo   [!] No API configured.
            echo   Please add CC Switch to bin\windows-x64\
            echo   or set ANTHROPIC_API_KEY environment variable.
            echo.
            pause
            exit /b 1
        )
    )
)

echo.
echo   Commands:
echo   claude              -- interactive
echo   claude -p "task"    -- one-shot
echo   claude -c           -- continue
echo   ==================================
echo.

:: 导出配置目录给 Claude Code
set "CLAUDE_CONFIG_DIR=%CONFIG_DIR%"

:: 启动 Claude Code
if "%~1"=="" (
    "%BIN_DIR%\claude.exe"
) else (
    "%BIN_DIR%\claude.exe" %*
)

:: 清理
echo.
echo   Stopping CC Switch...
taskkill /f /im cc-switch.exe >nul 2>&1
taskkill /f /im CC-Switch.exe >nul 2>&1
pause
exit /b 0

:: ─── 子程序：等待代理端口 ───
:wait_for_proxy
set "TRIES=0"
:wp_loop
if !TRIES! GEQ 10 goto :wp_done
timeout /t 1 >nul
set /a TRIES+=1
:: 用 PowerShell 检测端口（比 curl 更可靠）
powershell -Command "try { $c = New-Object Net.Sockets.TcpClient('127.0.0.1', %CC_SWITCH_PORT%); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if !errorlevel! EQU 0 (
    set "HAS_CCSWITCH=1"
    goto :wp_done
)
goto :wp_loop
:wp_done
exit /b 0
