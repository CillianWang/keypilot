# 0.1.0 / build 17 发布构建记录

本次首次提供可下载的 DMG 和 ZIP，应用功能源码与 build 16 相同。构建号更新为 17，加入通用架构构建、可重复执行的打包脚本和包内 MIT 许可证。

## 构建环境

- 打包平台：Apple Silicon，macOS 27.3。
- 编译工具：Command Line Tools 的 Apple Swift 6.4.2。
- SDK：本机已安装的 macOS 26.5 SDK。
- SwiftPM 构建引擎：`native`。
- 目标：`arm64-apple-macosx13.0` 与 `x86_64-apple-macosx13.0`，合并为通用二进制。
- 签名：沿用本机固定 Apple Development 身份；无附加权限声明，未进行 Developer ID 签名或 Apple 公证。

本机完整 Xcode 尚未完成许可设置；当前 Command Line Tools 的默认 macOS 27.2 SDK 构建还缺少 `SwiftUIMacros` 插件。因此本次显式选择已安装的兼容 SDK，未修改应用功能代码规避编译错误。

在具有同样工具链的机器上，可使用：

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools \
KEYPILOT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
KEYPILOT_BUILD_SYSTEM=native \
bash scripts/build.sh --universal

DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 scripts/package-release.py
```

其他机器应选择其实际安装且完整的开发工具，不必照搬上述 SDK 路径。`native` 构建引擎在当前工具链中已标记弃用，后续升级应重新验证默认构建引擎。

## 验证范围

发布附件中的 `BUILD_INFO.json` 记录实际架构、最低系统版本、打包提交及产物哈希；`SHA256SUMS.txt` 用于核对下载内容。

| 检查 | 结果 |
| --- | --- |
| 两种架构的 release 编译与链接 | 通过，合并为 arm64 + x86_64 通用二进制 |
| Mach-O 部署目标 | 两个架构均为 macOS 13.0 |
| 证书签名与固定身份校验 | 通过，保持原 Bundle ID 与签名身份 |
| arm64 启动自检与正式绘制器校验 | 通过 |
| x86_64 启动自检与正式绘制器校验 | 通过，使用 Rosetta；不等于 Intel 真机验证 |
| 设置视图示例渲染 | 四页及外观深色示例均成功生成，并检查通用页图像 |
| Gatekeeper 自动接纳 | 不通过；当前包未使用 Developer ID 签名及 Apple 公证，首次运行需要用户按系统提示确认 |

构建时出现两类警告：既有异步闭包的捕获声明警告，以及 Intel 链接时忽略不含 x86_64 的 `libswiftCompatibilityPacks.a`。链接完成不等于已覆盖所有旧系统与真实 Intel 机器，因此该版本标记为测试版。

本轮 `swift test` 尝试在当前 Command Line Tools 环境中因缺少 XCTest 而未能编译测试目标。历史 build 16 的 93 项 XCTest 通过记录见 [VALIDATION.md](VALIDATION.md)；不得把历史结果视为本次重跑通过。

macOS 13 是部署目标，不表示已在每个 macOS 13+ 版本完成测试。发布说明会列出此次实际完成的启动、绘制和打包检查；Intel 真机及跨系统的完整导航交互仍需验证。
