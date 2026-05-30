#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch · macOS
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
    arm64)  BIN_DIR="$SCRIPT_DIR/bin/macos-arm64" ;;
    x86_64) BIN_DIR="$SCRIPT_DIR/bin/macos-x64" ;;
    *)      echo "[ERROR] 不支持的架构: $ARCH"; exit 1 ;;
esac

if [ ! -f "$BIN_DIR/claude" ]; then
    echo "[ERROR] 未找到 Claude Code: $BIN_DIR/claude"
    exit 1
fi

chmod +x "$BIN_DIR/claude" "$BIN_DIR/cc-switch" 2>/dev/null

# macOS: 移除 quarantine 属性（Gatekeeper 拦截）
xattr -dr com.apple.quarantine "$BIN_DIR/claude" 2>/dev/null
xattr -dr com.apple.quarantine "$BIN_DIR/cc-switch" 2>/dev/null

# ═══════════════════════════════════════════
# 单实例锁（防止并发运行）
# ═══════════════════════════════════════════
RUN_LOCK="$SCRIPT_DIR/data/.running"
mkdir -p "$SCRIPT_DIR/data"
if [ -f "$RUN_LOCK" ]; then
    PREV_PID=$(cat "$RUN_LOCK" 2>/dev/null | head -1 | tr -d '[:space:]')
    if [ -n "$PREV_PID" ] && kill -0 "$PREV_PID" 2>/dev/null; then
        echo "  [info] 已有另一个实例正在运行 (PID $PREV_PID)。"
        echo "  如果错误，请删除：$RUN_LOCK"
        exit 1
    fi
    # Stale lock — clear
    rm -f "$RUN_LOCK"
fi
echo $$ > "$RUN_LOCK"

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
# 设备绑定校验（双 lock 文件，删除一个不能绕过）
# ═══════════════════════════════════════════
LOCK_FILE2="$PORTABLE_CCS/.bind"
LOCK_PRESENT=0
[ -f "$LOCK_FILE" ] && LOCK_PRESENT=1
[ -f "$LOCK_FILE2" ] && LOCK_PRESENT=1

if [ "$LOCK_PRESENT" = "1" ] && [ -f "$LIB_DIR/binding.sh" ]; then
    chmod +x "$LIB_DIR/binding.sh" 2>/dev/null
    # 校验任一存在的 lock。两个文件内容应一致——若不一致说明
    # 有人篡改了其中一个，按最严格的策略对待：用任一现存 lock
    # 检查；若其中一个 hash mismatch 但另一个 match，仍然 deny。
    # （但其实若 hash mismatch，说明此设备非原设备，两个 lock
    # 都会 mismatch，不存在「一对一错」的情况——除非用户故意改）
    bind_failed=0
    bind_warned=0
    for active_lock in "$LOCK_FILE" "$LOCK_FILE2"; do
        [ -f "$active_lock" ] || continue
        bash "$LIB_DIR/binding.sh" check "$SCRIPT_DIR" "$active_lock"
        r=$?
        case $r in
            1) bind_failed=1; break ;;   # mismatch → 立即拒绝
            3) bind_warned=1 ;;           # 无法计算 fingerprint
        esac
    done
    if [ "$bind_failed" = "1" ]; then
        echo ""
        echo "  ============================================================"
        echo "  [ERROR] 此便携包已绑定到原始设备。"
        echo "  ============================================================"
        echo ""
        echo "  当前位置与绑定设备不匹配。这是防复制保护机制。"
        echo "  此便携包不能被复制到其他设备运行。"
        echo ""
        echo "  如果你是原始所有者并主动移动了它："
        echo "    ./ClaudePortable.command --unlock"
        echo ""
        exit 1
    fi
    if [ "$bind_warned" = "1" ]; then
        echo "  [warn] 无法验证设备绑定（继续运行）。"
    fi
fi

# 注意：之前这里有一个 `migrate_dir`，它先把 ~/.cc-switch 拷到便携包，
# 然后又调 `ensure_symlink`。结果是 ensure_symlink 看到便携包有数据、
# 系统目录也有数据 → 走 "backup system dir" 分支，把 ~/.cc-switch
# 重命名为 .before-portable.<timestamp>。这是噪声不是数据丢失，但用户
# 体验差。改为单路径：直接调 ensure_symlink，让它一气呵成处理迁移、
# 拷贝、链接。
ensure_symlink() {
    local link="$1" target="$2"
    # 已经是指向目标的符号链接 → 幂等
    if [ -L "$link" ]; then
        local current="$(readlink "$link")"
        if [ "$current" = "$target" ]; then
            return 0
        fi
        # 指向其他位置，删除并重建
        rm "$link" 2>/dev/null
    elif [ -d "$link" ]; then
        # 真目录 — 用户有预装的系统版本。
        # 仅当便携目录为空时才迁移（避免覆盖便携数据）。
        # 绝不 rm -rf 用户数据。
        if [ -n "$(ls -A "$link" 2>/dev/null)" ]; then
            if [ -z "$(ls -A "$target" 2>/dev/null)" ]; then
                echo "  [migrate] $link → $target"
                # 重要：cp 失败时绝不能删源数据。
                # 之前的版本是 `cp -a ... 2>/dev/null` 然后 rm -rf，
                # 如果 cp 因磁盘满/权限/文件锁部分失败，会永久丢失用户数据。
                local cp_err
                cp_err=$(mktemp -t claude-cp.XXXXXX 2>/dev/null) || cp_err="/tmp/claude-cp.$$"
                if cp -a "$link/." "$target/" 2>"$cp_err"; then
                    rm -f "$cp_err"
                else
                    echo "  [ERROR] 迁移失败，保留系统目录不删除：$link"
                    [ -s "$cp_err" ] && sed 's/^/    /' "$cp_err" >&2
                    rm -f "$cp_err"
                    # 系统目录还在，便携包没数据 → 直接退出，不创建符号链接
                    # 让用户手动决断比静默丢数据强
                    return 1
                fi
            else
                echo "  [warn] 便携包已有数据，跳过系统目录迁移: $link"
                # 把系统目录改名备份而不是删除
                local backup="${link}.before-portable.$(date +%Y%m%d-%H%M%S)"
                mv "$link" "$backup" 2>/dev/null && echo "  [info] 系统数据已备份到: $backup"
                ln -s "$target" "$link" 2>/dev/null
                return 0
            fi
        fi
        # 走到这里：cp 已成功（或源目录原本就是空的）。
        # 删除源目录腾出位置创建符号链接。
        rm -rf "$link" 2>/dev/null
    fi
    ln -s "$target" "$link" 2>/dev/null
}
ensure_symlink "$SYS_CCS" "$PORTABLE_CCS"
ensure_symlink "$SYS_CLAUDE" "$PORTABLE_CLAUDE"

CC_SWITCH_PID=""
WE_STARTED_CCS=0

# 退出时清理符号链接（只清符号链接，不动真目录）
cleanup() {
    # 优雅杀掉本脚本启动的 cc-switch
    if [ "$WE_STARTED_CCS" = "1" ] && [ -n "$CC_SWITCH_PID" ] && kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
        # 重要：先收集子进程列表再 kill 父进程。
        # 父进程被 kill 后，子进程会 reparent 到 init (PID 1)，
        # `pgrep -P parent_pid` 就找不到它们了。
        local children
        children=$(pgrep -P "$CC_SWITCH_PID" 2>/dev/null || true)

        # 先 SIGTERM 主进程
        kill -TERM "$CC_SWITCH_PID" 2>/dev/null
        # 等最多 5 秒让 Electron 优雅关闭
        for _ in 1 2 3 4 5; do
            kill -0 "$CC_SWITCH_PID" 2>/dev/null || break
            sleep 1
        done
        # 还活着 → SIGKILL
        if kill -0 "$CC_SWITCH_PID" 2>/dev/null; then
            kill -9 "$CC_SWITCH_PID" 2>/dev/null
        fi
        # 清理之前收集的子进程（包括优雅关闭时漏掉的）
        for child in $children; do
            kill -9 "$child" 2>/dev/null
        done
    fi
    [ -L "$SYS_CCS" ] && rm "$SYS_CCS" 2>/dev/null
    [ -L "$SYS_CLAUDE" ] && rm "$SYS_CLAUDE" 2>/dev/null
    # 清理单实例锁
    [ -f "$RUN_LOCK" ] && rm -f "$RUN_LOCK"
}
trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════
# 检查配置（验证 DB 中真有 provider，不只是文件大小）
# ═══════════════════════════════════════════
has_valid_config() {
    [ -f "$CCS_DB" ] || return 1
    if command -v python3 &>/dev/null; then
        : # 走 python3 路径
    elif command -v sqlite3 &>/dev/null; then
        # python3 不在 → 退化到 sqlite3 CLI（macOS 自带 /usr/bin/sqlite3）
        local row
        row=$(sqlite3 -readonly "$CCS_DB" \
            "SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1;" 2>/dev/null)
        if [ -n "$row" ] && \
           printf '%s' "$row" | grep -q '"ANTHROPIC_BASE_URL"' && \
           printf '%s' "$row" | grep -qE '"ANTHROPIC_(AUTH_TOKEN|API_KEY)"'; then
            return 0
        fi
        return 1
    else
        # 既无 python3 也无 sqlite3。Size 检查不可靠：
        # 空 SQLite DB 文件经常 > 4096 字节（schema + page header 占空间）。
        # 此情况我们「返回未配置」（fail-closed），让 first-run 流程
        # 启动 GUI，比误判已配置然后用空 token 启动 Claude 更安全。
        return 1
    fi
    CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import sqlite3, json, os, sys
# Use SQLite query instead of regex on raw bytes:
#   - regex would match deleted-but-not-vacuumed rows (SQLite lazy delete)
#   - it would also match across rows, returning false positive
#   - reading the whole file as text wastes memory on large DBs
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
    echo "  正在打开 CC Switch GUI..."
    echo "  添加一个 Provider 并保存（无需关闭 CC Switch）"
    echo ""
    "$BIN_DIR/cc-switch" >/dev/null 2>&1 &
    CC_SWITCH_PID=$!
    WE_STARTED_CCS=1

    echo "  等待配置..."
    # 5 分钟最长等待。每 30 秒打一个进度提示，让用户知道脚本还活着。
    for i in $(seq 1 150); do
        sleep 2
        if has_valid_config; then
            echo ""
            echo "  [ok] 检测到 Provider，继续启动"
            sleep 1
            break
        fi
        # 每 15 次（30 秒）打一个点
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
    if ! command -v python3 &>/dev/null; then
        echo "  [!] 需要 python3 读取配置"
        return 1
    fi
    # Retry up to 3 times in case DB is being written
    local result attempt
    for attempt in 1 2 3; do
        result=$(CCS_DB="$CCS_DB" python3 - <<'PYEOF' 2>/dev/null
import sqlite3, json, os, sys
try:
    # timeout=2.0: don't block more than 2s on a writer lock.
    # The outer bash loop retries 3 times so total worst-case is ~6s,
    # vs the SQLite default of 5s × 3 = 15s.
    db = sqlite3.connect(os.environ['CCS_DB'], timeout=2.0)
    row = db.execute("SELECT settings_config FROM providers WHERE app_type='claude' AND is_current=1 LIMIT 1").fetchone()
    db.close()
    if row:
        cfg = json.loads(row[0])
        env = cfg.get('env', {})
        bu = env.get('ANTHROPIC_BASE_URL', '')
        ak = env.get('ANTHROPIC_AUTH_TOKEN', '') or env.get('ANTHROPIC_API_KEY', '')
        # Trim whitespace — cc-switch may store keys with trailing whitespace
        # if user pasted with extra characters. Without this, claude API
        # calls would 404/401 on the malformed credential.
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
            # 用 printf 而不是 echo 避免反斜杠转义问题
            # （某些 echo 实现会解释 \n、\t 等）
            export ANTHROPIC_BASE_URL=$(printf '%s\n' "$result" | head -1)
            export ANTHROPIC_AUTH_TOKEN=$(printf '%s\n' "$result" | tail -1)
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
# 创建/修复绑定锁（首次成功运行后，写入两个位置）
# 任一 lock 文件缺失就重新生成（保证防绕过完整性）
# ═══════════════════════════════════════════
if [ -f "$LIB_DIR/binding.sh" ]; then
    if [ ! -f "$LOCK_FILE" ]; then
        bash "$LIB_DIR/binding.sh" create "$SCRIPT_DIR" "$LOCK_FILE" 2>/dev/null
        if [ -f "$LOCK_FILE" ]; then
            echo "  [ok] 已绑定到当前设备。解绑命令：./ClaudePortable.command --unlock"
        fi
    fi
    # 镜像 lock 缺失就补上（防止用户手动删除单个文件绕过绑定）
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

# 提前清理：删 symlink 和 run lock（不依赖 trap 在 read 之后才跑）。
# 这样即便用户在 read -p 等待时拔 U 盘，主目录也已经干净，
# 不会留下指向不可达 USB 路径的 broken symlink。
[ -L "$SYS_CCS" ] && rm "$SYS_CCS" 2>/dev/null
[ -L "$SYS_CLAUDE" ] && rm "$SYS_CLAUDE" 2>/dev/null
[ -f "$RUN_LOCK" ] && rm -f "$RUN_LOCK"

# 如果 claude 异常退出，留窗口给用户看错误
if [ $CLAUDE_EXIT -ne 0 ]; then
    echo ""
    echo "  Claude 退出码: $CLAUDE_EXIT"
    read -p "  按回车关闭窗口... " _
fi
exit $CLAUDE_EXIT
