#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch · Linux
# ═══════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

# 处理 --unlock 参数（删除两个 lock 文件）
if [ "${1:-}" = "--unlock" ]; then
    LOCK_FILE="$SCRIPT_DIR/data/.lock"
    LOCK_FILE2="$SCRIPT_DIR/data/.cc-switch/.bind"
    REMOVED=0
    [ -f "$LOCK_FILE" ] && { rm -f "$LOCK_FILE"; REMOVED=1; }
    [ -f "$LOCK_FILE2" ] && { rm -f "$LOCK_FILE2"; REMOVED=1; }
    if [ "$REMOVED" = "1" ]; then
        echo "  [ok] 已移除绑定锁，下次运行将重新绑定到当前位置。"
    else
        echo "  [info] 没有绑定锁需要移除。"
    fi
    exit 0
fi

# 处理 --config 参数（随时打开配置中心）
if [ "${1:-}" = "--config" ]; then
    CONFIG_SERVER="$SCRIPT_DIR/lib/config_server.py"
    if command -v python3 &>/dev/null && [ -f "$CONFIG_SERVER" ]; then
        echo "  打开配置中心 http://127.0.0.1:17580 ..."
        exec python3 "$CONFIG_SERVER"
    elif [ -x "$SCRIPT_DIR/bin/linux-x64/cc-switch" ]; then
        exec "$SCRIPT_DIR/bin/linux-x64/cc-switch"
    else
        echo "  [!] 未找到 python3 或 cc-switch"
        exit 1
    fi
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
# 单实例锁（原子 mkdir 持锁）
# ═══════════════════════════════════════════
RUN_LOCK_DIR="$SCRIPT_DIR/data/.running"
mkdir -p "$SCRIPT_DIR/data"

if [ -d "$RUN_LOCK_DIR" ]; then
    PREV_PID=""
    [ -f "$RUN_LOCK_DIR/pid" ] && PREV_PID=$(cat "$RUN_LOCK_DIR/pid" 2>/dev/null | tr -d '[:space:]')
    if [ -n "$PREV_PID" ] && kill -0 "$PREV_PID" 2>/dev/null; then
        echo "  [info] Another instance is already running (PID $PREV_PID)."
        echo "  If incorrect, remove: $RUN_LOCK_DIR"
        exit 1
    fi
    rm -rf "$RUN_LOCK_DIR" 2>/dev/null
fi

if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
    echo "  [info] Another instance is already running (concurrent start)."
    echo "  If incorrect, remove: $RUN_LOCK_DIR"
    exit 1
fi
echo $$ > "$RUN_LOCK_DIR/pid"
RUN_LOCK="$RUN_LOCK_DIR"

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
# 设备绑定校验（双 lock 文件）
# ═══════════════════════════════════════════
LOCK_FILE2="$PORTABLE_CCS/.bind"
LOCK_PRESENT=0
[ -f "$LOCK_FILE" ] && LOCK_PRESENT=1
[ -f "$LOCK_FILE2" ] && LOCK_PRESENT=1

if [ "$LOCK_PRESENT" = "1" ] && [ -f "$LIB_DIR/binding.sh" ]; then
    chmod +x "$LIB_DIR/binding.sh" 2>/dev/null
    # Validate every existing lock. Both files should have the same hash;
    # any mismatch immediately denies launch. This makes the dual-lock
    # design actually pay off: replacing one file with random data still
    # gets caught when the other is checked.
    bind_failed=0
    bind_warned=0
    for active_lock in "$LOCK_FILE" "$LOCK_FILE2"; do
        [ -f "$active_lock" ] || continue
        bash "$LIB_DIR/binding.sh" check "$SCRIPT_DIR" "$active_lock"
        r=$?
        case $r in
            1) bind_failed=1; break ;;
            3) bind_warned=1 ;;
        esac
    done
    if [ "$bind_failed" = "1" ]; then
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
    if [ "$bind_warned" = "1" ]; then
        echo "  [warn] Could not verify drive binding (continuing)."
    fi
fi

# 注：之前 migrate_dir 与 ensure_symlink 重复迁移；改为单路径，
# ensure_symlink 自身完整处理迁移 + 链接。
ensure_symlink() {
    local link="$1" target="$2"
    if [ -L "$link" ]; then
        local current="$(readlink "$link")"
        if [ "$current" = "$target" ]; then
            return 0
        fi
        rm "$link" 2>/dev/null
    elif [ -d "$link" ]; then
        # Real directory — user has a pre-existing system install.
        # Migrate only if portable target is empty (don't overwrite
        # existing portable data).
        if [ -n "$(ls -A "$link" 2>/dev/null)" ]; then
            if [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
                echo "  [migrate] $link → $target"
                # cp failure must NOT result in source removal.
                # Previously: `cp -a ... 2>/dev/null` then rm -rf, which
                # would silently destroy data on partial copy failure.
                local cp_err
                cp_err=$(mktemp -t claude-cp.XXXXXX 2>/dev/null) || cp_err="/tmp/claude-cp.$$"
                if cp -a "$link/." "$target/" 2>"$cp_err"; then
                    rm -f "$cp_err"
                else
                    echo "  [ERROR] migration failed; system dir kept intact: $link"
                    [ -s "$cp_err" ] && sed 's/^/    /' "$cp_err" >&2
                    rm -f "$cp_err"
                    return 1
                fi
            else
                echo "  [warn] portable target not empty, skipping merge"
                local backup="${link}.before-portable.$(date +%Y%m%d-%H%M%S)"
                mv "$link" "$backup" 2>/dev/null && echo "  [info] system data backed up to: $backup"
                ln -s "$target" "$link" 2>/dev/null
                return 0
            fi
        fi
        # Source dir is empty (or cp succeeded). Remove it so we can
        # replace with a symlink.
        rm -rf "$link" 2>/dev/null
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
        # 重要：先收集子进程列表再 kill 父进程。
        # 父进程被 kill 后，子进程会 reparent 到 init (PID 1)，
        # `pgrep -P parent_pid` 就找不到它们了。
        local children
        children=$(pgrep -P "$CC_SWITCH_PID" 2>/dev/null || true)

        kill -TERM "$CC_SWITCH_PID" 2>/dev/null
        for _ in 1 2 3 4 5; do
            kill -0 "$CC_SWITCH_PID" 2>/dev/null || break
            sleep 1
        done
        if kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
            kill -9 "$CC_SWITCH_PID" 2>/dev/null
        fi
        # 清理之前收集的子进程（避免父进程死后变孤儿丢失）
        for child in $children; do
            kill -9 "$child" 2>/dev/null
        done
    fi
    [ -L "$SYS_CCS" ] && rm "$SYS_CCS" 2>/dev/null
    [ -L "$SYS_CLAUDE" ] && rm "$SYS_CLAUDE" 2>/dev/null
    # 清理单实例锁（dir 形式）
    [ -d "$RUN_LOCK" ] && rm -rf "$RUN_LOCK"
}
trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════
# 检查配置（验证 DB 中真有 provider，不只是文件大小）
# ═══════════════════════════════════════════
has_valid_config() {
    [ -f "$CCS_DB" ] || return 1
    if command -v python3 &>/dev/null; then
        : # use python3 path below
    elif command -v sqlite3 &>/dev/null; then
        # No python3 → fall back to sqlite3 CLI
        local row
        row=$(sqlite3 -readonly "$CCS_DB" \
            "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1;" 2>/dev/null)
        # Require a non-empty (>=6 char) value, else an empty value would
        # false-positive as "configured".
        if [ -n "$row" ] && \
           printf '%s' "$row" | grep -qE '"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"[^"]{6,}"' && \
           printf '%s' "$row" | grep -qE '"ANTHROPIC_(AUTH_TOKEN|API_KEY)"[[:space:]]*:[[:space:]]*"[^"]{6,}"'; then
            return 0
        fi
        return 1
    else
        # Neither python3 nor sqlite3. Size check is unreliable —
        # an empty SQLite DB is often >4KB (schema + page header).
        # Fail closed: report "not configured" so first-run UI runs,
        # vs. the previous behavior of false-positive "configured" and
        # launching Claude with empty creds.
        return 1
    fi
    CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import sqlite3, json, os, sys
# Use proper SQLite query (regex on raw bytes matched deleted rows
# and false positives across rows).
try:
    db = sqlite3.connect(os.environ['CCS_DB'], timeout=2.0)
    row = db.execute(
        "SELECT settings_config FROM providers "
        "WHERE app_type='claude' AND is_current=1 LIMIT 1"
    ).fetchone()
    db.close()
    if not row:
        sys.exit(1)
    cfg = json.loads(row[0])
    env = cfg.get('env', {})
    url = env.get('ANTHROPIC_BASE_URL', '')
    key = env.get('ANTHROPIC_AUTH_TOKEN', '') or env.get('ANTHROPIC_API_KEY', '')
    if isinstance(url, str) and isinstance(key, str) and len(url) > 5 and len(key) > 5:
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
    CONFIG_SERVER="$LIB_DIR/config_server.py"
    if command -v python3 &>/dev/null && [ -f "$CONFIG_SERVER" ]; then
        # 优先用配置中心（图文引导）。无图形界面时它仍能跑——
        # 用户可在另一台机器浏览器访问，或用 SSH 端口转发。
        echo "  正在打开配置中心 http://127.0.0.1:17580 ..."
        echo "  按引导选供应商、填 Key、测试、保存即可。"
        echo ""
        python3 "$CONFIG_SERVER" >/dev/null 2>&1 &
        CC_SWITCH_PID=$!
        WE_STARTED_CCS=1
    else
        echo "  正在打开 CC Switch GUI..."
        echo "  添加一个 Provider 并保存（无需关闭 CC Switch）"
        echo ""
        if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
            echo "  [!] 未检测到图形界面（DISPLAY 未设置），且无 python3 配置中心"
            echo "  请安装 python3，或在带图形界面的环境运行，或复制已配置的 DB 过来"
            exit 1
        fi
        "$BIN_DIR/cc-switch" >/dev/null 2>&1 &
        CC_SWITCH_PID=$!
        WE_STARTED_CCS=1
    fi

    echo "  等待配置..."
    for i in $(seq 1 150); do
        sleep 2
        if has_valid_config; then
            echo ""
            echo "  [ok] 检测到 Provider，继续启动"
            sleep 1
            break
        fi
        # cc-switch 死亡检测：若 GUI 已退出但仍未配好，立即报错。
        if ! kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
            echo ""
            echo "  [!] CC Switch exited before config saved. Re-run to retry."
            exit 1
        fi
        if [ $((i % 15)) -eq 0 ]; then
            printf "."
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
    if command -v python3 &>/dev/null; then
        local result attempt
        for attempt in 1 2 3; do
            result=$(CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import sqlite3, json, os, sys
try:
    # timeout=2.0: don't block on writer lock; outer loop retries.
    db = sqlite3.connect(os.environ['CCS_DB'], timeout=2.0)
    row = db.execute("SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1").fetchone()
    db.close()
    if row:
        cfg = json.loads(row[0])
        env = cfg.get('env', {})
        bu = env.get('ANTHROPIC_BASE_URL', '')
        ak = env.get('ANTHROPIC_AUTH_TOKEN', '') or env.get('ANTHROPIC_API_KEY', '')
        # Trim whitespace defensively (see .command for rationale).
        if isinstance(bu, str): bu = bu.strip()
        if isinstance(ak, str): ak = ak.strip()
        if bu and ak:
            print(bu)
            print(ak)
except Exception:
    pass
PYEOF
)
            if [ -n "$result" ]; then
                export ANTHROPIC_BASE_URL=$(printf '%s\n' "$result" | head -1)
                export ANTHROPIC_AUTH_TOKEN=$(printf '%s\n' "$result" | tail -1)
                unset ANTHROPIC_API_KEY
                return 0
            fi
            sleep 1
        done
        return 1
    fi

    if command -v sqlite3 &>/dev/null; then
        local row attempt
        for attempt in 1 2 3; do
            row=$(sqlite3 -readonly "$CCS_DB" \
                "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1;" 2>/dev/null)
            if [ -n "$row" ]; then
                local bu ak
                bu=$(printf '%s' "$row" | sed -nE 's/.*"ANTHROPIC_BASE_URL"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
                ak=$(printf '%s' "$row" | sed -nE 's/.*"ANTHROPIC_AUTH_TOKEN"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
                [ -z "$ak" ] && ak=$(printf '%s' "$row" | sed -nE 's/.*"ANTHROPIC_API_KEY"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
                bu=$(printf '%s' "$bu" | awk '{$1=$1};1')
                ak=$(printf '%s' "$ak" | awk '{$1=$1};1')
                if [ -n "$bu" ] && [ -n "$ak" ]; then
                    export ANTHROPIC_BASE_URL="$bu"
                    export ANTHROPIC_AUTH_TOKEN="$ak"
                    unset ANTHROPIC_API_KEY
                    return 0
                fi
            fi
            sleep 1
        done
        return 1
    fi

    echo "  [!] need python3 or sqlite3 to read config"
    return 1
}

if read_config; then
    echo "  [ok] 配置已加载"
else
    echo "  [!] 无法从 DB 读取配置"
    exit 1
fi

# ═══════════════════════════════════════════
# 创建/修复绑定锁（任一缺失就补上）
# ═══════════════════════════════════════════
if [ -f "$LIB_DIR/binding.sh" ]; then
    if [ ! -f "$LOCK_FILE" ]; then
        bash "$LIB_DIR/binding.sh" create "$SCRIPT_DIR" "$LOCK_FILE" 2>/dev/null
        if [ -f "$LOCK_FILE" ]; then
            echo "  [ok] 已绑定到当前设备。解绑命令：./ClaudePortable.sh --unlock"
        fi
    fi
    if [ ! -f "$PORTABLE_CCS/.bind" ]; then
        bash "$LIB_DIR/binding.sh" create "$SCRIPT_DIR" "$PORTABLE_CCS/.bind" 2>/dev/null
    fi
fi

# ═══════════════════════════════════════════
# 启动 Claude Code
# ═══════════════════════════════════════════
echo "  架构: $ARCH | 数据: 便携包内"
echo ""

"$BIN_DIR/claude" "$@"
CLAUDE_EXIT=$?

# 提前清理：不依赖 trap。即便用户在终端关闭前拔 U 盘，
# 主目录也已干净，不会留下指向不可达 USB 路径的 broken symlink。
[ -L "$SYS_CCS" ] && rm "$SYS_CCS" 2>/dev/null
[ -L "$SYS_CLAUDE" ] && rm "$SYS_CLAUDE" 2>/dev/null
[ -d "$RUN_LOCK" ] && rm -rf "$RUN_LOCK"

exit $CLAUDE_EXIT
