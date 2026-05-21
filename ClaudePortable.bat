@echo off
chcp 65001 >nul 2>&1
title Claude Code Portable + CC Switch

:: ═══════════════════════════════════════════
:: Claude Code Portable + CC Switch — Windows 启动脚本
:: ═══════════════════════════════════════════

set "SCRIPT_DIR=%~dp0"
set "BIN_DIR=%SCRIPT_DIR%bin\windows-x64"
set "CC_SWITCH_PORT=18080"

:: 检查二进制文件
if not exist "%BIN_DIR%\claude.exe" (
    echo [ERROR] 未找到 Claude Code: %BIN_DIR%\claude.exe
    pause
    exit /b 1
)

:: 配置目录
set "CLAUDE_CONFIG_DIR=%SCRIPT_DIR%data\.claude"
set "HOME_CLAUDE=%SCRIPT_DIR%.claude"

if not exist "%CLAUDE_CONFIG_DIR%" mkdir "%CLAUDE_CONFIG_DIR%"
if not exist "%HOME_CLAUDE%" mkdir "%HOME_CLAUDE%"
if not exist "%SCRIPT_DIR%data" mkdir "%SCRIPT_DIR%data"

:: 复制配置
if not exist "%CLAUDE_CONFIG_DIR%\settings.json" (
    if exist "%SCRIPT_DIR%config\claude\settings.json" (
        copy "%SCRIPT_DIR%config\claude\settings.json" "%CLAUDE_CONFIG_DIR%\settings.json" >nul
    )
)

echo.
echo ╔══════════════════════════════════════════╗
echo ║   Claude Code Portable + CC Switch       ║
echo ╚══════════════════════════════════════════╝
echo.
echo   架构: Windows x64
echo   路径: %BIN_DIR%
echo.

:: 启动 CC Switch（GUI 应用，自动开启代理）
set "HAS_CCSWITCH=0"
if exist "%BIN_DIR%\cc-switch.exe" (
    echo   启动 CC Switch...
    start "" "%BIN_DIR%\cc-switch.exe"
    :: 等待代理端口就绪（最多 10 秒）
    set "WAIT=0"
    :waitloop
    if %WAIT% GEQ 20 goto :nowait
    timeout /t 1 >nul
    set /a WAIT+=2
    curl -s "http://127.0.0.1:%CC_SWITCH_PORT%" >nul 2>&1 && goto :proxyon
    goto :waitloop
    :proxyon
    set "HAS_CCSWITCH=1"
    echo   [ok] CC Switch 代理已就绪
    :nowait
) else (
    echo   [!] CC Switch 未找到，使用直连模式
)

:: 设置环境变量
if "%HAS_CCSWITCH%"=="1" (
    set "ANTHROPIC_BASE_URL=http://127.0.0.1:%CC_SWITCH_PORT%"
    set "ANTHROPIC_API_KEY=portable-key"
)

echo.
echo   可用命令:
echo   claude              -- 交互模式
echo   claude -p "任务"     -- 一次性任务
echo   claude -c           -- 继续上次对话
echo.
echo ═══════════════════════════════════════════
echo.

:: 启动 Claude Code
if "%~1"=="" (
    "%BIN_DIR%\claude.exe"
) else (
    "%BIN_DIR%\claude.exe" %*
)

:: 清理
echo.
echo   正在停止 CC Switch...
taskkill /f /im cc-switch.exe >nul 2>&1
echo   已退出
pause
