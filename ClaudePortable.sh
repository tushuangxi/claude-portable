#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch
# 一键启动脚本 — Linux
# ═══════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

if [ "$ARCH" = "x86_64" ]; then
    BIN_DIR="$SCRIPT_DIR/bin/linux-x64"
elif [ "$ARCH" = "aarch64" ]; then
    BIN_DIR="$SCRIPT_DIR/bin/linux-arm64"
else
    echo "[ERROR] 不支持的架构: $ARCH"
    exit 1
fi

if [ ! -f "$BIN_DIR/claude" ]; then
    echo "[ERROR] 未找到 Claude Code: $BIN_DIR/claude"
    exit 1
fi

chmod +x "$BIN_DIR/claude" "$BIN_DIR/cc-switch" 2>/dev/null

CLAUDE_CONFIG_DIR="$SCRIPT_DIR/data/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "$SCRIPT_DIR/data"

CONFIG_FILE="$SCRIPT_DIR/config/ccswitch/providers.json"
FIRST_RUN_FLAG="$SCRIPT_DIR/data/.configured"

if [ ! -f "$FIRST_RUN_FLAG" ]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   首次运行 — 配置 API                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    read -p "  API 地址 (Base URL): " api_base
    read -p "  API Key: " api_key

    if [ -z "$api_base" ] || [ -z "$api_key" ]; then
        echo "[ERROR] 不能为空"
        exit 1
    fi

    API_BASE="$api_base" API_KEY="$api_key" CONFIG_FILE="$CONFIG_FILE" python3 -c "
import json, os
config = {'providers': [{'id': 'custom', 'name': 'Custom API', 'type': 'anthropic', 'base_url': os.environ['API_BASE'], 'api_key': os.environ['API_KEY'], 'enabled': True}], 'active_provider': 'custom', 'proxy_port': 18080}
with open(os.environ['CONFIG_FILE'], 'w') as f: json.dump(config, f, indent=2, ensure_ascii=False)
" 2>/dev/null

    touch "$FIRST_RUN_FLAG"
    echo "  [ok] 配置已保存"
fi

CC_SWITCH_PORT="${CC_SWITCH_PORT:-18080}"
CC_SWITCH_RUNNING=0

if [ -f "$BIN_DIR/cc-switch" ]; then
    echo "  启动 CC Switch..."
    "$BIN_DIR/cc-switch" &>/dev/null &
    CC_SWITCH_PID=$!
    for i in $(seq 1 20); do
        if nc -z 127.0.0.1 "$CC_SWITCH_PORT" 2>/dev/null || curl -s --connect-timeout 1 "http://127.0.0.1:$CC_SWITCH_PORT" >/dev/null 2>&1; then
            CC_SWITCH_RUNNING=1; break
        fi
        sleep 0.5
    done
    if [ "$CC_SWITCH_RUNNING" -eq 1 ]; then
        export ANTHROPIC_BASE_URL="http://127.0.0.1:$CC_SWITCH_PORT"
        export ANTHROPIC_API_KEY="portable-key"
    else
        echo "  [!] CC Switch 代理未就绪，使用直连"
    fi
fi

if [ "$CC_SWITCH_RUNNING" -eq 0 ] && [ -f "$CONFIG_FILE" ]; then
    eval "$(API_BASE="" API_KEY="" CONFIG_FILE="$CONFIG_FILE" python3 -c "
import json, os
try:
    with open(os.environ['CONFIG_FILE']) as f:
        d = json.load(f)
    p = d.get('providers', [None])[0]
    if p:
        print(f'export ANTHROPIC_BASE_URL=\"{p[\"base_url\"]}\"')
        print(f'export ANTHROPIC_API_KEY=\"{p[\"api_key\"]}\"')
except: pass
" 2>/dev/null)" || true
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "[ERROR] 未配置 API"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Claude Code Portable                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""

"$BIN_DIR/claude" "$@"

if [ -n "$CC_SWITCH_PID" ]; then kill "$CC_SWITCH_PID" 2>/dev/null; fi
