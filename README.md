# Wisp（雾灵）

桌面上一颗蓝色液态玻璃悬浮球。点它（或按 `⌥⌘V`），直接和 ChatGPT 官方实时语音对话。

A liquid-glass orb on your macOS desktop. Click it (or press `⌥⌘V`) to talk to ChatGPT's official realtime Voice — using your own Plus subscription, zero API cost.

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/0xtootoo29/wisp/main/install.sh | bash
```

装完跟随三步引导窗：① App 已装 ✓ → ② 商店一键装 Chrome 扩展 → ③ 登录 ChatGPT。完成后点悬浮球即可通话。

## 它是怎么工作的

- **不碰 API、不逆向**：Wisp 只是在你的 Chrome 里"替你点"chatgpt.com 官方页面上的语音按钮，走你自己的 Plus 订阅额度，零封号风险。
- **零窗口打扰**：配套 Chrome 扩展让后台标签页保持语音连接——通话时不需要切换或盯着任何窗口。
- **链路**：悬浮球 App → wisp-bridge（Native Messaging）→ Chrome 扩展 → ChatGPT 页面。全部本地，无任何第三方服务器。

## 功能

- 悬浮球：5 款玻璃球皮肤、拖拽自由摆放、贴边半隐（多显示器各屏边界均可吸附）
- 菜单栏面板：状态封面 + 一键起停 + 深/浅色外观切换
- 三步安装引导 + 一键自诊断（「为什么用不了？」直接告诉你卡在哪步并帮你修）
- 全局热键 `⌥⌘V`

## 要求

- macOS 13+，Google Chrome
- ChatGPT 账号（语音需 Plus 订阅）

## 从源码构建

```bash
git clone https://github.com/0xtootoo29/wisp && cd wisp
bash build.sh   # 编译并部署到 ~/Applications/Wisp.app
```

Chrome 扩展开发版：`chrome://extensions` → 开发者模式 → 加载已解压的扩展程序 → 选 `extension/`。

## 卸载

```bash
curl -fsSL https://raw.githubusercontent.com/0xtootoo29/wisp/main/uninstall.sh | bash
```

## 隐私

Wisp 不收集、不上传任何数据。详见 [PRIVACY.md](PRIVACY.md)。

## License

MIT
