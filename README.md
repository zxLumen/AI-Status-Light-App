# AI Status Light

一盏住在 macOS **菜单栏**的红绿灯:实时映射你的 AI 编程 agent 正在干什么——**在干活**、**干完了**、还是**在等你**。不用再盯着终端。

支持 **Claude Code**、**Cursor**、**Codex**、**opencode** 四个 agent。这是"软件灯"版本:菜单栏图标本身就是那盏灯,不需要任何硬件。

```
  菜单栏三灯   ◀──  状态仓库(~/.ai-status-light)  ◀──  Agent hooks
  (红/黄/绿)        sessions / names / override         (桥接写入)
```

## 特性

- **菜单栏三灯微缩图标**,按当前状态呼吸 / 闪烁 / 交替 / 循环(与硬件灯效一致)
- **直接读取**主机桥接的状态仓库,进程内聚合(优先级 + TTL + 手动覆盖),不依赖后台服务
- 点击图标弹出菜单:当前状态、活跃会话(会话名 + 彩色圆点)、演示、清空、打开控制面板、开机自启、退出
- 无 Dock 图标(`LSUIElement`),纯菜单栏常驻

## 构建与运行

需要 macOS 13+ 与 Xcode Command Line Tools(Swift 5.9+)。

```bash
make build     # swift build -c release
make bundle    # 组装 "build/AI Status Light.app"(ad-hoc 签名)
make run       # 构建并打开 App
```

或直接 `open "build/AI Status Light.app"`。

## 接入你的 agent(一次性)

菜单栏图标本身只负责"显示";状态由主机桥接的 hooks 写入仓库。安装桥接并接入 agent:

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
aistatus install-hooks --agent all --dry-run   # 先预览
aistatus install-hooks --agent all
```

| Agent | 接入文件 |
|---|---|
| Claude Code | `~/.claude/settings.json` |
| Cursor | `~/.cursor/hooks.json` |
| Codex | `~/.codex/config.toml`(`notify`) |
| opencode | `~/.config/opencode/plugins/aistatus.js`(插件;装完需重启 opencode) |

> opencode 只自动加载 `{plugin,plugins}/*.{ts,js}` —— 扩展名必须是 `.js`/`.ts`。
> 装完 opencode 后需**重启**才会生效;日志见 `~/.ai-status-light/opencode.log`。

## 灯效映射

| 状态 | 菜单栏三灯 |
|---|---|
| idle | 绿灯慢呼吸(很暗) |
| thinking | 黄灯慢呼吸(2.2s) |
| working | 黄灯呼吸(1.2s) |
| busy | 黄灯快闪 |
| success | 绿灯常亮 |
| error | 红灯快闪 |
| blocked(需要你) | 红/黄交替 |
| traffic / demo | 三色循环 / 轮播 |

优先级:`blocked > error > success > busy > working > thinking > idle`。

## 状态来源

- 状态仓库:`~/.ai-status-light/`(可用 `AISTATUS_HOME` 覆盖)
  - `sessions/*.json` 每个会话的最近状态
  - `names.json` 会话名(opencode 标题)
  - `override.json` 手动覆盖
- 契约:`aistatus/states.json`(优先级 / TTL / 颜色 / 标签),构建时复制进 App 的 `Contents/Resources`;运行时会优先读 `AISTATUS_CONTRACT` 或仓库内的同名文件,便于开发。

## 控制面板(可选)

桥接自带网页控制面板,可在菜单里一键打开:

```bash
.venv/bin/aistatus serve --open        # http://127.0.0.1:8377
```

## 目录结构

```
Package.swift                 SwiftPM 工程
Sources/AIStatusLight/        App 源码(菜单栏 / 聚合 / 灯效 / 图标)
Resources/Info.plist          打包用 Info.plist
scripts/bundle.sh             组装 .app + ad-hoc 签名
aistatus/                     主机桥接(Python):hooks、状态仓库、聚合、网页面板
web/                          网页控制面板页面
```

## 备注

- 菜单栏图标彩色需 `isTemplate=false`;深/浅色模式下对比度略有差异。
- 会话名取不到时回退显示 agent 名,不显示裸 session id。
