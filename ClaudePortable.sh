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
    echo "[ERROR] 暂不支持 Linux ARM64（项目中无对应二进制）"
    exit 1
else
    echo "[ERROR] 不支持的架构: $ARCH"
    exit 1
fi

if [ ! -f "$BIN_DIR/claude" ]; then
    echo "[ERROR] 未找到 Claude Code: $BIN_DIR/claude"
    exit 1
fi

chmod +x "$BIN_DIR/claude" "$BIN_DIR/cc-switch" 2>/dev/null

export CLAUDE_CONFIG_DIR="$SCRIPT_DIR/data/.claude"
export CLAUDE_HOME="$SCRIPT_DIR/data/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "$SCRIPT_DIR/data"

# 便携式 CC Switch 数据目录（随项目移动）
PORTABLE_CCS_DIR="$SCRIPT_DIR/data/cc-switch"
mkdir -p "$PORTABLE_CCS_DIR"

sync_db_to_home() {
    if [ -f "$PORTABLE_CCS_DIR/cc-switch.db" ]; then
        mkdir -p "$HOME/.cc-switch"
        cp "$PORTABLE_CCS_DIR/cc-switch.db" "$HOME/.cc-switch/cc-switch.db" 2>/dev/null
    fi
}

sync_db_to_portable() {
    if [ -f "$HOME/.cc-switch/cc-switch.db" ]; then
        mkdir -p "$PORTABLE_CCS_DIR"
        cp "$HOME/.cc-switch/cc-switch.db" "$PORTABLE_CCS_DIR/cc-switch.db" 2>/dev/null
    fi
}

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
    read -p "  API 地址 (Base URL): " api_base
    read -p "  API Key: " api_key

    if [ -z "$api_base" ] || [ -z "$api_key" ]; then
        echo "[ERROR] 不能为空"
        exit 1
    fi

    python3 <<-PYEOF 2>/dev/null
import json, os
config = {
    'providers': [{
        'id': 'custom', 'name': 'Custom API', 'type': 'anthropic',
        'base_url': os.environ.get('API_BASE', ''),
        'api_key': os.environ.get('API_KEY', ''),
        'enabled': True
    }],
    'active_provider': 'custom',
    'proxy_port': 18080,
    'auto_start_proxy': True
}
with open(os.environ['CONFIG_FILE'], 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF

    touch "$FIRST_RUN_FLAG"
    echo "  [ok] 配置已保存"
fi

# ═══════════════════════════════════════════
# 启动 CC Switch 代理
# ═══════════════════════════════════════════
CCS_DB="$HOME/.cc-switch/cc-switch.db"
CC_SWITCH_PORT=$(python3 <<-PYEOF 2>/dev/null
import sqlite3, sys
try:
    db = sqlite3.connect('$CCS_DB')
    row = db.execute("SELECT listen_port FROM proxy_config WHERE app_type='claude' LIMIT 1").fetchone()
    db.close()
    print(row[0] if row else 18080)
except:
    print(18080)
PYEOF
)
[ -z "$CC_SWITCH_PORT" ] && CC_SWITCH_PORT=18080
CC_SWITCH_RUNNING=0
CC_SWITCH_PID=""

# 清理后台进程 + 保存数据
cleanup() {
    [ -n "$CC_SWITCH_PID" ] && kill "$CC_SWITCH_PID" 2>/dev/null
    sync_db_to_portable
}
trap cleanup EXIT INT TERM

if [ -f "$BIN_DIR/cc-switch" ]; then
    sync_db_to_home
    echo "  启动 CC Switch...（代理端口 $CC_SWITCH_PORT）"
    "$BIN_DIR/cc-switch" &>/dev/null &
    CC_SWITCH_PID=$!

    for i in $(seq 1 20); do
        if (echo >/dev/tcp/127.0.0.1/$CC_SWITCH_PORT) 2>/dev/null || \
           curl -s --connect-timeout 1 "http://127.0.0.1:$CC_SWITCH_PORT" >/dev/null 2>&1; then
            CC_SWITCH_RUNNING=1
            break
        fi
        sleep 0.5
    done

    if [ "$CC_SWITCH_RUNNING" -eq 1 ]; then
        export ANTHROPIC_BASE_URL="http://127.0.0.1:$CC_SWITCH_PORT"
        export ANTHROPIC_API_KEY="portable-key"
        PROXY_MODE="CC Switch 代理 (端口 $CC_SWITCH_PORT)"
    else
        echo "  [!] CC Switch 代理未就绪，尝试直连模式"
        PROXY_MODE="直连"
    fi
else
    PROXY_MODE="直连（未找到 CC Switch）"
fi

# 直连模式：从 SQLite 读取活跃 Provider
if [ "$CC_SWITCH_RUNNING" -eq 0 ] && [ -f "$CCS_DB" ]; then
    eval "$(python3 <<-PYEOF 2>/dev/null
import sqlite3, json
try:
    db = sqlite3.connect('$CCS_DB')
    row = db.execute("SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1").fetchone()
    db.close()
    if row:
        cfg = json.loads(row[0])
        env = cfg.get('env', {})
        base_url = env.get('ANTHROPIC_BASE_URL', '')
        api_key = env.get('ANTHROPIC_AUTH_TOKEN', '')
        if base_url and api_key:
            print('export ANTHROPIC_BASE_URL=\"' + base_url + '\"')
            print('export ANTHROPIC_AUTH_TOKEN=\"' + api_key + '\"')
            print('export ANTHROPIC_API_KEY=\"' + api_key + '\"')
except:
    pass
PYEOF
)" || true
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "[ERROR] 未配置 API，请先运行配置："
    echo "   $0"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Claude Code Portable                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  架构: $ARCH"
echo "  模式: $PROXY_MODE"
echo ""

"$BIN_DIR/claude" "$@"
sync_db_to_portable