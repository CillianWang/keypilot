# KeyPilot

原生 macOS 13+ 菜单栏键盘导航工具。SwiftPM、AppKit、SwiftUI、Accessibility、CGEvent 和 Core Animation；无第三方依赖、服务器、OCR、录屏权限或联网需求。

## 构建与安装

```sh
swift test
bash scripts/build.sh
python3 scripts/install.py
```

当前机器的固定签名身份已初始化。安装位置始终是 `~/Applications/KeyPilot.app`，Bundle ID 始终是 `dev.pingy.keypilot`。菜单栏打开设置；关闭设置不退出。首次启用需要在系统设置的辅助功能权限中允许这个安装包，再选择“重新连接”。不会修改 TCC 或设置登录启动。

新机器先在“钥匙串访问”的证书助理创建本机代码签名证书，或使用已有有效开发证书。私钥留在本机钥匙串，然后显式绑定身份：

```sh
security find-identity -v -p codesigning
python3 scripts/signing.py init --identity <本机有效代码签名证书的SHA1>
```

配置位于 `~/Library/Application Support/KeyPilot/signing.json`，不在仓库内。已有安装时初始化会核对并复用原证书和 designated requirement。证书、私钥或配置缺失时构建失败；不会生成新身份或退回 ad-hoc。当前本机使用已有 Apple Development 身份，**不是 Developer ID 公证发行**。证书到期后的身份迁移必须显式处理，不能无声替换。

安装脚本先验证产物，备份原 App、偏好和签名配置，正常退出旧进程，验证暂存包再替换，重启后读取真实权限与热键状态。备份位于 `~/Library/Application Support/KeyPilot/Backups/`。应用版本与构建号分别在 `Resources/Info.plist` 中管理。

## 操作

| 按键 | 行为 |
| --- | --- |
| ⇧⌘Space | 进入或完全退出导航 |
| ⇧⌘J | 进入同一导航；激活后再次按不会退出 |
| W / E / R 及其两位组合 | 选区；超过九个区域用 Tab 跨组 |
| Tab / ⇧Tab | 下一个 / 上一个区域 |
| J / K | 按住向下 / 向上滚动，同时按住为零；Shift 加速 |
| gg / Home；⇧G / End | 顶部；底部 |
| Space | 显示全窗口及应用菜单的全量 AX 候选，包括已折叠的行内操作；保留滚动区 |
| ; 然后行标签 | 选择该行并悬停，刷新后展开它的操作按钮；不点击该行 |
| ;（已经展开时） | 收起行内操作；用户未移动鼠标时恢复原指针位置 |
| 两位或三位按钮码 | 精确匹配后自动点击；可在设置关闭自动点击 |
| ↑ / ↓，Return | 当前页选择、左键点击；⇧Return 右键；⌘Return Command 点击 |
| [ / ]；Backspace | 翻页；删除前缀 |
| I | 临时输入，保留当前区边框，普通文字和快捷键透传 |
| Esc | 输入模式回到导航；导航中直接退出 |

大区字母牌使用薄荷绿，默认高亮边框使用更浅的薄荷绿；按钮保持通透的浅蓝白原生毛玻璃和薄荷绿选中态，字母清晰。圆角、柔和细边与轻阴影帮助区分背景。设置中可选择浅色、深色、茶色或跟随系统；茶色按钮使用暖奶白字和浅琥珀选中态。区域内部保持透明，遵循系统“减少透明度”。

点击后继续导航。默认速度 900 px/s，Shift 2.5 倍，按钮字号 13 pt。设置持久保存启用状态、自动点击、速度、字号、颜色和动画。按物理键位识别，标签输入不依赖当前输入法。

默认启用“按需展开列表行操作”：保留行的主目标标签，收起该行内的按钮、弹出按钮等次要操作。按 `;` 后输入完整行标签来展开，也可用方向键选行后 Return；关闭自动点击时，完整标签仍需 Return 确认。没有自身点击动作的列表项使用仅用于展开的行标签，不会把容器当按钮点击。再次按 `;` 收起；滚动、切区或临时输入也结束展开。行结构无法确定时保留原候选，浮层菜单仍直接可选，内文链接和输入控件不随操作按钮折叠。设置可关闭此策略，`Space` 随时提供全量入口。

分组也支持没有列表角色的普通容器：较宽主目标及其小按钮、有独立正文的重复内容块，以及共用容器内纵向排列的主目标和同行小按钮。仅凭按钮大小不足以折叠；结构仍不明确时保留原标签。普通工具栏和带输入控件的表单不参与这些推断。

操作控件除了标准按钮，也包括通过 AXPress/AXPick 暴露点击动作的普通组或图像；它们必须先满足行分组规则才会折叠。正文链接、可点击文本和具有专用语义的输入/选择控件保持可用。

## 配置界面与标识

菜单栏选择「设置…」打开四页配置：通用、外观、快捷键、连接与权限；也可用 ⌘1–4 切页。设置实时保存，窗口可缩放并记住位置，关闭后继续在菜单栏运行。外观页复用正式标签/边框绘制器进行实时预览，支持原生颜色选择器、字号和玻璃样式；恢复默认外观只影响外观项。界面跟随 macOS 浅色/深色，侧栏使用原生毛玻璃。

Logo 将 K 的上臂延伸成方向箭头，放在薄荷绿键帽中；菜单栏采用同一图形的单色模板。矢量源文件为 `Resources/Brand/KeyPilot.svg`，原生绘制代码在 `Sources/KeyPilot/Brand.swift`。构建时生成 16–1024 px 图标集，打包为 AppIcon.icns；可导出的 PNG 位于 `artifacts/brand/KeyPilot.png`。

```sh
dist/KeyPilot.app/Contents/MacOS/KeyPilot --render-settings "$PWD/artifacts/settings"
dist/KeyPilot.app/Contents/MacOS/KeyPilot --export-brand "$PWD/artifacts/brand"
```

设置渲染采用隔离偏好，仅生成示例状态图，不更改用户设置；截图不代表实际授权验证或真实桌面毛玻璃合成。实际启动状态仍以安装检查和配置页显示为准。

## 工程结构

- `Sources/KeyPilotCore/`：纯状态机、区域选择、编码簿、空间/编码分页、坐标与落点、可注入读取器的分片扫描、有限延后刷新计划。
- `Sources/KeyPilot/`：正式 AX 读取器与对象身份注册表、串行 AX/控制/布局队列、事件 tap、Carbon 热键、滚轮/点击投递、正式覆盖层、原生设置和本地诊断。
- `Tests/KeyPilotCoreTests/`：真实边界条件的离线回归，使用同一个扫描器及布局器；无需桌面授权。
- `scripts/`：固定签名、打包安装、绘制检查、回归及性能报告。

```sh
bash scripts/regression.sh
python3 scripts/performance.py
```

回归绘图调用正式 `OverlayCanvas`，没有产品练习窗口。图像和验证输出在 `artifacts/`。`swift test` 可使用支持 Swift 5.9+ 的 Command Line Tools；本次实际构建工具与验收结果见 [验证记录](docs/VALIDATION.md)。

辅助诊断：

```sh
~/Applications/KeyPilot.app/Contents/MacOS/KeyPilot --self-check
~/Applications/KeyPilot.app/Contents/MacOS/KeyPilot --scan-frontmost
```

终端派生进程的权限归属可能与通过 Launch Services 启动的 App 不同；安装脚本以已启动 App 写入的 `ready.json` 为准，不能只凭命令行助手宣称权限保留。`--scan-frontmost` 遇到权限不足直接失败。

日志仅含计数、模式、页数、时间和错误状态，保存在 `~/Library/Logs/KeyPilot/metrics.jsonl`，约 2 MB 轮换，不保存文字内容、标题或 URL，不上传。

## 兼容性

所有应用走同一套结构规则，没有 App 名称、Bundle ID、网站或会话标题特例。AX 未公开的自绘元素无法可靠索引。一次扫描受节点数、候选数、时间及系统 IPC 超时预算保护；截断扫描会明确标记不完整，不释放尚未确认消失的身份。

某些应用让“更多、复制、编辑”等按钮平时透明、悬停才显示，但始终将它们暴露为可点击的 AX 元素。模型将可操作性与视觉可见性（确认可见、确认隐藏、未知）分开记录；AXHidden 缺失或为 false、矩形有效、命中成功均不会升级为确认可见。按需展开是展示折中，也可能收起常显按钮，不能保证“画面看不到的按钮绝不出现标签”。未识别为行的控件及全量入口仍可能包含透明按钮；当前未接入 DOM 或屏幕视觉验证。

滚轮路由与 AX 可见性取决于目标应用的实现。真实应用验证、工具限制、用户已确认的部分与尚待检查的部分逐项记录在 [验证记录](docs/VALIDATION.md)；性能口径见 [设计说明](docs/DESIGN.md)。
