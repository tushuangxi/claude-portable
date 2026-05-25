#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch
# 一键启动脚本 - macOS
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

# 检查 python3
HAS_PYTHON3=0
if command -v python3 &>/dev/null; then
    HAS_PYTHON3=1
else
    echo "[WARN] python3 未找到，部分功能（端口检测、DB读取）可能受限"
fi

# macOS: 移除 quarantine 属性（Gatekeeper 拦截）
xattr -dr com.apple.quarantine "$BIN_DIR/claude" 2>/dev/null
xattr -dr com.apple.quarantine "$BIN_DIR/cc-switch" 2>/dev/null

# 配置目录
export CLAUDE_CONFIG_DIR="$SCRIPT_DIR/data/.claude"
export CLAUDE_HOME="$SCRIPT_DIR/data/.claude"
mkdir -p "$CLAUDE_CONFIG_DIR" "$SCRIPT_DIR/data"

# 便携式 CC Switch 数据目录
PORTABLE_CCS_DIR="$SCRIPT_DIR/data/cc-switch"
mkdir -p "$PORTABLE_CCS_DIR"
CCS_DB="$HOME/.cc-switch/cc-switch.db"
CONFIG_FILE="$SCRIPT_DIR/config/ccswitch/providers.json"

# 从便携包同步 DB 到 HOME
sync_db_to_home() {
    if [ -f "$PORTABLE_CCS_DIR/cc-switch.db" ]; then
        mkdir -p "$HOME/.cc-switch"
        cp "$PORTABLE_CCS_DIR/cc-switch.db" "$CCS_DB" 2>/dev/null
        echo "  [sync] 已恢复 CC Switch 数据"
    fi
}

# 从 HOME 同步 DB 回便携包
sync_db_to_portable() {
    if [ -f "$CCS_DB" ]; then
        mkdir -p "$PORTABLE_CCS_DIR"
        cp "$CCS_DB" "$PORTABLE_CCS_DIR/cc-switch.db" 2>/dev/null
    fi
}

# 启动时同步 DB（比较修改时间，避免覆盖更新的 home DB）
sync_db_to_home_safe() {
    if [ -f "$PORTABLE_CCS_DIR/cc-switch.db" ]; then
        mkdir -p "$HOME/.cc-switch"
        if [ ! -f "$CCS_DB" ]; then
            # home 没有 DB，直接复制
            cp "$PORTABLE_CCS_DIR/cc-switch.db" "$CCS_DB" 2>/dev/null
            echo "  [sync] 已恢复 CC Switch 数据"
        elif [ "$PORTABLE_CCS_DIR/cc-switch.db" -nt "$CCS_DB" ]; then
            # 便携包 DB 更新，覆盖 home
            cp "$PORTABLE_CCS_DIR/cc-switch.db" "$CCS_DB" 2>/dev/null
            echo "  [sync] 已恢复 CC Switch 数据"
        fi
    fi
}

sync_db_to_home_safe

# 检测 provider 配置是否存在（DB 或 providers.json 任一即可）
has_valid_config() {
    # 无 python3 时：只检查文件是否存在且非空
    if [ "$HAS_PYTHON3" != "1" ]; then
        [ -f "$CCS_DB" ] && [ -s "$CCS_DB" ] && return 0
        [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ] && return 0
        return 1
    fi
    # 检查 DB 中是否有 claude provider
    if [ -f "$CCS_DB" ]; then
        if python3 - "$CCS_DB" <<'PYEOF' 2>/dev/null
import sqlite3, sys
db_path = sys.argv[1]
try:
    db = sqlite3.connect(db_path)
    n = db.execute("SELECT COUNT(*) FROM providers WHERE app_type='claude'").fetchone()[0]
    db.close()
    sys.exit(0 if n > 0 else 1)
except Exception:
    sys.exit(1)
PYEOF
        then
            return 0
        fi
    fi
    # 检查 providers.json
    if [ -f "$CONFIG_FILE" ]; then
        if python3 - "$CONFIG_FILE" <<'PYEOF' 2>/dev/null
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    ok = any(p.get('enabled') and p.get('base_url') and p.get('api_key') for p in d.get('providers', []))
    sys.exit(0 if ok else 1)
except Exception:
    sys.exit(1)
PYEOF
        then
            return 0
        fi
    fi
    return 1
}

# ═══════════════════════════════════════════
# 首次运行引导（基于配置存在性，跨机器跨目录都能正确判断）
# ═══════════════════════════════════════════
if ! has_valid_config; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   首次运行 - 配置 API                    ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    echo "  Claude Code 需要 API 才能运行。"
    echo ""
    echo "  支持的方式："
    echo "    1. CC Switch 图形界面配置（推荐）"
    echo "    2. 命令行快速配置"
    echo ""
    read -p "  选择方式 [1/2]: " choice
    if [ -z "$choice" ]; then
        exit 0
    fi

    if [ "$choice" = "1" ]; then
        echo ""
        echo "  正在打开 CC Switch（窗口关闭后将自动检测配置）..."
        echo ""
        "$BIN_DIR/cc-switch" 2>/dev/null || true
        # cc-switch 退出后检测
        if has_valid_config; then
            echo "  [ok] 检测到已配置的 Provider"
            sync_db_to_portable
        else
            echo "  [!] 未检测到 Provider，请重新运行并完成配置"
            exit 1
        fi
    else
        echo ""
        echo "  命令行配置："
        echo ""
        read -rp "  API 地址 (Base URL): " api_base
        read -rsp "  API Key: " api_key
        echo ""
        if [ -z "$api_base" ] || [ -z "$api_key" ]; then
            echo "[ERROR] API 地址和 Key 不能为空"
            exit 1
        fi

        # 保存到 providers.json — 通过环境变量传值，避免命令注入
        API_BASE="$api_base" API_KEY="$api_key" CONFIG_OUT="$CONFIG_FILE" \
        python3 - <<'PYEOF' 2>/dev/null
import json, os
config = {
    'providers': [{
        'id': 'custom', 'name': 'Custom API', 'type': 'anthropic',
        'base_url': os.environ['API_BASE'],
        'api_key': os.environ['API_KEY'],
        'enabled': True
    }],
    'active_provider': 'custom',
    'proxy_port': 15721,
    'auto_start_proxy': True
}
with open(os.environ['CONFIG_OUT'], 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        echo "  [ok] 配置已保存"
        echo ""
        # 命令行配置只写了 JSON，cc-switch 不知道这个 provider
        # 直接设置环境变量，跳过代理模式
        export ANTHROPIC_BASE_URL="$api_base"
        export ANTHROPIC_API_KEY="$api_key"
        export ANTHROPIC_AUTH_TOKEN="$api_key"
        SKIP_PROXY=1
    fi
fi

# ═══════════════════════════════════════════
# 读取 CC Switch 监听端口
# ═══════════════════════════════════════════
SKIP_PROXY=${SKIP_PROXY:-0}

if [ "$SKIP_PROXY" = "1" ]; then
    PROXY_MODE="直连（命令行配置）"
    CC_SWITCH_RUNNING=0
else
CC_SWITCH_PORT=$(CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import sqlite3, os
try:
    db = sqlite3.connect(os.environ['CCS_DB'])
    row = db.execute("SELECT listen_port FROM proxy_config WHERE app_type='claude' LIMIT 1").fetchone()
    db.close()
    print(row[0] if row else 15721)
except Exception:
    print(15721)
PYEOF
)
[ -z "$CC_SWITCH_PORT" ] && CC_SWITCH_PORT=15721
CC_SWITCH_RUNNING=0
CC_SWITCH_PID=""
WE_STARTED_CCS=0

# 端口检测：多重回退
check_port() {
    local p="$1"
    if command -v nc &>/dev/null; then
        nc -z -w1 127.0.0.1 "$p" 2>/dev/null && return 0
    fi
    # /dev/tcp 回退
    (echo >/dev/tcp/127.0.0.1/"$p") 2>/dev/null && return 0
    # curl 回退
    if command -v curl &>/dev/null; then
        curl -s --connect-timeout 1 "http://127.0.0.1:$p" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# 进程检测：宽松匹配，排除自身
ccs_running() {
    pgrep -f "[Cc][Cc].?[Ss]witch" 2>/dev/null | grep -v "^$$\$" | grep -q .
}

cleanup() {
    # 仅杀掉本脚本启动的 cc-switch
    if [ "$WE_STARTED_CCS" = "1" ] && [ -n "$CC_SWITCH_PID" ]; then
        kill "$CC_SWITCH_PID" 2>/dev/null
        # 等待进程退出，确保 DB 写入完成
        wait "$CC_SWITCH_PID" 2>/dev/null
    fi
    sync_db_to_portable
}
trap cleanup EXIT INT TERM

if [ -f "$BIN_DIR/cc-switch" ]; then
    if ccs_running; then
        echo "  CC Switch 已在运行"
    else
        echo "  启动 CC Switch...（代理端口 $CC_SWITCH_PORT）"
        "$BIN_DIR/cc-switch" &>/dev/null &
        CC_SWITCH_PID=$!
        WE_STARTED_CCS=1
        sleep 1
    fi

    for i in $(seq 1 20); do
        # 检查进程是否还活着（仅对我们启动的进程）
        if [ "$WE_STARTED_CCS" = "1" ] && ! kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
            echo "  [!] CC Switch 进程已退出"
            WE_STARTED_CCS=0
            break
        fi
        if check_port "$CC_SWITCH_PORT"; then
            CC_SWITCH_RUNNING=1
            break
        fi
        sleep 0.5
    done

    if [ "$CC_SWITCH_RUNNING" -eq 1 ]; then
        export ANTHROPIC_BASE_URL="http://127.0.0.1:$CC_SWITCH_PORT"
        export ANTHROPIC_API_KEY="portable-key"
        export ANTHROPIC_AUTH_TOKEN="portable-key"
        PROXY_MODE="CC Switch 代理 (端口 $CC_SWITCH_PORT)"
    else
        echo "  [!] CC Switch 代理未就绪，尝试直连模式"
        PROXY_MODE="直连"
    fi
else
    PROXY_MODE="直连（未找到 CC Switch）"
fi

fi  # end SKIP_PROXY else

# ═══════════════════════════════════════════
# 直连模式：读取配置（用换行分隔，避免 eval 注入）
# ═══════════════════════════════════════════
read_config_safe() {
    local base_url=""
    local api_key=""
    # 方式1: SQLite DB
    if [ -f "$CCS_DB" ]; then
        local result
        result=$(CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import sqlite3, json, os, sys
try:
    db = sqlite3.connect(os.environ['CCS_DB'])
    row = db.execute("SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1").fetchone()
    db.close()
    if row:
        cfg = json.loads(row[0])
        env = cfg.get('env', {})
        bu = env.get('ANTHROPIC_BASE_URL', '')
        ak = env.get('ANTHROPIC_AUTH_TOKEN', '') or env.get('ANTHROPIC_API_KEY', '')
        if bu and ak:
            print(bu)
            print(ak)
except Exception:
    pass
PYEOF
)
        if [ -n "$result" ]; then
            base_url=$(echo "$result" | head -1)
            api_key=$(echo "$result" | tail -1)
        fi
    fi
    # 方式2: providers.json
    if [ -z "$api_key" ] && [ -f "$CONFIG_FILE" ]; then
        local result
        result=$(CONFIG_FILE="$CONFIG_FILE" python3 - <<'PYEOF' 2>/dev/null
import json, os, sys
try:
    with open(os.environ['CONFIG_FILE']) as f:
        d = json.load(f)
    for p in d.get('providers', []):
        if p.get('enabled') and p.get('base_url') and p.get('api_key'):
            print(p['base_url'])
            print(p['api_key'])
            break
except Exception:
    pass
PYEOF
)
        if [ -n "$result" ]; then
            base_url=$(echo "$result" | head -1)
            api_key=$(echo "$result" | tail -1)
        fi
    fi
    if [ -n "$base_url" ] && [ -n "$api_key" ]; then
        export ANTHROPIC_BASE_URL="$base_url"
        export ANTHROPIC_API_KEY="$api_key"
        export ANTHROPIC_AUTH_TOKEN="$api_key"
        return 0
    fi
    return 1
}

if [ "$CC_SWITCH_RUNNING" -eq 0 ]; then
    if [ "$HAS_PYTHON3" = "1" ]; then
        read_config_safe || true
    else
        echo "  [!] python3 不可用，无法读取直连配置"
    fi
fi

# 检查是否有配置
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo ""
    if [ "$HAS_PYTHON3" != "1" ]; then
        echo "[ERROR] 需要 python3 来读取 API 配置，请安装 python3 或确保 CC Switch 代理正常运行"
    else
        echo "[ERROR] 未配置 API。请打开 CC Switch 添加 Provider："
        echo "   $BIN_DIR/cc-switch"
    fi
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
