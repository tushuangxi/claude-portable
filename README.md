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
- **CC Switch** — API 代理切换工具，支持第三方 API
- **预配置** — 小米 MiMo API 已内置，开箱即用

## 目录结构

```
claude-portable/
├── bin/                    # 平台二进制文件
│   ├── macos-arm64/        # Apple Silicon Mac
│   ├── macos-x64/          # Intel Mac
│   ├── linux-x64/          # Linux x86_64
│   └── windows-x64/        # Windows 64-bit
├── config/                 # 配置文件
│   ├── claude/             # Claude Code 配置
│   └── ccswitch/           # CC Switch Provider 配置
├── data/                   # 会话数据
├── .claude/                # Claude 项目配置
├── ClaudePortable.command  # macOS 启动脚本
├── ClaudePortable.sh       # Linux 启动脚本
└── ClaudePortable.bat      # Windows 启动脚本
```

## 添加 API Provider

编辑 `config/ccswitch/providers.json`，添加你的 API 配置。

## 环境变量

| 变量 | 说明 |
|------|------|
| `ANTHROPIC_API_KEY` | Anthropic API Key |
| `ANTHROPIC_BASE_URL` | 自定义 API 端点 |
| `CC_SWITCH_PORT` | CC Switch 代理端口 (默认 18080) |

## 更新

替换 `bin/` 目录下对应平台的二进制文件即可。
