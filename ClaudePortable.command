#!/bin/bash
# ═══════════════════════════════════════════
# Claude Code Portable + CC Switch · macOS
# ═══════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"

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
# 便携目录设置
# ═══════════════════════════════════════════
PORTABLE_DATA="$SCRIPT_DIR/data"
PORTABLE_CCS="$PORTABLE_DATA/.cc-switch"
PORTABLE_CLAUDE="$PORTABLE_DATA/.claude"
SYS_CCS="$HOME/.cc-switch"
SYS_CLAUDE="$HOME/.claude"
CCS_DB="$PORTABLE_CCS/cc-switch.db"

mkdir -p "$PORTABLE_CCS" "$PORTABLE_CLAUDE"

# 一次性迁移：把系统已有的数据复制到便携包
migrate_dir() {
    local src="$1" dst="$2"
    if [ -d "$src" ] && [ ! -L "$src" ]; then
        # src 是真目录（不是符号链接），且有内容 → 迁移
        if [ -n "$(ls -A "$src" 2>/dev/null)" ] && [ -z "$(ls -A "$dst" 2>/dev/null)" ]; then
            echo "  [migrate] 复制系统现有数据到便携包: $src → $dst"
            cp -a "$src/." "$dst/" 2>/dev/null
        fi
    fi
}
migrate_dir "$SYS_CCS" "$PORTABLE_CCS"
migrate_dir "$SYS_CLAUDE" "$PORTABLE_CLAUDE"

# 创建符号链接：~/.cc-switch → 便携包/data/.cc-switch
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
        # 真目录（迁移后应该已经空了）
        rmdir "$link" 2>/dev/null || rm -rf "$link" 2>/dev/null
    fi
    ln -s "$target" "$link" 2>/dev/null
}
ensure_symlink "$SYS_CCS" "$PORTABLE_CCS"
ensure_symlink "$SYS_CLAUDE" "$PORTABLE_CLAUDE"

# 退出时清理符号链接（只清符号链接，不动真目录）
cleanup() {
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
        # 无 python3 时退化到大小检查（不可靠）
        local size
        size=$(stat -f%z "$CCS_DB" 2>/dev/null || stat -c%s "$CCS_DB" 2>/dev/null || echo 0)
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
    "$BIN_DIR/cc-switch" &>/dev/null &
    CC_SWITCH_PID=$!

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
    if [ -z "$result" ]; then
        return 1
    fi
    export ANTHROPIC_BASE_URL=$(echo "$result" | head -1)
    export ANTHROPIC_AUTH_TOKEN=$(echo "$result" | tail -1)
    unset ANTHROPIC_API_KEY
    return 0
}

if read_config; then
    echo "  [ok] 配置已加载"
else
    echo "  [!] 无法从 DB 读取配置"
    exit 1
fi

# ═══════════════════════════════════════════
# 启动 Claude Code
# ═══════════════════════════════════════════
echo "  架构: $ARCH | 数据: 便携包内"
echo ""

"$BIN_DIR/claude" "$@"
