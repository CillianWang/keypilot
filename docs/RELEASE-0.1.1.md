# Keylian 0.1.1 / build 18

KeyPilot 更名为 **Keylian**。本次同步修改菜单栏文字、设置页、辅助功能标签、App 名称、可执行文件、矢量资源标题、README 预览与 DMG / ZIP 文件名。导航功能和快捷键保持兼容。

## 升级与兼容

新安装位置为 `~/Applications/Keylian.app`。Bundle ID 仍为 `dev.pingy.keypilot`，设置窗口位置、偏好域、`Application Support/KeyPilot` 与 `Logs/KeyPilot` 沿用原位置，避免因显示名称变化丢失设置。

签名脚本会核对新旧两种名称的已有安装；若任何一份使用不同证书，将拒绝签名或替换。安装脚本先验证暂存包，将新旧名称的原 App 移入备份，再安装 Keylian。替换或签名验证失败时恢复原 App；备份中同时保存偏好与签名配置。

手动下载安装时，先退出并移开旧 `KeyPilot.app`，再启动 `Keylian.app`；详见 [安装说明](INSTALL.md)。辅助功能授权是否保留，以已启动 App 报告的实际状态为准。

Swift 内部 target / 测试模块名仍使用 KeyPilot / KeyPilotCore；可执行产品名为 Keylian。旧 `KEYPILOT_*` 构建和签名配置环境变量仍作为兼容别名接受，新名称使用 `KEYLIAN_*`。

## 构建与检查

构建环境继续使用 macOS 27.3、Apple Swift 6.4.2、已安装的 macOS 26.5 SDK 和 SwiftPM native 引擎；目标为 arm64 与 x86_64 的 macOS 13.0。沿用固定 Apple Development 签名，仍是未公证测试版。

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
KEYLIAN_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
KEYLIAN_BUILD_SYSTEM=native \
bash scripts/build.sh --universal

python3 scripts/test-install-migration.py
# 提交本次改动后再打包
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 scripts/package-release.py
```

安装迁移回归覆盖旧名称迁移、同时存在新旧 App、签名验证失败回滚、移动失败回滚、首次安装失败清理，以及旧名称签名不匹配时拒绝操作。所有测试只使用临时文件。

| 本轮检查 | 结果 |
| --- | --- |
| 安装迁移与失败回滚 | 6 项临时文件测试通过 |
| 通用构建、自检和正式绘制器校验 | arm64 原生与 x86_64 / Rosetta 均通过 |
| 新旧 App 的 designated requirement | 一致，保持原证书及 Bundle ID |
| 签名负例 | 资源篡改、同 Bundle ID 的临时签名、签名配置缺失均被拒绝 |
| 设置视图 | 四页及深色外观渲染成功；检查并更新 README 的 Keylian 外观预览 |
| 本机从 build 16 升级到 build 18 | 新 App 位于 `~/Applications/Keylian.app`；旧 App 已移入备份，校验其可执行文件哈希一致 |
| 设置与签名配置 | 已保存的应用偏好保持一致，签名配置文件哈希未变 |
| 已启动 App 的实际状态 | 版本 0.1.1 / build 18，辅助功能权限、启用状态及全局热键均有效 |

当前 Command Line Tools 仍缺少 XCTest，完整 Swift 测试套件本轮不作为通过项；历史结果见 [VALIDATION.md](VALIDATION.md)。Intel 执行检查使用 Rosetta，不能代替 Intel 真机或 macOS 13 的完整交互验证。

安装包输出到 `dist/releases/v0.1.1/`，包含许可、安装说明、`BUILD_INFO.json` 和 `SHA256SUMS.txt`。发布说明列出此次实际完成的签名、启动、绘制、迁移与压缩包检查。
