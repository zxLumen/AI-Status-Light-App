# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/),
版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Added
- **手机 / 手表推送(Bark)**:任务进入 需要你 / 完成 / 出错 时推到 iPhone,
  再由 iOS 通知镜像到手表。新增 `Push.swift`(`PushConfig` + `PushNotifier`):
  - 配置 `~/.ai-status-light/push.json`(密钥只在此,不进仓库;日志只记主机名)
  - 分状态开关;需要你用 `timeSensitive`,完成/出错用 `active`
  - 每会话每状态冷却去重(默认 60s)、`group`=会话 id、`badge`=待处理数
  - 菜单「手机推送」:启用 / 测试推送 / 分状态开关 / 设置 Bark…(输入 key 自动发测试)
- 跃变检测抽为 `stateTransitions()`,气泡与推送各用其开关独立消费

### Added
- 悬浮灯**悬停变透明**:光标移到红绿灯上时淡出到设定值(默认 15%,菜单可切 0%/15%/30%),
  移开即恢复;`FloatingSettings.effectiveOpacity` 计算显示不透明度,0.12s 缓动
- **固定(点击穿透)状态也能淡化**:固定时面板 `ignoresMouseEvents` 收不到鼠标事件,
  改用全局 `.mouseMoved` 监听 + 面板 frame 包含判断驱动悬停
- 菜单新增「悬停变透明」开关与「悬停透明度」子菜单

### Added
- 气泡支持**滑动关闭**(不确认):触控板**双指左右滑动**累计超过 60pt 或鼠标拖拽超过 80pt
  即滑出屏幕并关闭,会话仍为待确认状态、灯继续显示;滑动/悬停时暂停 8s 自动消失定时器
  (悬停不消失),轻点仍是跳转+确认

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
- **iTerm 里切到 opencode 的 tab 不清除 success**:插件上报的 `ITERM_SESSION_ID` 是
  `w0t0p0:<UUID>`,而 AppleScript 的 `unique id` 是裸 `<UUID>`,全等比较永远失败。
  新增 `ITermFocus.normalize`(取尾部 UUID)后比较;`focus()` 同样按归一化匹配并
  **校验命中**(AppleScript 返回 "ok"),修掉"跳转没真选中 tab 却报成功"

### Fixed
- 菜单列表因误切窗口而**跳动**:`markAcknowledged` 原会把 `ts`/`seq` 刷新为"现在",
  而列表按 `ts` 倒序 → 被自动确认的会话跳到了最上面。现改为只写 `ack=true`,
  **不再改动 `ts`/`seq`**;排序抽为 `StateStore.menuOrder`,**活跃会话(未确认且在 TTL 内)在前、
  已确认/过期沉底**,组内按活动时间倒序

### Fixed
- 滑动松手后**还要停约 1 秒才飞走**:触控板抬指后的**惯性 `scrollWheel` 事件**持续到达,
  每次都重置 0.15s 静默定时器。改为**累计一旦 ≥40pt 立即飞出**(不等惯性),
  并用 `phase/momentumPhase == .ended` 判断手势真正结束;静默计时器仅作无相位设备的兜底

### Fixed
- 滑动**滑一半卡住**:`hitTest` 只认随 `offset` 移动的卡片矩形,卡片滑离静止的光标后
  panel 收不到 `scrollWheel`,手势中断。改为手势期间 `capturing` 覆盖整个 bounds,
  结束后恢复仅卡片可点;`followLimit 45→90`、`margin 60→140`,跟手更明显
- 滑动语义改为**滑动即关闭**(累计 ≥20pt 即甩出,只对 <20pt 抖动回弹)
- 手势后**悬停不再起作用**:新增 `hoverMuted`,滑动/拖拽一开始即置位,
  回弹后也恢复计时,修复"回弹后赖着不走"

### Fixed
- 气泡滑动**不跟手、甩出掉帧**:改为 `BubbleModel`(ObservableObject)驱动 SwiftUI
  `offset/opacity`,滑动按 0.45 比例实时跟手(限 ±45pt),甩出走 GPU 动画,
  不再动画窗口 frame;面板加 60pt 透明边距并限制命中区域(边距不拦截点击)
- `hovering/dragging` 在显示时不重置,导致第一次气泡后小幅滑动不再恢复自动消失
- 双指竖直滚动被吞掉:非水平滚动交还 `super.scrollWheel`

### Fixed
- 同一个项目目录里的多个 success 在切换窗口时**被一起清空**:窗口标题只含文件夹名,
  同目录的多个会话会全部"精确匹配"。现改为**每次切换最多确认一个**(取最新的那个)

### Fixed
- 多会话时 success/error **不再出气泡**:气泡原来按"聚合模式变化"触发,只要有另一个会话处于
  更高优先级(busy/working)聚合就永远不是 success。现改为**按每个会话的状态变化**触发
  (仍受状态开关、3s 冷却、alarm 升级、blocked 合并约束)

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
