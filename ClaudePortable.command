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
    echo "[ERROR] 不支持的架构: $ARCH"
    exit 1
fi

# 检查二进制
if [ ! -f "$BIN_DIR/claude" ]; then
    echo "[ERROR] 未找到 Claude Code: $BIN_DIR/claude"
    echo "请确认 bin/ 目录完整"
    exit 1
fi

chmod +x "$BIN_DIR/claude" 2>/dev/null
chmod +x "$BIN_DIR/cc-switch" 2>/dev/null

# 配置目录 — 导出给 Claude Code 使用便携路径
export CLAUDE_CONFIG_DIR="$SCRIPT_DIR/data/.claude"
export CLAUDE_HOME="$SCRIPT_DIR/data/.claude"
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
        echo "  请在 CC Switch 中添加 Provider，保存后关闭 CC Switch。"
        echo "  然后重新运行此脚本。"
        echo ""
        "$BIN_DIR/cc-switch" 2>/dev/null || true
# 检查 CC Switch 数据库是否有 provider（不用 providers.json，CC Switch 存 SQLite）
        CCS_DB="$HOME/.cc-switch/cc-switch.db"
        if [ -f "$CCS_DB" ]; then
            CCS_COUNT=$(python3 <<-PYEOF 2>/dev/null
import sqlite3, sys
try:
    db = sqlite3.connect('$CCS_DB')
    count = db.execute("SELECT COUNT(*) FROM providers").fetchone()[0]
    db.close()
    print(count)
    sys.exit(0 if count > 0 else 1)
except Exception:
    sys.exit(1)
PYEOF
) && touch "$FIRST_RUN_FLAG" && echo "  [ok] 检测到 $CCS_COUNT 个已启用的 Provider"
        fi
        exit 0
    fi

    echo ""
    echo "  命令行配置："
    echo ""
    read -p "  API 地址 (Base URL): " api_base
    read -p "  API Key: " api_key

    if [ -z "$api_base" ] || [ -z "$api_key" ]; then
        echo "[ERROR] API 地址和 Key 不能为空"
        exit 1
    fi

    # 保存配置
    API_BASE="$api_base" API_KEY="$api_key" CONFIG_FILE="$CONFIG_FILE" python3 -c "
import json, os
config = {
    'providers': [{
        'id': 'custom',
        'name': 'Custom API',
        'type': 'anthropic',
        'base_url': os.environ['API_BASE'],
        'api_key': os.environ['API_KEY'],
        'enabled': True
    }],
    'active_provider': 'custom',
    'proxy_port': 18080,
    'auto_start_proxy': True
}
with open(os.environ['CONFIG_FILE'], 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
" 2>/dev/null

    touch "$FIRST_RUN_FLAG"
    echo ""
    echo "  [ok] 配置已保存"
    echo ""
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
    if row:
        print(row[0])
    else:
        print(18080)
except:
    print(18080)
PYEOF
)
[ -z "$CC_SWITCH_PORT" ] && CC_SWITCH_PORT=18080
CC_SWITCH_RUNNING=0
CC_SWITCH_PID=""

# 清理后台进程（防止 Ctrl+C 残留）
cleanup() {
    if [ -n "$CC_SWITCH_PID" ]; then
        kill "$CC_SWITCH_PID" 2>/dev/null
    fi
}
trap cleanup EXIT INT TERM

if [ -f "$BIN_DIR/cc-switch" ]; then
    echo "  启动 CC Switch...（代理端口 $CC_SWITCH_PORT）"
    # 直接后台执行（不用 open，cc-switch 不是 .app bundle）
    "$BIN_DIR/cc-switch" &>/dev/null &
    CC_SWITCH_PID=$!

    # 等待代理端口就绪（最多 10 秒）
    for i in $(seq 1 20); do
        if nc -z -w1 127.0.0.1 "$CC_SWITCH_PORT" 2>/dev/null; then
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

# 直连模式：从 CC Switch SQLite 读取活跃 Provider
if [ "$CC_SWITCH_RUNNING" -eq 0 ] && [ -f "$CCS_DB" ]; then
    eval "$(python3 <<-PYEOF 2>/dev/null
import sqlite3, json
try:
    db = sqlite3.connect('$CCS_DB')
    # 取当前激活的 claude provider
    row = db.execute("SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1").fetchone()
    db.close()
    if row:
        cfg = json.loads(row[0])
        env = cfg.get('env', {})
        base_url = env.get('ANTHROPIC_BASE_URL', '')
        api_key = env.get('ANTHROPIC_AUTH_TOKEN', '')
        if base_url and api_key:
            print(f'export ANTHROPIC_BASE_URL=\"{base_url}\"')
            print(f'export ANTHROPIC_AUTH_TOKEN=\"{api_key}\"')
            print(f'export ANTHROPIC_API_KEY=\"{api_key}\"')
except:
    pass
PYEOF
)" || true
fi

# 检查是否有配置
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo ""
    echo "[ERROR] 未配置 API，请先运行配置："
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
