#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch
# 一键启动脚本 — macOS
# ═══════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

# 检测架构
if [ "$ARCH" = "arm64" ]; then
    BIN_DIR="$SCRIPT_DIR/bin/macos-arm64"
elif [ "$ARCH" = "x86_64" ]; then
    BIN_DIR="$SCRIPT_DIR/bin/macos-x64"
else
    echo "❌ 不支持的架构: $ARCH"
    exit 1
fi

# 检查二进制
if [ ! -f "$BIN_DIR/claude" ]; then
    echo "❌ 未找到 Claude Code: $BIN_DIR/claude"
    echo "请确认 bin/ 目录完整"
    exit 1
fi

chmod +x "$BIN_DIR/claude" 2>/dev/null
chmod +x "$BIN_DIR/cc-switch" 2>/dev/null

# 配置目录
CLAUDE_CONFIG_DIR="$SCRIPT_DIR/data/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "$SCRIPT_DIR/data"

# ═══════════════════════════════════════════
# 首次运行引导
# ═══════════════════════════════════════════
CONFIG_FILE="$SCRIPT_DIR/config/ccswitch/providers.json"
FIRST_RUN_FLAG="$SCRIPT_DIR/data/.configured"

if [ ! -f "$FIRST_RUN_FLAG" ]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   首次运行 — 配置 API                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "  Claude Code 需要 API 才能运行。"
    echo ""
    echo "  支持的方式："
    echo "    1. CC Switch 图形界面配置（推荐）"
    echo "    2. 命令行快速配置"
    echo ""
    read -p "  选择方式 [1/2]: " choice

    if [ "$choice" = "1" ]; then
        echo ""
        echo "  正在打开 CC Switch..."
        echo "  请在 CC Switch 中添加 Provider，然后重新运行此脚本。"
        echo ""
        open "$BIN_DIR/cc-switch" 2>/dev/null || "$BIN_DIR/cc-switch" &
        exit 0
    fi

    echo ""
    echo "  命令行配置："
    echo ""
    read -p "  API 地址 (Base URL): " api_base
    read -p "  API Key: " api_key

    if [ -z "$api_base" ] || [ -z "$api_key" ]; then
        echo "❌ API 地址和 Key 不能为空"
        exit 1
    fi

    # 保存配置
    python3 -c "
import json
config = {
    'providers': [{
        'id': 'custom',
        'name': '自定义 API',
        'type': 'anthropic',
        'base_url': '$api_base',
        'api_key': '$api_key',
        'enabled': True
    }],
    'active_provider': 'custom',
    'proxy_port': 18080,
    'auto_start_proxy': True
}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
" 2>/dev/null

    touch "$FIRST_RUN_FLAG"
    echo ""
    echo "  ✓ 配置已保存"
    echo ""
fi

# ═══════════════════════════════════════════
# 加载配置
# ═══════════════════════════════════════════
CC_SWITCH_PORT="${CC_SWITCH_PORT:-18080}"

# 尝试启动 CC Switch 代理
if [ -f "$BIN_DIR/cc-switch" ]; then
    "$BIN_DIR/cc-switch" --proxy-only --port "$CC_SWITCH_PORT" &>/dev/null &
    CC_SWITCH_PID=$!
    sleep 3

    if kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
        export ANTHROPIC_BASE_URL="http://127.0.0.1:$CC_SWITCH_PORT"
        export ANTHROPIC_API_KEY="portable-key"
        PROXY_MODE="CC Switch 代理 (端口 $CC_SWITCH_PORT)"
    else
        PROXY_MODE="直连"
    fi
else
    PROXY_MODE="直连（无 CC Switch）"
fi

# 直连模式：从配置文件读取
if [ -z "$ANTHROPIC_BASE_URL" ] && [ -f "$CONFIG_FILE" ]; then
    eval "$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    d = json.load(f)
providers = d.get('providers', [])
if providers:
    p = providers[0]
    print(f'export ANTHROPIC_BASE_URL=\"{p[\"base_url\"]}\"')
    print(f'export ANTHROPIC_API_KEY=\"{p[\"api_key\"]}\"')
" 2>/dev/null)"
fi

# 检查是否有配置
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo ""
    echo "❌ 未配置 API，请先运行配置："
    echo "   $0 --setup"
    echo ""
    echo "或打开 CC Switch 手动配置："
    echo "   open $BIN_DIR/cc-switch"
    exit 1
fi

# ═══════════════════════════════════════════
# 启动 Claude Code
# ═══════════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Claude Code Portable                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  架构: $ARCH"
echo "  模式: $PROXY_MODE"
echo ""

"$BIN_DIR/claude" "$@"

# 清理
if [ -n "$CC_SWITCH_PID" ]; then
    kill "$CC_SWITCH_PID" 2>/dev/null
fi
