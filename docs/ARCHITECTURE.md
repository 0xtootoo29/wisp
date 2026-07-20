# Wisp 架构说明

> 读者对象：想理解或修改 Wisp 的开发者。5 分钟读完。

## 组件与链路

```
悬浮球 App (GPTLive.swift + WispUI.swift)
   │  macOS 分布式通知 local.tootoo.wisp.cmd / .state
   ▼
wisp-bridge (wisp-bridge.swift, Native Messaging host)
   │  NM 帧协议：4 字节小端长度 + JSON，stdin/stdout
   ▼
Chrome 扩展 (extension/)
   │  chrome.tabs.sendMessage
   ▼
chatgpt.com 页面 (voice.js content script 点击官方语音按钮)
```

- **App**：菜单栏 + 悬浮球 UI，无网络、无麦克风权限。只发命令、收状态。
- **wisp-bridge**：由 Chrome 在扩展 `connectNative` 时拉起，纯中继，stdin EOF 即退出。每 25s 向扩展发 `ping` 保活 service worker。
- **扩展**：`keepalive.js`（MAIN world，document_start）伪装页面可见性，让后台标签的语音连接不被浏览器挂起——"零窗口打扰"的关键；`background.js`（SW）负责编排；`voice.js`（isolated world）找按钮、点按钮、用 MutationObserver 实时推送状态。

## 消息协议

App → 扩展（经 bridge，`{"cmd": ...}`）：

| cmd | 含义 |
|---|---|
| `toggle` | 起/停语音：有通话中标签 → 全部挂断；否则挑可用标签启动；没有标签 → 后台开一个（`active:false`） |
| `status` | 询问全局状态，扩展回 `status-none / unready / idle / live` |
| `setup-tab` | 打开（或复用）ChatGPT 标签并置顶固定（pinned），前台弹出供登录 |
| `ping` | bridge 保活心跳，SW 收到即可 |

扩展 → App（`{"event":"state","state": ...}`）：

| state | 含义 |
|---|---|
| `hello` | SW 连上 bridge（= 扩展已安装且链路通，引导窗第②步据此打勾） |
| `idle` / `busy` / `live` | 页面语音状态；`idle` 在 SW 做跨标签聚合（其他标签通话中时不下发） |
| `status-*` | 对 `status` 询问的回答，App 的诊断窗口据此出结论 |

App 侧兜底：发出 `toggle` 后 45s 无回包 → 回 idle（覆盖 Chrome 未开 / 扩展未装）。

## 状态机（App 侧）

`idle → busy →（live | idle）`。busy 由点击触发；live/idle 均由扩展实时推送驱动，App 不轮询。
通话中挂断（无论从球还是网页操作）都由 voice.js 的 MutationObserver 推送回来。

## 悬浮球位置机制

- 拖拽自由摆放，位置存 UserDefaults `orbOrigin`。
- **贴边半隐**：松手时球缘距所在屏幕左/右边 < 70pt 即吸附，半隐只露 32pt 月牙；hover 浮出，通话中强制浮出。
- **多显示器**：吸附判定按"球心所在屏幕"的边界（`NSScreen.screens` 逐屏判断，不能用 `window.screen`——半隐时窗口大部分在屏外会返回 nil/错屏）。吸附瞬间固定参照屏（`dockRect`），脱离吸附才重算。
- **内部边界（双屏中缝）**：窗口不能滑出中缝——macOS「显示器使用不同空间」会按窗口主体改判归属屏幕，导致球在两屏间跳动。方案：窗口整体钉在本屏，半隐改用 `setBoundsOrigin` 内容位移（球在窗口内部平移出去被裁掉）。
- **拖拽期间冻结一切自动位移**（`dragging` 标志）：快拖时光标会瞬间甩出视图触发 mouseExited，若不冻结，hover 缩回动画会和拖拽抢窗口位置。

## 扩展 ID 与 Native Messaging

- 扩展有两个 ID：**商店正式版** `mghelpfopaeahcpdgjnbffnmkeapgpnn`（CWS 分配，上传包必须剥离 manifest 的 `key` 字段）；**本地开发版** `icbpolfbnfgcloeeahjmiknhfflnefkp`（由 `manifest.json` 预埋的 `key` 公钥决定，对应私钥不在仓库中，见 .gitignore）。
- NM 清单 `com.tootoo.wisp.json` 由 build.sh / install.sh 写入
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`，
  `allowed_origins` 必须含扩展 ID。若商店版 ID 与预埋 ID 不同，两个 ID 都要写进去。

## 构建与发布

```bash
bash build.sh          # swiftc 编译双可执行 → 部署 ~/Applications/Wisp.app → 写 NM 清单 → 重启
```

- 多文件 swiftc：入口必须 `@main`（顶层代码只允许单文件）；`NSApplication.delegate` 是弱引用，需另持强引用。
- Release 资产名必须是 `Wisp.zip`——install.sh 按 `releases/latest/download/Wisp.zip` 下载。
- 动效不用 CABasicAnimation 驱动旋转（历史上被图层结构吞掉），统一 Timer 60fps 手动驱动，`RunLoop.common` 模式保证菜单/拖拽期间不停帧。

## 已验证走不通的路线（勿重试）

- ChatGPT 桌面 App 的语音快捷键（26.707 版是死绑定，仅听写）；大版本更新后可复测。
- 内嵌 webview（Cloudflare 人机验证 + Google SSO 封锁）。
- 逆向 WebRTC（有封号先例，违背零风险铁律）。
- AppleScript 注入路线（v0.9 及以前）：依赖按 profile 的 Chrome 菜单开关 + 授权弹窗，已被 Native Messaging 取代并删除。
