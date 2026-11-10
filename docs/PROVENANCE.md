# 来源与许可检查

检查日期：2026-11-10。对象：`CillianWang/keypilot` 初次导入提交 `1e41875e593ab5e7898075f73b0885a1a061468a` 的 40 个文件及唯一一条既有提交历史，以及本次补充的 README、MIT 许可证和设置预览图。

**本次有限检查没有发现可确认的第三方代码复制、素材搬运或许可证冲突。发现已有同名键盘软件，名称混淆风险仍待进一步核查。** 这一结果不是“不侵权”的法律保证，也不替代创作记录或完整的代码相似性、商标与专利检索。

## 来源盘点

| 内容 | 可核查证据 | 检查结果 |
| --- | --- | --- |
| Swift 源码与测试 | `Sources/` 中 18 个 Swift 文件，`Tests/` 中 7 个测试文件 | 未发现第三方版权头、来源声明或大段附带的外部源码；维护者确认没有已知的外部复制、改编来源 |
| 包依赖 | [Package.swift](../Package.swift) | 无远程包、二进制 target 或 vendored 依赖；`KeyPilotCore` 是本仓库内部 target |
| 构建与安装脚本 | [scripts/](../scripts/) | Python 标准库、本地 `signing` 模块及 macOS 系统工具；未发现下载并打包外部源码的步骤 |
| 应用图标 | [SVG](../Resources/Brand/KeyPilot.svg)、[Brand.swift](../Sources/KeyPilot/Brand.swift) | K 字母、箭头和圆角键帽由路径绘制；SVG 不引用外部图片或字体。维护者确认没有已知外部图标来源，未完成全网图形相似性检索 |
| 设置预览图 | [settings-appearance.png](images/settings-appearance.png)、[SettingsPreview.swift](../Sources/KeyPilot/SettingsPreview.swift) | 来自本项目实际设置视图的既有示例渲染，视觉检查未见第三方应用画面或个人内容；以模拟数据演示标签 |
| 系统界面元素 | [SettingsView.swift](../Sources/KeyPilot/SettingsView.swift)、[GlassLabel.swift](../Sources/KeyPilot/GlassLabel.swift) | 通过系统 API 使用 AppKit、SwiftUI、系统字体及 SF Symbols；未随源码附带 Apple 字体文件、SDK 或导出的符号素材包 |
| 技术文档 | [DESIGN.md](DESIGN.md)、[VALIDATION.md](VALIDATION.md) | 包含 W3C、Apple、Chromium 的技术参考链接与行为概述；未发现附带整份外部文档或 Chromium 源文件 |

仓库中的来源声明只能说明当前可见记录，不能证明全部内容的独立创作过程。已有 Git 历史从一次整体导入开始，无法还原更早的编辑来源。

## 外部检索

对以下有辨识度的源码片段进行了 GitHub 代码搜索，检索时均未返回匹配项：

- `"Published labels are immutable"`
- `"RowActionGroup" "structureCounts" language:Swift`
- `"Reserve exactly the needed unpublished branches"`

另使用通用搜索引擎检索源码注释及 SVG 中的路径片段。没有取得能确认来源相同的结果。搜索索引覆盖不完整，零匹配不能证明不存在相似或未被索引的代码；本次未进行全网源码比对或反向图像检索。

## 名称需要进一步核查

截至检查日，存在以下独立的同名产品或项目：

- [ai-fresh/KeyPilot](https://github.com/ai-fresh/KeyPilot)：macOS 菜单栏工具，用于管理三键可编程键盘的配置。
- [Keypilot — App Store](https://apps.apple.com/jp/app/keypilot/id6808972712)：另一开发者发布的键盘应用。

这些记录证明名称已被其他键盘软件使用，不能单独证明谁拥有有效商标，也不能据此认定本项目侵权。名称相似程度、软件或服务的关联、适用地区和实际使用方式都可能影响判断；例如 [USPTO 的混淆可能性说明](https://www.uspto.gov/trademarks/search/likelihood-confusion) 讨论了名称与商品/服务关联的共同作用。

本次未完成中国、美国、欧盟等市场的商标清查，也未进行专利检索。正式品牌推广、上架或商业发行前，建议先做目标市场的名称检索，并考虑选用更有区分度的名称。MIT 许可不等于名称已获商标核准。

## 许可处理

维护者已明确选择 MIT。本次在仓库根目录加入 [LICENSE](../LICENSE)，使用标准 MIT 文本，版权署名为 `2026 CillianWang`。使用、修改或再发布时应保留其中的版权及许可声明；参见 [MIT 许可说明](https://choosealicense.com/licenses/mit/)。

Apple 系统框架、系统字体及 [SF Symbols](https://developer.apple.com/sf-symbols/) 仍由各自适用条款约束，本仓库的 MIT 不重新许可这些系统资源。文档引用的外部规范和项目仍归各自权利人。本次未发现需要补充的第三方再分发许可文本，因此没有生成臆造的第三方版权清单。

若后续确认引用了外部代码、图标或其他素材，应记录具体来源、版本和许可，并按其要求保留声明；不能仅凭本仓库附带 MIT 就覆盖来源不明的内容。

## 公开范围检查

对初次提交的全部文件及既有提交历史进行了常见私钥、GitHub token、API 密钥、凭据赋值、个人绝对路径和文件内电子邮件模式扫描，未检出命中。模式扫描有覆盖限制，不是完整的安全审计。

`.build/`、`dist/`、`artifacts/` 被 [`.gitignore`](../.gitignore) 排除；签名私钥和本机签名配置不在仓库。设置预览图经单独检查后复制到 `docs/images/`，不包含本机诊断日志。Git 提交本身包含提交者配置的作者姓名和邮箱。
