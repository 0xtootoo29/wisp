# CWS 商店listing 填写材料（照抄用）

## 基本信息
- **名称**：Wisp — ChatGPT Voice
- **简介**（Summary，≤132 字符）：一键唤起 ChatGPT 官方语音：配合 Wisp 悬浮球，后台标签保持连接，零窗口打扰。
- **类别**：生产力工具（Productivity / Tools）
- **语言**：中文（简体）

## 详细说明（Description）
Wisp 是 macOS 桌面悬浮球应用「Wisp（雾灵）」的配套 Chrome 扩展。

它只做两件事：
1. 保持 chatgpt.com 后台标签页的语音连接——你不需要切换或盯着任何窗口；
2. 在你点击桌面悬浮球（或按 ⌥⌘V）时，代替你点击页面上的官方语音按钮，启动/结束对话。

特点：
- 使用 ChatGPT 官方网页语音，走你自己的订阅额度，不调用任何 API
- 全部通信在本机完成（Chrome Native Messaging），无任何服务器
- 不收集、不存储、不上传任何数据

需要配合 Wisp macOS 应用使用，一键安装：
https://github.com/0xtootoo29/wisp

## 单一用途说明（Single purpose）
在 chatgpt.com 页面上启动/结束 ChatGPT 官方语音对话，并保持后台标签页的语音连接（配合 Wisp macOS 悬浮球应用）。

## 权限理由（Permission justifications）
- **nativeMessaging**：与本机 Wisp 悬浮球应用通信——接收「启动/结束语音」指令、回报页面语音状态。纯本地进程通信，无网络传输。
- **主机权限 chatgpt.com**：扩展仅在 chatgpt.com 运行，用于点击页面上的语音按钮、读取按钮状态、以及保持后台标签的语音连接。
- **远程代码**：不使用（选"否，我不使用远程代码"）。

## 数据使用（Data usage / Privacy practices）
- 所有「是否收集」问题全部选 **否**（不收集任何用户数据）。
- 隐私政策 URL：https://github.com/0xtootoo29/wisp/blob/main/PRIVACY.md

## 图片素材
- 商店图标 128×128：`extension/icons/icon128.png`
- 截图（1280×800，至少 1 张）：待 too 提供实景截图后由 Claude 裁制

## ✅ ID 已定（2026-07-20 接线完成）
商店正式版项目 ID = `mghelpfopaeahcpdgjnbffnmkeapgpnn`（CWS 分配；上传包必须剥离 manifest 的 key 字段，CWS 拒收含 key 的清单）。
本地开发版 ID = `icbpolfbnfgcloeeahjmiknhfflnefkp`。两个 ID 均已写入 NM 清单 allowed_origins（build.sh / install.sh），App 商店按钮指向商店版。
