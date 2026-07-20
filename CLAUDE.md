# Wisp 项目规范

系统机制见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)，本文件只写规则。

## 红线

- `wisp-extension-key.pem` 是扩展身份私钥：**绝不提交、绝不打包进任何 zip**（.gitignore 已挡，改打包脚本时重新确认）。
- 扩展 ID `icbpolfbnfgcloeeahjmiknhfflnefkp` 是全链路契约（NM 清单 / install.sh / 商店），不得变更 manifest 的 `key`。
- 不引入任何逆向 / API 调用路线：Wisp 只允许"替用户点官方页面按钮"。

## 构建与验证

- 构建部署一律 `bash build.sh`；可执行名是 `GPTLive`（`pkill -x GPTLive`）。
- 改了 `extension/` 下任何文件，必须在 `chrome://extensions` 里 reload 扩展才生效（改 manifest 的 key 以外字段 reload 即可，ID 不变）。
- 验证二进制里是否包含某字符串时注意：Swift ≤15 字节的字面量会内联进代码段，字节扫描扫不到——只能用长字符串做标记，编译成败以 `set -e` 的 build.sh 为准。
- 产物验证以文件真实存在/内容为准，不轻信构建命令的 stdout 回显。

## 版本与发布

- 对外版本从 v1.0 起（2026-07-20 首发），不再使用 0.x；同步三处：build.sh 的 CFBundleVersion/ShortVersionString、extension/manifest.json 的 version、WispUI.swift 引导窗版本文案。
- 发布流程：build.sh → `ditto -ck --keepParent ~/Applications/Wisp.app dist/Wisp.zip` → GitHub Release（资产名必须 `Wisp.zip`）→ 实测一键安装命令端到端。
- GitHub API 5xx 时用重试循环穿过（历史上 api/uploads 曾大面积故障半小时）。

## 商店（CWS）

- 上传包：`cd extension && zip -qr ../dist/wisp-extension-vX.Y.zip . -x ".*"`（manifest 在 zip 顶层）。
- 提审材料照 [store-listing.md](store-listing.md)。上传后核对控制台项目 ID 是否等于预埋 ID；不同则把两个 ID 都写进 NM 清单 `allowed_origins` 并更新 install.sh。
