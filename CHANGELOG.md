# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added
- **多会话轮播**:存在多个不同状态时,菜单栏图标与悬浮灯按优先级轮流展示(每 2.5s;
  blocked/error 停留 2 倍);状态去重、只有一个状态或手动覆盖/演示时不轮播;
  菜单标题仍显示最高优先级

### Added
- **状态变化气泡**:任务进入 blocked/success/error 时在菜单栏图标下方弹出气泡,
  显示 agent + 会话名,4s 自动淡出;点击跳转到任务 App(opencode→OpenCode、cursor→Cursor);
  菜单可开关气泡并选停留时长;下拉菜单的会话行也可点击跳转
- **悬浮红绿灯**:透明无底、置顶、跨所有 Space/全屏的三灯组件;可拖动、
  右下角拖拽或滚轮缩放;`⌥`+滚轮或状态面板滑块调透明度;悬停出现「固定/隐藏」;
  **固定即点击穿透**(隐藏按钮,取消固定用菜单);可选**圆角外壳**;位置与大小按屏幕持久化
- ObjC 桥接 target `PrivateStatusItem`(私有 `NSStatusBar` 优先级 API,实验性)

### Added
- **切到窗口即确认**(菜单开关,默认开):把 success/error 会话所在窗口切到前台即视为已确认(置灰保留);
  用 AX 读焦点窗口标题**按项目文件夹精确匹配**(需辅助功能权限),未授权时退化为按 App 判断
- 已完成且在看的窗口:不再弹 success/error 气泡

### Changed
- **改用稳定签名**:`bundle.sh` 优先使用本机 codesigning 证书(Apple Development),
  替代 ad-hoc 签名,使 macOS TCC(辅助功能/自动化)授权在重建后不再失效
- 菜单新增「辅助功能:已授权 / 未授权」状态行(点击去授权)

### Changed
- 优先级调整为 `blocked > error > busy > working > thinking > success > idle`:
  有人在干活时显示黄灯,不再被常驻的 success 绿灯压住

### Changed
- **success 常驻**:完成态不再 25s 过期变灰,保持绿灯直到用户从气泡/菜单点击跳转「唤起」该会话
  (跳转时清除该 success/error 会话)

### Changed
- 菜单栏图标改为**单个玻璃圆点**(2x 渲染、径向渐变球 + 左上高光 + 柔光晕,按模式混色)
- 状态面板高度按内容自适应
- 「固定」即**点击穿透 + 锁位置/大小 + 隐藏按钮**;取消固定改用菜单「固定悬浮灯」
- 移除全部全局快捷键(仅保留菜单入口)
- `make install` 安装到 `/Applications`

### Added
- 气泡增强:问题文本展示、按状态分别开关、会话「中断」提示、多会话合并、
  出错反复出现时升级为 alarm(气泡 + 灯短暂切 alarm)
- opencode `question` 工具(等你选择)映射为 **blocked**,不再误显示为 working

### Changed
- 活动态(working/busy/thinking)与 blocked 改为**常驻**(不再按时间过期),长任务不会中途掉;
  新增**工具运行期间心跳**(每 3 分钟)与**20 分钟静默超时**:静默超时判定为中断,
  删除该会话(灯切 idle)并可弹「已中断」气泡

### Fixed
- 同一 App 下多个 success,切一个却全被确认变 idle:按 App 兜底会清掉该 App 下**所有**会话。
  现**仅当该 App 下只有 1 个待确认会话**才兜底;≥2 个必须精确匹配(读不到则不确认)。

### Fixed
- 悬浮灯 success 一闪而过:每轮 poll 的 `AppState.update` 把 `mode` 设回聚合(最高优先级),
  而 `applyDisplay` 提前返回未纠正 → 悬浮灯被按回 busy。现 `update` 不再设置 `mode`,
  由显示逻辑(轮播)独占
- 切到 success 窗口不确认:精确判定依赖 Automation/辅助功能权限,未授权时读不到 tab/窗口身份;
  现在**读不到就退化为按 App 确认**(仍在"前台发生切换"时才触发),授权后为精确到 tab/窗口

### Fixed
- success 出现后**秒消失**:「切到窗口即确认」把你**正在看的 tab** 当已确认 →
  改为**仅在前台发生切换**时才确认(你已在该窗口不算);并移除"已在看就不弹气泡"的即时确认

### Fixed
- **转发队列卡死**:串行队列被一个卡住的子进程拖垮,之后所有事件不再写入(表现为
  权限弹窗却显示 busy、success 丢失)。改为**并发转发 + 单进程 8s 超时 kill**,
  顺序仍由 `seq` 保证
- **权限挂起保护**:`permission.asked` 后被 busy/tool.before 覆盖回 working;
  现挂起期间抑制 busy/tool 事件,blocked 保持到 `permission.replied`
- **轮播改按状态名计时**:之前用下标,列表顺序/长度一变就把 success 顶掉;现只有
  当前状态消失或计时到才切换,每个状态拿满时长(2.5s,blocked/error 5s);
  新出现的 blocked/error 会立即打断

### Fixed
- 跳转目标改为**按会话宿主**:插件上报 `host`(iTerm/VS Code/OpenCode 桌面)与 `ref`,
  修复"iTerm 里的 opencode 被跳到 VS Code";iTerm 用 `ref` 精确选中 tab,桌面版走深链
- 事件转发**串行化** + `safeStringify` 加固 + 子进程 stderr 全量记录,
  修复并发 hook 偶发丢事件导致的**卡 working**

### Fixed
- `question` 工具也会触发 `tool.execute.before`,导致等待期间被写成 **busy**;
  现在 `question` 的 tool.before/after 不转发 busy/working(等待一律 blocked,
  回答后由 question.replied 回到 working)

### Fixed
- 事件**乱序写入**导致状态卡住(如 `idle` 先落、并发进程的 `busy` 后落,把会话写成 working
  且常驻):插件为每个事件带单调 `seq`,`store.write_event` 忽略比现有记录更旧的事件

### Fixed
- 跳转在**主线程**同步执行 `code`/`sqlite3`,慢时会卡死菜单栏(可能被系统判无响应终止);
  改为**后台线程**执行,不再阻塞 UI
- 启动/退出写 `~/.ai-status-light/app.log`,便于区分「正常退出」与「被终止/强退」

### Fixed
- opencode `busy` 从不触发:`tool.execute.before/after` 是插件 **hook**(非 event),
  现按 hook 转发为 busy/working
- opencode 新增 `thinking`:由 `message.part.updated` 的 reasoning 部分派生
- `working/busy/thinking` 长时间无事件会被 90s TTL 清掉(灯"变没");
  活动态 TTL 提到 1800s,`blocked` 也提到 1800s

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
