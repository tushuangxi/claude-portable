# Claude Code Portable + CC Switch

便携版 Claude Code + CC Switch，零安装，即插即用。

## 快速开始

### macOS
```bash
./ClaudePortable.command
```

### Linux
```bash
chmod +x ClaudePortable.sh
./ClaudePortable.sh
```

### Windows
双击 `ClaudePortable.bat`

## 功能

- **Claude Code** — Anthropic AI 编程助手 CLI
- **CC Switch** — API 供应商切换工具，图形界面管理多个 Provider
- **便携数据** — 所有配置/会话存于包内 `data/`，可整包带走
- **设备绑定** — 首次运行绑定到当前设备，防止随意复制（`--unlock` 解绑）

## 目录结构

```
claude-portable/
├── bin/                    # 平台二进制文件
│   ├── macos-arm64/        # Apple Silicon Mac
│   ├── macos-x64/          # Intel Mac
│   ├── linux-x64/          # Linux x86_64
│   └── windows-x64/        # Windows 64-bit (含 sqlite3.exe)
├── config/                 # 默认配置模板
│   ├── claude/             # Claude Code 配置
│   └── ccswitch/           # CC Switch 默认 Provider 模板
├── lib/                    # 配置读取 / 设备绑定辅助脚本
├── data/                   # 运行时数据（会话、cc-switch.db、锁）
├── ClaudePortable.command  # macOS 启动脚本
├── ClaudePortable.sh       # Linux 启动脚本
└── ClaudePortable.bat      # Windows 启动脚本
```

## 配置 API

首次运行会自动打开 CC Switch 图形界面。添加一个 Provider 并保存即可，
配置会写入 `data/.cc-switch/cc-switch.db`（SQLite）。启动脚本从该 DB
读取 `ANTHROPIC_BASE_URL` 和 `ANTHROPIC_AUTH_TOKEN` 注入 Claude Code。

> 注：`config/ccswitch/providers.json` 仅是首次运行的默认模板，实际生效
> 的配置以 cc-switch 写入的 `data/.cc-switch/cc-switch.db` 为准。

## 设备绑定与解绑

便携包首次成功运行后会绑定到当前设备/位置。若需移动到其他设备，先解绑：

```bash
# macOS
./ClaudePortable.command --unlock
# Linux
./ClaudePortable.sh --unlock
# Windows
ClaudePortable.bat --unlock
```

## 环境变量（由启动脚本自动注入）

| 变量 | 说明 |
|------|------|
| `ANTHROPIC_AUTH_TOKEN` | API Key（从 cc-switch.db 读取） |
| `ANTHROPIC_BASE_URL` | 自定义 API 端点（从 cc-switch.db 读取） |

## 更新

替换 `bin/` 目录下对应平台的二进制文件即可。
