# dsh-mac-launcher

[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web GUI 的**纯原生 macOS 启动器**。

用一个 Swift + WKWebView 的单进程应用承载它的 Web GUI：点 Dock 图标即用，
**不依赖 Google Chrome，也不需要任何系统自动化权限。**

```
点 Dock 图标
   └─ DSH.app 自己：探端口 → 必要时拉起 dsh web → 认证 → WKWebView 开窗
                    ↑ 全在一个进程里完成，没有脚本、没有标志文件、没有 osascript
```

## 前置要求

- macOS 14+（`LSMinimumSystemVersion`）
- Xcode 命令行工具：`xcode-select --install`（编译需要）
- **[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 已安装** ——
  本应用只是它的 GUI 宿主，不含 DSH 本身。装好后 `dsh --version` 应能正常输出；
  若不在默认位置，用 `DSH_BIN` 指定

用 nvm 管理 node 时**不需要**手动指定 `DSH_BIN`：启动器按 `~/.nvm/alias/default`
找对应版本的 `dsh`（`nvm alias default v26` 就跟着切到 v26）；没有该别名时取
nvm 里语义版本最高的那个。所以升级 node 后只要在新版本里装了 dsh（`npm i -g
@deepseek-ai/dsh`），重启启动器即可，不用改配置。`dsh` 的入口是
`#!/usr/bin/env node` 脚本，启动器同时会把该版本目录放到子进程 `PATH` 首位，
保证"跑 dsh 的 node"与"被选中的 dsh"是同一个版本 —— 只改一半就会出现
"加载 v26 的 dsh 模块、却用 v24 的 node 执行"的错配。

## 安装

```sh
cd dsh-mac-launcher
./build.sh                    # Release 构建：编译 + 生成图标 + 组装 build/DSH.app
cp -R "build/DSH.app" /Applications/
```

`build.sh` 默认产出 **Release** 版本（`-O -wmo` 全模块优化 + 剥离符号，可执行文件约 268 KB）。
需要带符号调试时用 `BUILD_TYPE=debug ./build.sh`（`-Onone -g`，不剥离）。

然后把 `/Applications/DSH.app` 拖到 Dock。首次点击会自己起服务并开窗。

> 若端口上已经有 `dsh web` 在跑（比如你之前用别的方式启动过），本启动器会直接复用，
> 并尽量从历史日志里取回认证地址，不会去重启它。

自检（不做任何动作，只打印本次决策）：

```sh
"/Applications/DSH.app/Contents/MacOS/DSHLauncher" --print-decision
```

另有两条自省路径，用于验证无法用脚本点击的菜单动作
（菜单点击在 macOS 上需要辅助功能权限，脚本发不了按键）：

```sh
DSHLauncher --self-test-restart   # 启动后自动触发一次「重启」，验证整条链路
DSHLauncher --self-test-close     # 关掉窗口，验证「关窗不退出应用、也不停服务」
```

## 行为

**服务**
- 端口已有监听 → 复用，**绝不重启**
- 端口空闲 → 拉起 `dsh web --port <端口> --no-open`，子进程输出直接写 `service-raw.log`，启动器读它的增量解析认证 URL
- 取到的认证 URL 缓存在 `~/Library/Logs/DSH/auth-url`（权限 `0600`）

**认证**（这一版的核心简化）
- 日常启动**裸加载根地址**，让持久 cookie 生效 —— 服务端重启也不影响
  （DSH 的签名密钥是持久化凭据，cookie 不绑定进程级 launch token）
- cookie 失效时才用带 token 的地址补一次认证。token 优先取「原始输出日志里本次启动新增的那条」
  （一定是当前进程的）；本启动器启动的服务会重启一次拿新 token
- **别人启动的服务**（终端里手动跑的、旧启动器留下的）：只尝试从日志恢复认证地址，
  **找不到也绝不重启它** —— 那会打断正在使用它的会话

**窗口**
- 默认占满屏幕可用区域；`DSH_WINDOW_MODE=custom` 时用配置尺寸，并记住你调整过的大小
- 页面缩放：`⌘+` / `⌘-` 每档 10%、`⌘0` 回到 100%（菜单「显示」）；调过的值会被记住
- **关窗口不退出应用**：服务与菜单栏图标继续在，点 Dock 图标窗口回来
- 外链交给系统默认浏览器；下载走"下载"文件夹
- 右键菜单是精简版（剪切/拷贝/粘贴/刷新/回到主页），没有浏览器味的"检查元素"

**菜单栏**（与应用同进程，图标是黑色鲸鱼模板图标，深浅色菜单栏自动适配）
- 左键 → 菜单：状态行 · 打开（⌘O）· 刷新（⌘R）· 重启（⇧⌘R）· 退出（⌘Q）
- `重启` **无条件可用**：它会把端口上的服务停掉再重新拉起，**不管那个服务是不是本启动器
  启动的**（不是的话按端口反查监听者，SIGTERM → 3 秒宽限 → SIGKILL 强停，日志里会写明）。
  这会打断正在使用该服务的会话 —— 这正是它与下面「退出」的区别
- `退出` = 关窗口 + 停服务 + 撤图标。只停"本启动器启动的服务"；
  别人的服务会保留（日志里会写明）
- 菜单首行会标明服务归属（`运行中 · 端口 3080（外部启动）`）

## 配置

环境变量（也可写在 `~/.dsh/mac-launcher.yaml`，格式 `KEY: value`）：

| 变量 | 默认 | 说明 |
|---|---|---|
| `DSH_WEB_PORT` | `3080` | 服务端口 |
| `DSH_BIN` | 自动探测 | `dsh` 可执行文件路径；留空时跟随 `~/.nvm/alias/default` |
| `DSH_WORKDIR` | `~` | `dsh web` 的工作目录（决定 GUI 会话的起始目录） |
| `DSH_WINDOW_MODE` | `maximized` | `maximized` 占满屏幕 \| `custom` |
| `DSH_WINDOW_WIDTH` / `HEIGHT` | `1180` / `800` | 仅 `custom` 模式 |
| `DSH_REMEMBER_WINDOW_SIZE` | `1` | `custom` 模式下记住窗口大小 |
| `DSH_IMMERSIVE_WINDOW` | `0` | `1` = 隐藏标题栏的沉浸式窗口 |
| `DSH_PAGE_ZOOM` | `1.0` | 页面缩放（Chrome 那种整体缩放）；用户按 ⌘+ / ⌘- 调过的值会被记住并优先 |
| `DSH_TRAY` | `1` | `0` = 不显示菜单栏图标 |
| `DSH_OPEN_WINDOW` | `1` | `0` = 启动时不自动开窗 |
| `DSH_LOG_DIR` | `~/Library/Logs/DSH` | 日志目录 |
| `DSH_SERVICE_TIMEOUT` | `60` | 等端口就绪的上限（秒） |
| `DSH_TOKEN_TIMEOUT` | `20` | 等认证 URL 的上限（秒） |

命令行里未被本启动器识别的参数，会原样转给 `dsh web`。

## 日志

都在 `~/Library/Logs/DSH/`（不再把运行期文件写进源码目录）：

| 文件 | 内容 |
|---|---|
| `launcher.log` | 启动器决策与动作，排错先看这里 |
| `service.log` | `dsh web` 的输出（认证 URL 已脱敏），**可以放心外发** |
| `service-raw.log` | `dsh web` 的原始输出，权限 `0600`；启动器增量读它解析认证 URL。**里面可能有明文 token，不要外发** |
| `auth-url` | 带 token 的认证地址，权限 `0600`，**本机凭据不要外传** |

目录在应用启动时即建立，所以还没有任何日志时点错误面板的「打开日志」也能打开它。

`service-raw.log` 是这两份日志的中转：子进程的 stdout/stderr 以追加方式（`O_APPEND`）直接写它，
启动器按节奏读增量 —— 启动阶段 0.3 秒一次（尽快拿到认证 URL），运行期 2 秒一次 —— 一边解析
认证 URL，一边把**脱敏后**的内容转发进 `service.log`。

> **别把它改回 `Pipe` + `readabilityHandler`**（1.0.3 之前的写法）：管道对端一旦消失，
> 那两个 `com.apple.NSFileHandle.fd_monitoring` 线程会在 `availableData` 上空转，
> 实测各烧满一个核、合计约 200% CPU，而且日志里不留任何痕迹。普通文件的增量读不存在这种形态。

## 排错

**每点一次 Dock 图标就多一个窗口？**
不会。服务与窗口都在同一进程内，且应用有单实例守卫（第二次启动会激活已有实例并退出）。

**窗口只显示空白或「Loading plugins…」很久**
启动遮罩会一直显示到前端真正渲染出来。若超过十几秒，看 `launcher.log` 里
"界面就绪"那行；只有认证墙（`dsh web authentication required`）才会触发重新认证。

**提示「端口 xxxx 上的服务不是本启动器启动的」**
端口上那个服务是别处（终端 / 旧启动器）启动的。两种做法：
1. **想直接接管它** → 菜单栏「重启」会强制停掉它再重新拉起（**会打断正在使用它的会话**）；
2. **想不打断它** → 在浏览器里打开 dsh 打印的认证地址完成一次认证，之后本启动器复用同一 cookie 即可进入。

**界面状态坏了（空白引导页）**
数据在 `~/.dsh/` 下通常是好的，是浏览器里那个 origin 的本地状态需要重置。
在窗口里按 `⌘⌥I` 打开开发者工具（或改用 Safari/无痕窗口验证），执行：

```js
Object.keys(localStorage).filter(k => k.startsWith('dsh')).forEach(k => localStorage.removeItem(k)); location.reload()
```

**想完全重置本启动器的状态**（cookie、窗口大小、缓存）：

```sh
rm -rf ~/Library/WebKit/com.kaidiren.dsh-mac-launcher \
       ~/Library/HTTPStorages/com.kaidiren.dsh-mac-launcher.binarycookies \
       ~/Library/Logs/DSH
defaults delete com.kaidiren.dsh-mac-launcher 2>/dev/null
```

## 目录结构

| 文件 | 作用 |
|---|---|
| `Sources/main.swift` | 入口：单实例守卫、应用菜单、退出流程、信号处理 |
| `Sources/Config.swift` | 配置解析（环境变量 / 配置文件） |
| `Sources/Service.swift` | `dsh web` 生命周期：启动、就绪、token 解析、重启、停止 |
| `Sources/WebWindow.swift` | 窗口 + WKWebView 宿主、认证流程、下载、右键菜单、兼容注入 |
| `Sources/MenuFallback.swift` | 弹层菜单定位兜底（WebKit 缺 CSS Anchor Positioning 时自己算坐标） |
| `Sources/MenuBar.swift` | 菜单栏图标与四个动作（打开/刷新/重启/退出） |
| `Sources/OverlayView.swift` | 启动进度与错误面板 |
| `Sources/Support.swift` | 日志、端口探测、认证 URL 解析与缓存 |
| `Sources/AtomicFlag.swift` | 跨线程标志（后台等待端口时判断子进程存活） |
| `build.sh` | 一键构建（默认 Release；`BUILD_TYPE=debug` 可切调试版） |
| `Resources/Info.plist` | bundle 描述 |
| `scripts/winlist.swift` | 调试小工具：列出窗口（验证开窗与尺寸） |
| `docs/背景与验证记录.md` | 为什么这样设计，以及可行性验证的实测数据 |

## 版本号

两处必须一起改（`build.sh` 只编译，不会替你改）：

- `Sources/main.swift` → `enum Version` 的 `string`（`--version` 的输出，也是「关于」面板显示的版本）
- `Resources/Info.plist` → `CFBundleShortVersionString`（Finder 与系统层面；应与上面那个保持一致）

升幅约定（**每次改动都顺手升，别攒着**）：

| 改动性质 | 升幅 | 例子 |
|---|---|---|
| 不兼容变更：启动参数、配置项语义、服务启动方式 | major `x.0.0` | 改 `DSH_*` 变量含义、不再复用外部服务 |
| 新增用户可见能力 | minor `1.x.0` | 页面缩放、新菜单动作、新自省参数 |
| 文案/配色修正、缺陷修复 | patch `1.0.x` | 菜单文案精简、错别字、修一处 UI 抖动 |

`Info.plist` 里的 `CFBundleVersion`（构建号）只是占位，**不递增、也不展示**：它是系统的
常规字段，而「关于」面板刻意只渲染语义版本 —— 面板的格式本来是 `Version <short> (<build>)`，
`main.swift` 里的 `showAboutPanel()` 把 `version` 传成空串才压掉后面那截括号（只传
`applicationVersion` 会回落到 bundle 的构建号，实测过）。将来若要签名分发、需要构建号
单调递增，再恢复维护它即可。

改完记得 `./build.sh` 并覆盖安装 `/Applications/DSH.app`。注意：安装只换了磁盘上的包，
**关于面板、菜单都来自运行中的进程**，要让改动可见必须重启启动器进程（退出再打开）；
直接改盘上的 `Info.plist` 对已经在跑的实例无效。

> 具体怎么重启见下一节「重启启动器（让改动生效）」。**不要**在会话里随手挂
> `sleep && kill && open` 脚本——它会因为连坐而在 `open` 之前消失。

## 重启启动器（让改动生效）

改盘上的二进制或 `Info.plist` **不影响已运行的进程**：菜单项、`--version`、「关于」面板
都来自进程内存。要让改动可见必须重启启动器；而它退出时会停掉自己拉起的 `dsh web`，
**正在使用的会话会随之断开**（会话本身在磁盘上，重连后可继续）。

### 两种不可用的写法（都实测踩过）

1. **会话里挂延迟脚本**（`sleep && kill && open &`）：脚本是发起它的那个会话的子孙进程，
   重启动作会停 `dsh web`，脚本常在执行到 `open` 之前就被一起收走 —— 结果是"窗口关了却
   再也起不来"。2026-10-10 与 2026-11-15 各有实证，日志都停在 kill 那一行。
2. **`nohup setsid bash x.sh & disown`**：`setsid` 在 macOS **根本不存在**（那是 Linux 的
   工具，`which setsid` 输出为空）。整条命令直接失败，而 stdout 早已重定向进 `/dev/null`，
   于是**完全静默**：终端回显了 `armed`，排上的脚本却一个字节都没跑，连日志文件都不会被
   创建。2026-11-15 因此空转两次，误判为"脚本被杀"。去掉 `setsid` 只留 `nohup` 也不行，
   连坐问题照旧。

另外尽量别用 `kill -9`：1.0.3 起 `dsh web` 的输出改为直写日志文件，原先"管道读端消失
导致 EPIPE"的风险已不存在，但 `SIGTERM` 仍比强杀多一层正常清理。

### 可靠做法：launchd 一次性任务

launchd 的任务不属于任何会话进程树，`dsh web` 停掉不会波及它。三步：

**1. 写脚本 `/tmp/dsh-relaunch.sh`**（`chmod +x`）：

```sh
#!/bin/bash
exec >> /tmp/dsh-relaunch-launchd.log 2>&1
set -x
date
sleep 3
PID=$(lsappinfo info -only pid $(lsappinfo find bundleID=com.kaidiren.dsh-mac-launcher) 2>/dev/null | tr -dc "0-9")
echo "old_pid=$PID"
[ -n "$PID" ] && kill -TERM "$PID"
# 必须等旧实例真的消失再 open：应用有单实例守卫，抢跑会直接激活旧进程
for i in $(seq 1 30); do
  sleep 0.5
  P=$(lsappinfo info -only pid $(lsappinfo find bundleID=com.kaidiren.dsh-mac-launcher) 2>/dev/null | tr -dc "0-9")
  [ -z "$P" ] && break
done
echo "after_kill=[$P]"
open -a /Applications/DSH.app
sleep 6
/Applications/DSH.app/Contents/MacOS/DSHLauncher --version
lsof -nP -iTCP:3080 -sTCP:LISTEN | head -2
launchctl bootout gui/$(id -u)/com.kaidiren.dsh.relaunch 2>/dev/null || true
```

**2. 写 plist `/tmp/com.kaidiren.dsh.relaunch.plist`**：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.kaidiren.dsh.relaunch</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>/tmp/dsh-relaunch.sh</string></array>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>/tmp/dsh-relaunch-launchd.log</string>
  <key>StandardErrorPath</key><string>/tmp/dsh-relaunch-launchd.log</string>
</dict>
</plist>
```

**3. 加载任务**：

```sh
launchctl bootout gui/$(id -u)/com.kaidiren.dsh.relaunch 2>/dev/null
launchctl bootstrap gui/$(id -u) /tmp/com.kaidiren.dsh.relaunch.plist
```

在 DSH 会话内执行时 `bootstrap` 需要提权（沙箱内报 `Bootstrap failed: 5: Input/output error`），
在普通终端里直接跑不需要。

### 判据

- `tail /tmp/dsh-relaunch-launchd.log`：应看到 `old_pid=…` → `after_kill=[]` → `open` 之后的
  `--version` 与端口两行。**日志文件不存在 = 任务没跑起来**（先查 `which setsid` 这类命令
  是否真的存在，别和服务连坐混为一谈）。
- `lsappinfo list | grep -i -A3 kaidiren`：`pid` 应是新值，`bundle path` 指向 `/Applications/DSH.app`。
- 任务跑完会 `bootout` 自己，之后 `launchctl print gui/$(id -u)/com.kaidiren.dsh.relaunch`
  报 `Could not find service` **属正常收尾**，不是失败。
- `~/Library/Logs/DSH/launcher.log` 末尾应有新的「服务就绪 / 界面就绪」两行。

### 实测记录

2026-11-15 11:40（1.0.6 发布）：`bootstrap` → `kill -TERM` 旧实例 87632 → 轮询到空 →
`open -a /Applications/DSH.app` → 新实例 90173 起来、`dsh web` 90178 就绪、界面就绪 54926
字符，全程约 5 秒；任务自行 `bootout` 收尾。2026-10-10 那次同样成功（2.33s）。
## 已知限制

- 菜单栏图标只在**本应用运行时**存在。退掉应用图标就没了 —— 但服务仍在跑，重新打开应用即可。
- WKWebView 与 Chrome 的渲染内核不同。已实测 DSH GUI 完整可用（会话列表、工作区、余额、
  上传下载、WebSocket 长连接），个别 CSS 细节可能有细微差异。
- 在 macOS 14.4 以下运行时会注入 `AbortSignal.any` / `Promise.withResolvers` / `Promise.try`
  的兼容实现（DSH 前端在关键路径上用了它们且没有 polyfill）。
- DSH 前端的弹层菜单靠 CSS Anchor Positioning 定位（`anchor()` / `position-anchor`），
  Chromium 125 起就支持，而 WebKit 要到 Safari 26 / macOS 26 才有。本应用因此在
  `Sources/MenuFallback.swift` 里带一段兜底：检测到 `CSS.supports('anchor-name: --a')` 为 false
  时，按触发器的矩形自己算菜单坐标。**没有该兜底的菜单**（例如右键菜单
  `data-context-menu`，它没有 `aria-expanded` 触发器）仍会错位。
  兜底依赖前端的 DOM 约定（`role=menu` / `data-anchor-side` / `aria-expanded`），前端改结构后
  它会静默失配：菜单回到错位，但不会报错。
- 文件上传用 `<input type=file>`（原生文件面板）；拖放上传与剪贴板粘贴图片沿用浏览器行为，
  遇到问题请记录到 `launcher.log` 附近的现象里反馈。

## 许可

本项目以 [MIT](LICENSE) 发布。

`Resources/icons/app-icon-mac.png`（应用图标）取自
[anywhere-labs/dsh-desktop](https://github.com/anywhere-labs/dsh-desktop)，
**其版权归该项目所有、不在本项目的 MIT 范围内**；再分发前请自行确认其许可。
`Resources/icons/tray-iconTemplate*.png` 与 `tray-icon.svg` 沿用旧启动器的素材。

菜单栏图标加载 `@2x`（32×32）那份、逻辑尺寸设为 18pt，并标记为模板图标。
**不要改用 1x（16×16）那份** —— 它在 Retina 上要被拉大两倍多，菜单栏里会发糊。
