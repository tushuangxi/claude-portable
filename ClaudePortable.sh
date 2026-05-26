#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch · Linux
# ═══════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

# 处理 --unlock 参数
if [ "${1:-}" = "--unlock" ]; then
    LOCK_FILE="$SCRIPT_DIR/data/.lock"
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        echo "  [ok] 已移除绑定锁，下次运行将重新绑定到当前位置。"
    else
        echo "  [info] 没有绑定锁需要移除。"
    fi
    exit 0
fi

# Banner
GOLD='\033[38;5;220m'
AMBER='\033[38;5;214m'
BRONZE='\033[38;5;166m'
NC='\033[0m'
echo ""
echo -e "${GOLD}  ██╗   ██╗██╗  ██╗   ██╗ ██████╗${NC}"
echo -e "${GOLD}  ╚██╗ ██╔╝██║  ╚██╗ ██╔╝██╔════╝${NC}"
echo -e "${AMBER}   ╚████╔╝ ██║   ╚████╔╝ ██║  ███╗${NC}"
echo -e "${AMBER}    ╚██╔╝  ██║    ╚██╔╝  ██║   ██║${NC}"
echo -e "${BRONZE}     ██║   ███████╗██║   ╚██████╔╝${NC}"
echo -e "${BRONZE}     ╚═╝   ╚══════╝╚═╝    ╚═════╝${NC}"
echo ""
echo "     Claude Code Portable"
echo ""

# 架构检测
case "$ARCH" in
    x86_64|amd64)  BIN_DIR="$SCRIPT_DIR/bin/linux-x64" ;;
    aarch64|arm64) echo "[ERROR] Linux ARM64 暂不支持"; exit 1 ;;
    *)             echo "[ERROR] 不支持的架构: $ARCH"; exit 1 ;;
esac

if [ ! -f "$BIN_DIR/claude" ]; then
    echo "[ERROR] 未找到 Claude Code: $BIN_DIR/claude"
    exit 1
fi

chmod +x "$BIN_DIR/claude" "$BIN_DIR/cc-switch" 2>/dev/null

# ═══════════════════════════════════════════
# 便携目录设置
# ═══════════════════════════════════════════
PORTABLE_DATA="$SCRIPT_DIR/data"
PORTABLE_CCS="$PORTABLE_DATA/.cc-switch"
PORTABLE_CLAUDE="$PORTABLE_DATA/.claude"
SYS_CCS="$HOME/.cc-switch"
SYS_CLAUDE="$HOME/.claude"
CCS_DB="$PORTABLE_CCS/cc-switch.db"
LIB_DIR="$SCRIPT_DIR/lib"
LOCK_FILE="$PORTABLE_DATA/.lock"

mkdir -p "$PORTABLE_CCS" "$PORTABLE_CLAUDE"

# ═══════════════════════════════════════════
# 设备绑定校验
# ═══════════════════════════════════════════
if [ -f "$LOCK_FILE" ] && [ -f "$LIB_DIR/binding.sh" ]; then
    chmod +x "$LIB_DIR/binding.sh" 2>/dev/null
    bash "$LIB_DIR/binding.sh" check "$SCRIPT_DIR" "$LOCK_FILE"
    bind_result=$?
    if [ $bind_result -eq 1 ]; then
        echo ""
        echo "  ============================================================"
        echo "  [ERROR] 此便携包已绑定到原始设备。"
        echo "  ============================================================"
        echo ""
        echo "  当前位置与绑定设备不匹配。这是防复制保护机制。"
        echo ""
        echo "  如果你是原始所有者并主动移动了它："
        echo "    ./ClaudePortable.sh --unlock"
        echo ""
        exit 1
    fi
    if [ $bind_result -eq 3 ]; then
        echo "  [warn] 无法验证设备绑定（继续运行）。"
    fi
fi

# 一次性迁移：把系统已有的数据复制到便携包
migrate_dir() {
    local src="$1" dst="$2"
    if [ -d "$src" ] && [ ! -L "$src" ]; then
        if [ -n "$(ls -A "$src" 2>/dev/null)" ] && [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
            echo "  [migrate] 复制系统现有数据到便携包: $src → $dst"
            cp -a "$src/." "$dst/" 2>/dev/null
        fi
    fi
}
migrate_dir "$SYS_CCS" "$PORTABLE_CCS"
migrate_dir "$SYS_CLAUDE" "$PORTABLE_CLAUDE"

# 创建符号链接
ensure_symlink() {
    local link="$1" target="$2"
    if [ -L "$link" ]; then
        local current="$(readlink "$link")"
        if [ "$current" = "$target" ]; then
            return 0
        fi
        rm "$link" 2>/dev/null
    elif [ -d "$link" ]; then
        rmdir "$link" 2>/dev/null || rm -rf "$link" 2>/dev/null
    fi
    ln -s "$target" "$link" 2>/dev/null
}
ensure_symlink "$SYS_CCS" "$PORTABLE_CCS"
ensure_symlink "$SYS_CLAUDE" "$PORTABLE_CLAUDE"

CC_SWITCH_PID=""
WE_STARTED_CCS=0

# 退出时清理符号链接
cleanup() {
    if [ "$WE_STARTED_CCS" = "1" ] && [ -n "$CC_SWITCH_PID" ] && kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
        kill -TERM "$CC_SWITCH_PID" 2>/dev/null
        for _ in 1 2 3 4 5; do
            kill -0 "$CC_SWITCH_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
            kill -9 "$CC_SWITCH_PID" 2>/dev/null
        fi
        # 仅清理本进程的直接子进程
        for child in $(pgrep -P "$CC_SWITCH_PID" 2>/dev/null); do
            kill -9 "$child" 2>/dev/null
        done
    fi
    [ -L "$SYS_CCS" ] && rm "$SYS_CCS" 2>/dev/null
    [ -L "$SYS_CLAUDE" ] && rm "$SYS_CLAUDE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════
# 检查配置（验证 DB 中真有 provider，不只是文件大小）
# ═══════════════════════════════════════════
has_valid_config() {
    [ -f "$CCS_DB" ] || return 1
    if ! command -v python3 &>/dev/null; then
        local size
        size=$(stat -c%s "$CCS_DB" 2>/dev/null || stat -f%z "$CCS_DB" 2>/dev/null || echo 0)
        [ "$size" -gt 4096 ]
        return $?
    fi
    CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import os, re, sys
try:
    with open(os.environ['CCS_DB'], 'rb') as f:
        text = f.read().decode('utf-8', errors='replace')
    url = re.search(r'"ANTHROPIC_BASE_URL"\s*:\s*"([^"]+)"', text)
    key = re.search(r'"ANTHROPIC_AUTH_TOKEN"\s*:\s*"([^"]+)"', text)
    if not key:
        key = re.search(r'"ANTHROPIC_API_KEY"\s*:\s*"([^"]+)"', text)
    if url and key and len(url.group(1)) > 5 and len(key.group(1)) > 5:
        sys.exit(0)
except Exception:
    pass
sys.exit(1)
PYEOF
}

if ! has_valid_config; then
    echo "═══════════════════════════════════════════"
    echo "  首次运行 - 配置 API"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "  正在打开 CC Switch GUI..."
    echo "  添加一个 Provider 并保存（无需关闭 CC Switch）"
    echo ""
    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        echo "  [!] 未检测到图形界面（DISPLAY 未设置）"
        echo "  请在带图形界面的环境运行，或在另一台机器配置后复制 DB 过来"
        exit 1
    fi
    "$BIN_DIR/cc-switch" >/dev/null 2>&1 &
    CC_SWITCH_PID=$!
    WE_STARTED_CCS=1

    echo "  等待配置..."
    for i in $(seq 1 150); do
        sleep 2
        if has_valid_config; then
            echo "  [ok] 检测到 Provider，继续启动"
            sleep 1
            break
        fi
    done

    if ! has_valid_config; then
        echo "  [!] 等待超时，请重新运行"
        exit 1
    fi
fi

# ═══════════════════════════════════════════
# 从 DB 读取 API 配置
# ═══════════════════════════════════════════
read_config() {
    if ! command -v python3 &>/dev/null; then
        echo "  [!] 需要 python3 读取配置"
        return 1
    fi
    local result attempt
    for attempt in 1 2 3; do
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
            export ANTHROPIC_BASE_URL=$(echo "$result" | head -1)
            export ANTHROPIC_AUTH_TOKEN=$(echo "$result" | tail -1)
            unset ANTHROPIC_API_KEY
            return 0
        fi
        sleep 1
    done
    return 1
}

if read_config; then
    echo "  [ok] 配置已加载"
else
    echo "  [!] 无法从 DB 读取配置"
    exit 1
fi

# ═══════════════════════════════════════════
# 创建绑定锁（首次成功运行后）
# ═══════════════════════════════════════════
if [ ! -f "$LOCK_FILE" ] && [ -f "$LIB_DIR/binding.sh" ]; then
    bash "$LIB_DIR/binding.sh" create "$SCRIPT_DIR" "$LOCK_FILE" 2>/dev/null
    if [ -f "$LOCK_FILE" ]; then
        echo "  [ok] 已绑定到当前设备。解绑命令：./ClaudePortable.sh --unlock"
    fi
fi

# ═══════════════════════════════════════════
# 启动 Claude Code
# ═══════════════════════════════════════════
echo "  架构: $ARCH | 数据: 便携包内"
echo ""

"$BIN_DIR/claude" "$@"
