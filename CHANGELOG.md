# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added
- **状态变化气泡**:任务进入 blocked/success/error 时在菜单栏图标下方弹出气泡,
  显示 agent + 会话名,4s 自动淡出;点击跳转到任务 App(opencode→OpenCode、cursor→Cursor);
  菜单可开关气泡并选停留时长;下拉菜单的会话行也可点击跳转
- **悬浮红绿灯**:透明无底、置顶、跨所有 Space/全屏的三灯组件;可拖动、
  右下角拖拽或滚轮缩放;`⌥`+滚轮或状态面板滑块调透明度;悬停出现「固定/隐藏」;
  **固定即点击穿透**(隐藏按钮,取消固定用菜单);可选**圆角外壳**;位置与大小按屏幕持久化
- ObjC 桥接 target `PrivateStatusItem`(私有 `NSStatusBar` 优先级 API,实验性)

### Changed
- 菜单栏图标改为**单个玻璃圆点**(2x 渲染、径向渐变球 + 左上高光 + 柔光晕,按模式混色)
- 状态面板高度按内容自适应
- 「固定」即**点击穿透 + 锁位置/大小 + 隐藏按钮**;取消固定改用菜单「固定悬浮灯」
- 移除全部全局快捷键(仅保留菜单入口)
- `make install` 安装到 `/Applications`

### Fixed
- 跳转改为按项目目录精准聚焦:opencode 用 VS Code CLI(`code <目录>`)定位对应窗口,
  目录优先取桥接采集、缺失时只读查询 opencode 数据库;辅助功能标题匹配作为二级兜底
- 状态面板高度写死导致透明度滑块被裁切

### Removed
- 网页控制面板:`webui.py`、`serve` 命令、`web/` 页面及菜单/按钮入口


## [0.1.0] - 2026-09-21

macOS 菜单栏应用首版:把 AI 状态灯做成菜单栏里的一个灯。

### Added
- 原生 Swift / AppKit 菜单栏 App(`LSUIElement`,无 Dock 图标)
- 菜单栏单灯图标,按状态呼吸 / 闪烁 / 交替 / 循环
- 直接读取主机桥接状态仓库(`~/.ai-status-light`),进程内聚合(优先级 + TTL + 手动覆盖)
- 菜单:当前状态、活跃会话(会话名 + 彩色圆点)、演示、清空、打开控制面板、开机自启(`SMAppService`)、退出
- SwiftPM 工程 + `scripts/bundle.sh` 组装可运行 `.app`(ad-hoc 签名)
- 保留主机桥接(`aistatus/`,Python)与网页控制面板(`web/`)用于接入 agent

### Notes
- 状态契约 `aistatus/states.json` 在打包时复制进 App,可运行期覆盖
- 不依赖后台服务即可显示;agent 接入仍由桥接的 hooks 写入仓库
