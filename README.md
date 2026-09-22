# AI Status Light

<img src="docs/images/icon-1024.png" width="120" align="right" alt="App 图标">

一盏住在 macOS **菜单栏**的红绿灯:实时映射你的 AI 编程 agent 正在干什么——**在干活**、**干完了**、还是**在等你**。不用再盯着终端。

支持 **Claude Code**、**Cursor**、**Codex**、**opencode** 四个 agent。这是"软件灯"版本:菜单栏图标本身就是那盏灯,不需要任何硬件。

```
  菜单栏单灯   ◀──  状态仓库(~/.ai-status-light)  ◀──  Agent hooks
  (红/黄/绿)        sessions / names / override         (桥接写入)
```

## 特性

- **菜单栏单灯图标**(玻璃圆点:径向渐变球 + 高光 + 柔光晕,按模式混色),按当前状态呼吸 / 闪烁 / 交替 / 循环(与硬件灯效一致)
- **直接读取**主机桥接的状态仓库,进程内聚合(优先级 + TTL + 手动覆盖),不依赖后台服务
- 点击图标弹出菜单:当前状态、活跃会话(**点击跳转到对应 App**)、状态面板、演示、清空、悬浮灯开关、气泡开关、开机自启、退出
- **多会话轮播**:同时有多个不同状态的会话时,图标与悬浮灯按**优先级轮流展示**各状态
  (blocked/error 停留更久);只有一个状态时静止
- **状态变化气泡**:任务进入 需要你 / 完成 / 出错 时,菜单栏图标下方弹出气泡;**点击跳转到任务 App**
- **悬浮红绿灯**(菜单开关):透明无底、置顶、跨所有 Space/全屏;可拖动、可缩放、可固定;**鼠标悬停时自动变透明**
- **手机 / 手表推送**(菜单开关):需要你 / 完成 / 出错 时经 **Bark** 推到 iPhone,并由 iOS 通知镜像到智能手表
- 图标位置用 `autosaveName` 持久化(`⌘` 拖拽后记住)
- 无 Dock 图标(`LSUIElement`),纯菜单栏常驻

## 截图

菜单栏下拉会显示当前状态与各会话,点会话行可跳转到对应窗口;悬浮灯与气泡随时反映同一状态。

| working | success |
|---|---|
| <img src="docs/images/demo-menu-working.gif" width="330" alt="菜单 · working"> | <img src="docs/images/menu-success.jpg" width="330" alt="菜单 · success"> |

| idle | needs you(等你选择) |
|---|---|
| <img src="docs/images/menu-idle.jpg" width="330" alt="菜单 · idle"> | <img src="docs/images/demo-menu-blocked.gif" width="330" alt="菜单 · needs you"> |

## 悬浮红绿灯

一个透明、置顶的三灯组件,窗口切来切去都在最上层。

<img src="docs/images/floating-shell.jpg" width="220" alt="悬浮红绿灯 · 圆角外壳">

- **显示/隐藏**:菜单「显示悬浮灯」;启动默认显示
- **移动**:直接拖拽
- **缩放**:拖右下角,或在组件上滚轮
- **透明度**:`⌥` + 滚轮,或菜单「状态面板」里的滑块
- **悬停**出现两个小按钮:**📌 固定**、**✕ 隐藏**
- **固定 = 点击穿透**:点 📌 后锁住位置/大小、隐藏按钮并开始穿透(点击落到下方窗口);
  取消固定:菜单栏菜单 →「固定悬浮灯」
- **圆角外壳**:菜单「悬浮圆角外壳」开关(深色圆角底 + 细边,更像红绿灯盒子)
- **显示位置**:菜单「悬浮灯显示在 → 仅主屏 / 所有屏幕」
- 位置与大小会被记住(按屏幕分别持久化)

## 状态变化气泡

任务进入**关键状态**时,菜单栏图标正下方弹出一个气泡:

<img src="docs/images/demo-bubble-question.gif" width="320" alt="等你选择(needs you)">
<img src="docs/images/bubble-success.jpg" width="320" alt="完成(success)">

- 显示 **状态 + agent + 会话名**;若是工具在问你问题(如 opencode 的 `question`),还会显示**问题文本**
- 停留 **8s** 后自动淡出(菜单「气泡停留」可选 2/4/8s)
- **点击气泡 → 跳到对应任务窗口**
  - opencode **按会话宿主**跳转(插件上报 `host`/`ref`,需重启 opencode 采集):
    - **iTerm** → 用 `ref` 经 AppleScript **选中对应 tab**(首次弹"自动化"授权)
    - **VS Code** → `code <项目目录>` 聚焦对应窗口(无需权限)
    - **OpenCode 桌面版** → `opencode://open-project?directory=…` 打开/聚焦项目窗口
    - 其它终端 → 激活该 App
  - cursor → Cursor;claude/codex 暂无映射(点击打开状态面板)
  - 项目目录优先取桥接采集,缺失时只读查询 opencode 数据库
- **提示状态**可分别开关:需要你 / 完成 / 出错 / **中断**
  - 「中断」= 活动会话**超过 20 分钟无任何事件**(工具运行期间每 3 分钟有心跳续期)→ 判为中断,灯切回 idle;默认关闭
  - 多个任务同时「需要你」时,气泡合并显示「N 个任务需要你」
  - 出错**反复出现**(120s 内 ≥2 次)会**升级为 alarm**:气泡变 alarm 样式,并把灯短暂切到 alarm(30s)
- 菜单「状态变化气泡」为总开关;气泡消失后,也可从**下拉菜单点击会话行**跳转

## 手机 / 手表推送

任务进入 **需要你 / 完成 / 出错** 时,把通知推到 iPhone,再由 iOS 通知镜像到智能手表。

```
macOS App ──HTTPS──▶ api.day.app ──▶ iPhone 通知 ──蓝牙(ANCS)──▶ 手表
```

用 **Bark**(iPhone 免费 App,开源,可自建):

1. iPhone 安装 **Bark**,打开 → 复制 key(其 URL 尾部那串)
2. 菜单 **手机推送 → 设置 Bark…** → 粘贴完整地址 `https://api.day.app/<KEY>` 或只填 `<KEY>` → 保存
3. 保存后会自动发一条**测试推送**;手机收到即成功(手表需在 Garmin/其它手表 App 里允许转发该 App 的通知)

细节:

- **分状态开关**:需要你 / 完成 / 出错(菜单「手机推送」)
- **提醒强度**:需要你用 `timeSensitive`(可穿透专注模式,但**不绕过静音**);完成/出错用 `active`
  - 想更强:在 iOS「设置 → 通知 → Bark → 关键警报」开启后,把 `~/.ai-status-light/push.json` 的 `level` 改为 `critical`(可绕过静音/勿扰)
  - `timeSensitive` **仍会进通知中心并带角标**,只是"何时打扰你"更强制
- **去重**:同一会话同一状态 `cooldown` 秒内只推一次(默认 60s),防止 error 升级刷屏
- **角标** = 待处理的 需要你/出错 会话数;**分组** = 会话 id(iOS 上同会话通知折叠)
- **通知图标**(iOS 15+):默认用本项目的图标
  (`https://cdn.jsdelivr.net/gh/zxLumen/AI-Status-Light-App@main/docs/images/icon-256.png`)
  - 换图标:改 `~/.ai-status-light/push.json` 的 `icon`(任意可公网访问的图片 URL)
  - 关掉(用 Bark 自带图标):把 `icon` 设为 `""`
  - 国内若 CDN 不通,可把 `docs/images/icon-256.png` 传到任意可达图床,再填其 URL
- 配置存在 `~/.ai-status-light/push.json`(含密钥,**不在仓库内**);日志只记主机名不记 key
- 手表靠 iOS 通知镜像:**通知必须真正进入 iPhone 通知中心**才会转发;手表自身的勿扰/睡眠模式仍会静默

## 构建与运行

需要 macOS 13+ 与 Xcode Command Line Tools(Swift 5.9+)。

```bash
make build     # swift build -c release
make icon      # 重新生成 App 图标(Resources/AppIcon.icns + docs/images/icon-1024.png)
make bundle    # 组装 "build/AI Status Light.app"(稳定签名,回退 ad-hoc)
make run       # 构建并打开 App
make install   # 构建并安装到 /Applications 后打开(推荐)
```

装到 `/Applications` 后,它才会出现在 **Launchpad / Spotlight**,菜单里的"开机自启"也才可靠。

## 菜单栏位置(刘海机型必读)

带刘海的 MacBook 上,状态图标只排在**刘海右侧**。当右侧槽位被占满时,新图标会被挤到刘海下方而**不可见**——这不是 App 的问题,而是 macOS 的限制。

- 本 App 用 `autosaveName` 记住你 `⌘` 拖拽后的位置。
- 正解:**用 [Ice](https://github.com/jordanbaird/Ice) 等菜单栏工具收纳几个图标腾出空间**,再把「AI Status Light」拖到常显区/最右。
  - `brew install --cask jordanbaird-ice`,首次启动授予**辅助功能**权限,然后把它拖进 Visible 区。
- 实在看不到图标时:从菜单打开「状态面板」。
- 备注:代码里的 `PrivateStatusItem`(私有优先级 API)实测在 macOS 15 上不可靠(会把图标移到屏幕外),默认不启用,仅供实验(`AISTATUS_PRIVATE=1`)。

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

| 状态 | 菜单栏单灯 |
|---|---|
| idle | 绿灯慢呼吸(很暗) |
| thinking | 黄灯慢呼吸(2.2s) |
| working | 黄灯呼吸(1.2s) |
| busy | 黄灯快闪 |
| success | 绿灯常亮 |
| error | 红灯快闪 |
| blocked(需要你) | 红/黄交替 |
| traffic / demo | 三色循环 / 轮播 |

优先级:`blocked > error > busy > working > thinking > success > idle`
(即:**有人在干活时显示黄灯**;全部完成才显示绿灯;error/blocked 优先)。

## 状态来源

- 状态仓库:`~/.ai-status-light/`(可用 `AISTATUS_HOME` 覆盖)
  - `sessions/*.json` 每个会话的最近状态
  - `names.json` 会话名(opencode 标题)
  - `override.json` 手动覆盖
- 契约:`aistatus/states.json`(优先级 / TTL / 颜色 / 标签),构建时复制进 App 的 `Contents/Resources`;运行时会优先读 `AISTATUS_CONTRACT` 或仓库内的同名文件,便于开发。

## 目录结构

```
Package.swift                 SwiftPM 工程
Sources/AIStatusLight/        App 源码(菜单栏 / 聚合 / 灯效 / 图标 / 面板 / 悬浮窗)
Sources/PrivateStatusItem/    ObjC 小桥接:高优先级放置状态项(私有 API,带兜底)
Resources/Info.plist          打包用 Info.plist
Resources/AppIcon.icns        App 图标(由 scripts/make-icon.swift 生成)
scripts/bundle.sh             组装 .app + 稳定签名(回退 ad-hoc)
scripts/make-icon.swift       矢量绘制 App 图标并打包 .icns(含推送用 icon-256.png)
aistatus/                     主机桥接(Python):hooks、状态仓库、聚合
```

## 备注

- **success 常驻**:任务完成后绿灯会一直亮,直到**被「唤起」**才不再绿灯(会话**仍保留在菜单**里,置灰):
  - 从**气泡/菜单点击跳转**,或
  - **直接切到该会话窗口**(菜单「切到窗口即确认」,默认开;精确匹配窗口标题需**辅助功能**权限)
  - 若此时**别的会话还在 working/busy**,灯显示黄灯(干活优先)

- 菜单栏图标彩色需 `isTemplate=false`;深/浅色模式下对比度略有差异。
- **别在旧的项目副本里跑 `install-hooks`**:不要复制项目后沿用旧的 `.venv`
  (console script 的 shebang 会指向旧路径,插件里写死的 Python 也会指错,
  表现为 hook 用旧代码、`question` 等新映射失效)。若已复制,请重建 venv,
  或用 `python -m aistatus install-hooks` 安装以写入正确的解释器路径。
- 会话名取不到时回退显示 agent 名,不显示裸 session id。
