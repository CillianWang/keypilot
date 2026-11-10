# KeyPilot Mac 安装说明

无需安装 Xcode、Swift 或 Python，也无需自己创建签名证书。

## 下载正确的文件

从官方 Releases 下载：
https://github.com/CillianWang/keypilot/releases

- `arm64`：Apple Silicon（M 系列芯片）的 Mac。
- `x86_64`：Intel Mac。
- `universal`：同时包含上述两种架构。

以该次发布实际附带的文件为准。最低系统版本为 macOS 13；详细测试环境见该次发布说明。

## 安装

1. 下载并打开 `.dmg`。如果使用 `.zip`，先双击解压。
2. 如果已有 KeyPilot 在运行，从菜单栏选择「退出 KeyPilot」。
3. 打开访达，按 `⇧⌘H` 进入个人主文件夹，找到「应用程序」文件夹。若没有，在这里新建一个名为 `Applications` 的文件夹。
4. 将安装包内的 `KeyPilot.app` 拖入这个文件夹，即 `~/Applications/KeyPilot.app`。已有版本时替换同一位置的 App。
5. 从个人「应用程序」文件夹打开 KeyPilot。不要直接在磁盘映像中运行；安装后可推出磁盘映像。

KeyPilot 是菜单栏应用，没有 Dock 主窗口。从菜单栏的图标打开「设置…」即可。

## 第一次打开

当前包使用固定的 Apple Development 证书签名，尚未经过 Developer ID 签名和 Apple 公证。签名完整性验证不等于 Apple 公证。

如果 macOS 提示无法验证开发者或 Apple 无法检查恶意软件，在确认文件来自上述仓库后，先尝试打开一次，再到「系统设置 → 隐私与安全性」为 KeyPilot 选择「仍要打开」。系统管理策略可能不允许此操作。

如果提示软件损坏、包含恶意内容或证书已撤销，请停止安装并反馈；不要关闭系统安全功能。具体提示及处理方法以 Apple 官方说明为准：
https://support.apple.com/en-us/102445

## 授予辅助功能权限

1. 打开「系统设置 → 隐私与安全性 → 辅助功能」，添加并允许个人「应用程序」文件夹中的 KeyPilot。
2. 回到菜单栏的 KeyPilot，选择「重新连接」。在「设置… → 连接与权限」中确认权限与热键状态。
3. 切到要操作的窗口，按 `⇧⌘Space` 开始导航，按 `Esc` 退出。

更新后若权限失效，先核对安装位置，再在系统设置中重新授权同一 App，并重新连接。应用不需要录屏权限。

## 快速操作

- `Tab`、`W` / `E` / `R`：选择区域。
- 输入屏幕上的两位或三位字母标签：点击目标。
- 按住 `J` / `K`：向下 / 向上滚动；按住 Shift 加速。
- `;` 再输入行标签：展开行内操作。
- `I`：临时输入文字；`Esc` 返回导航，再按一次退出。

更多用法：https://github.com/CillianWang/keypilot#快捷键

## 校验与许可

每次发布附带 `SHA256SUMS.txt`，用于核对下载文件是否完整。应用包内和安装包内均附带 MIT 许可证。

可选的终端校验（将 `SHA256SUMS.txt` 和该次发布的全部文件下载到同一目录）：

```sh
shasum -a 256 -c SHA256SUMS.txt
```
