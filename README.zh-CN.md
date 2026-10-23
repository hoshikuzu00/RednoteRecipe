# RednoteRecipe

[English](README.md) | **简体中文**

> **安装说明：** 本应用尚未上架 Apple App Store；通过 App Store 发布应用需要加入 [Apple Developer Program](https://developer.apple.com/help/account/membership/programs-overview)。目前请使用 Xcode 编译安装，在 iPhone 真机上运行时需要开启 [Developer Mode（开发者模式）](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。也可以使用 iPhone 模拟器体验。

把菜谱截图、视频和小红书分享链接，整理成可以编辑、保存、照着做的菜谱。

收藏了一篇菜谱，真正做饭时却还要在正文、图片和视频字幕之间来回找食材和步骤。RednoteRecipe 会把这些内容整理到一份菜谱里。你可以先检查和修改识别结果，再保存到菜谱库；做饭时逐步勾选，买菜前把食材加入购物清单。

这是一个使用 SwiftUI 开发的个人 iOS 项目。Xcode 工程和应用构建目标仍沿用 `RednoteOCR` 这个名称。

## 可以做什么

- 从相册或文件导入图片、视频，粘贴分享链接，也可以手动录入菜谱。
- 配置自己的 OpenAI API 密钥后，使用 AI 整理菜谱。不配置也可以导入本地图片和视频，通过设备上的文字识别和规则解析提取内容。
- 编辑菜谱、设置分类、搜索菜谱库、给菜品评分，并记录做到了哪一步。
- 将食材加入购物清单，关闭应用后仍会保留。
- 将菜谱、分类和购物清单导出为 JSON 备份。导入备份时，如果遇到同名菜谱，可以选择替换或保留两份。

## 运行应用

需要一台安装了 Xcode 的 Mac，以及运行 iOS 17 或更高版本的 iPhone 或模拟器。请先完成 Xcode 的首次启动设置，按提示安装 iOS 平台支持。Xcode 的版本需要支持手机当前的 iOS 版本。

克隆仓库并打开已包含的工程：

```bash
git clone --recurse-submodules https://github.com/hoshikuzu00/RednoteRecipe.git
cd RednoteRecipe
open RednoteOCR.xcodeproj
```

如果只想先用模拟器体验，在工具栏选择 **RednoteOCR** 运行方案和一个 iPhone 模拟器，点击 **Run** 即可。安装到自己的 iPhone，请按下面的步骤操作。

### 安装到自己的 iPhone

在自己的设备上测试，可以使用个人 Apple 账号，不需要付费加入 Apple Developer Program。Xcode 会将这类账号显示为 **Personal Team**。个人团队安装的应用需要定期重新签名；到期后，连接手机并通过 Xcode 再次运行即可续用。详见 [Apple 账号说明](https://developer.apple.com/help/account/basics/about-your-developer-account)。

#### 1. 连接并配对手机

1. 用支持数据传输的线缆连接 iPhone 和 Mac，并解锁手机。
2. 如果手机提示“**要信任此电脑吗？**”，点击“**信任**”，并输入手机锁屏密码。
3. 在 Xcode 中打开 **Xcode → Open Developer Tool → Device Hub**，也可以从工具栏的运行设备菜单选择 **Manage Devices…**。较旧版本的入口是 **Window → Devices and Simulators**。
4. 选择自己的 iPhone，按界面提示配对；如果出现 **Pair** 按钮，点击它。接下来的设置过程中保持手机连接。

#### 2. 开启 Developer Mode（开发者模式）

1. 在 iPhone 上打开“**设置 → 隐私与安全性 → 开发者模式**”，开启开关。
2. 阅读系统提示，点击“**重新启动**”。
3. 重启后解锁手机，在确认提示中开启开发者模式，并按要求输入锁屏密码。

如果找不到“**开发者模式**”，先完成上一步中开始与 Xcode 配对的操作，再回到设置查看。Apple 只会在开始配对或设备曾经配对后显示这个选项。详见 [Apple 开发者模式指南](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

#### 3. 配置签名并安装

1. 打开 **Xcode → Settings → Apple Accounts**，登录自己的 Apple 账号。较旧版本的标签可能叫 **Accounts**。
2. 点击左侧栏蓝色的 **RednoteOCR** 工程图标，在 **TARGETS** 下选择 **RednoteOCR**，打开 **Signing & Capabilities**。
3. 勾选 **Automatically manage signing**，在 **Team** 中选择自己的 **Personal Team** 或开发团队。将 **Bundle Identifier** 改为唯一的标识，例如 `com.yourname.RednoteRecipe`，其中 `yourname` 替换为自己的标识。如果出现 **Set Up Signing**，就在该对话框中选择团队并填写 Bundle ID。
4. 在工具栏选择 **RednoteOCR** 运行方案，并将已连接的 iPhone 设为运行设备。如果 Xcode 显示 **Register Device**，按提示注册，等待设备准备完成。
5. 点击 **Run** 或按 **⌘R**，保持手机解锁。编译成功后，Xcode 会把应用安装到 iPhone 上并启动。

如果签名失败，先检查团队是否选对、Bundle ID 是否唯一。如果设备不可用，查看 Device Hub 中的具体提示，并确认 Xcode 支持手机的 iOS 版本。Apple 的[设备配对指南](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)和[运行与签名指南](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)提供了更详细的界面说明。

第一次体验时，可以先导入一张文字清晰的菜谱截图，检查食材和步骤，再保存。这一步不需要 API 密钥，也不需要配置 Mac 后端。本地解析更适合文字清楚的图片和带字幕的视频。

### 重新生成工程（可选）

仓库已包含 Xcode 工程。只有修改了 `project.yml`、需要重新生成工程时，才需要使用 [XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
xcodegen generate
```

重新生成会恢复 `project.yml` 中的设置。要保留自己的 Bundle ID 和签名团队，请同步修改该文件，或在生成后回到 Xcode 重新选择。

### 可选：使用 AI 整理菜谱

在应用设置中填写自己的 OpenAI API 密钥。应用会把选中的图片或视频帧，以及相关文字发送到 Responses API，再把返回结果整理成可编辑的菜谱。API 密钥保存在设备的 Keychain（钥匙串）中。

API 请求可能产生费用，设置里的连接测试也会发出请求。请在应用中填写密钥，不要把真实密钥写进 `LocalSecrets.swift` 或提交到 Git。

#### 模型选择与请求限制

**当前仓库版本的所有 AI 请求都固定使用 `gpt-5.4-nano`。** 模型名称写在源码中，设置界面只能填写 API 密钥，不能选择模型。请求失败后，应用也不会自动切换到另一个模型。

**测试体验：** 本项目也使用 GPT-5.5 进行过测试，菜谱提取结果已达到较好的准确度。这是基于测试结果的定性评价。

| 请求 | 模型 | `max_output_tokens` |
| --- | --- | --- |
| 从文字、图片或视频帧提取菜谱 | `gpt-5.4-nano` | 2,000 |
| 检查菜名 | `gpt-5.4-nano` | 220 |
| 设置中的连接测试 | `gpt-5.4-nano` | 20 |

这些输出上限由应用设置，不代表模型本身的最大能力，也不是一次导入的总 token 预算；输入文字和图片同样会产生用量。API 地址固定为 `https://api.openai.com/v1/responses`，设置里的后端地址只用于配置小红书适配服务。

如果要更换模型，需要修改 [OpenAIRecipeEnhancer.swift](Sources/OpenAIRecipeEnhancer.swift) 中的 `model` 和 [OpenAISettingsStore.swift](Sources/OpenAISettingsStore.swift) 中的 `recipeModel`，然后重新编译。同时更新 [OCRViewModel.swift](Sources/OCRViewModel.swift) 和 [OpenAISettingsView.swift](Sources/OpenAISettingsView.swift) 中显示的模型名称。

新模型需要兼容现有的 Responses API 请求，包括[图片输入](https://developers.openai.com/api/docs/guides/images-vision)和[严格 JSON Schema 输出](https://developers.openai.com/api/docs/guides/structured-outputs)，你的 API 账号也需要有权使用它。换模型时应检查请求参数和 token 预算；只改名称不代表已经验证兼容。设置中的连接测试只发送一条简短文字请求，通过测试并不代表图片提取和结构化输出也已经验证。

### 可选：通过 Mac 导入小红书链接

有些帖子需要登录后才能读取。遇到这类内容，应用可以借助运行在 Mac 上的后端，通过已登录小红书的 Chrome 获取帖子。

这里接入的是 [autoclaw-cc/xiaohongshu-skills](https://github.com/autoclaw-cc/xiaohongshu-skills)，它提供 Chrome 扩展、WebSocket 桥接服务和命令行工具。本项目的 Python 适配服务通过命令行工具读取帖子，这套安装流程不需要另行配置 MCP 服务。

```text
iPhone → Python 适配服务 → 浏览器桥接服务 → 已登录小红书的 Chrome
```

按照[后端安装指南（英文）](LocalBackend/README.md) 安装 Python 依赖和 Chrome 扩展，然后在应用设置中填写 Mac 后端地址。导入本地图片、视频或手动录入菜谱，都不需要这个后端。

## 菜谱是怎样提取出来的

处理图片时，应用先检查其中是否有可读文字；处理视频时，会抽取画面，并过滤文字内容相近的帧。配置 API 密钥后，模型会将内容整理为食材、用量、步骤、菜谱分组、小贴士和时间信息，随后再通过一次独立请求检查菜名。

没有配置密钥，或 AI 提取失败时，应用可以使用 Apple Vision OCR 识别图片和视频帧中的文字，再在本地解析。导入链接时，会先尝试已配置的 Mac 后端，失败后可以尝试直接读取公开网页。不过，公开网页不一定包含登录后能看到的全部内容。

视频处理依赖画面和可见文字，目前不支持语音转写。保存或做饭前，请检查提取出的食材用量和步骤。

## 数据保存在哪里

菜谱、分类和购物清单以 JSON 文件保存在设备本地。目前没有账号系统或云同步。API 密钥保存在 Keychain 中，不会写入备份文件。

使用 AI 提取时，选中的图片、视频帧和相关文字会发送给 OpenAI。本地 OCR 不会把这些内容发送给 OpenAI。导入链接仍然需要联网。

## 目前的限制

- 小红书导入依赖分享链接格式、可获取的图片或视频，以及浏览器登录状态，不能保证每篇帖子都能成功导入。
- 视频中如果没有清晰的文字，可能无法提取出足够的信息。视频下载或抽帧失败时，导入可能中止。
- 购物清单会逐项添加食材，不会自动合并不同菜谱里的用量，也不会换算单位。
- 后端自动发现目前关闭，需要手动填写地址；Mac 的地址变化后，也需要更新设置。
- Mac 后端没有登录验证或 HTTPS 加密。请仅在可信任的局域网内使用，不要开放到互联网。

## 代码结构

| 路径 | 内容 |
| --- | --- |
| `Sources/` | SwiftUI 界面、导入流程、菜谱解析、本地存储和设置 |
| `Resources/` | 应用配置和图片资源目录 |
| `skills/recipe-post-parser/` | 随应用打包、在 AI 提取时读取的 Markdown 提示词 |
| `LocalBackend/` | Python 适配服务、启停脚本和浏览器桥接子模块 |
| `Tests/` | 菜谱数据处理与提示词加载的离线回归检查 |
| `project.yml` | XcodeGen 工程配置 |

Markdown 提示词是应用资源，使用应用不需要另行安装 AI agent 或技能运行器。后端的请求和返回格式见 [LOCAL_BACKEND.md（英文）](LOCAL_BACKEND.md)。

## 运行检查

在已安装 Swift 工具链的 macOS 上运行：

```bash
python3 Tests/run_recipe_regressions.py
python3 Tests/run_prompt_bundle_regressions.py
```

这些检查覆盖菜谱数据处理、API 返回结果解析，以及打包后的提示词能否正确加载。运行时不需要 API 密钥，也不需要登录小红书。它们不覆盖界面操作、真实 AI 请求或需要登录的小红书导入。当前 Xcode 运行方案没有配置 XCTest 测试目标。

## 第三方代码

可选后端使用 [autoclaw-cc/xiaohongshu-skills](https://github.com/autoclaw-cc/xiaohongshu-skills) 提供的 Chrome 扩展、浏览器桥接服务和命令行工具。该项目以固定版本的 Git 子模块引入，遵循其自身的 [MIT 许可证](https://github.com/autoclaw-cc/xiaohongshu-skills/blob/9d3055b2f45e166b9514af16020e9fd5163a43a4/LICENSE)。本仓库的 iOS 应用和 Python 适配服务负责与它对接。

如果克隆时没有下载子模块，可以补充运行：

```bash
git submodule update --init --recursive
```

GitHub 的源码 ZIP 不包含子模块内容。如果需要运行后端，建议使用 Git 克隆仓库。
