# RednoteRecipe

**English** | [简体中文](README.zh-CN.md)

> **Availability:** This app is not published on Apple's App Store. App Store distribution requires an [Apple Developer Program membership](https://developer.apple.com/help/account/membership/programs-overview). To use the app, build and install it with Xcode. Running it on a physical iPhone requires [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). You can also try it in the iPhone simulator.

Turn recipe screenshots, videos, and Xiaohongshu (Rednote) links into recipes you can edit and cook from.

A saved recipe post can leave you scrolling between captions, images, and video subtitles to find what you need. RednoteRecipe brings the ingredients and instructions into one editable recipe. Review it before saving, check off steps as you cook, and add ingredients to your shopping list.

This is a personal iOS project built with SwiftUI. The Xcode project and app target are still named `RednoteOCR`.

## What you can do

- Import images or videos from Photos or Files, paste a shared link, or enter a recipe by hand.
- Extract recipe details with an optional OpenAI API key. Without a key, local image and video imports use Apple's on-device text recognition and a rule-based parser.
- Edit recipes, assign categories, search the library, rate dishes, and keep track of completed steps.
- Add ingredients to a shopping checklist that stays saved between app launches.
- Export recipes, categories, and shopping items as a JSON backup. When importing a backup, review recipes with matching titles and choose whether to replace them or keep both.

## Run the app

You need a Mac with Xcode and an iPhone or simulator running iOS 17 or later. Complete Xcode's first-launch setup and install iOS platform support if prompted. Your Xcode version must support the iOS version on your phone.

Clone the repository and open the included project:

```bash
git clone --recurse-submodules https://github.com/hoshikuzu00/RednoteRecipe.git
cd RednoteRecipe
open RednoteOCR.xcodeproj
```

To try it in a simulator, select the **RednoteOCR** scheme, choose an iPhone simulator in the toolbar, and click **Run**. For your own iPhone, follow the steps below.

### Install on your iPhone

A personal Apple Account can be used for testing on your own device; you do not need a paid Apple Developer Program membership for this. Xcode calls this a **Personal Team**. Personal Team builds need to be renewed periodically by connecting the phone and running the app from Xcode again. See [Apple's account guide](https://developer.apple.com/help/account/basics/about-your-developer-account).

#### 1. Connect and pair your phone

1. Connect your iPhone to the Mac with a data cable and unlock it.
2. If the iPhone asks **Trust This Computer?**, tap **Trust** and enter the phone's passcode.
3. In Xcode, open **Xcode → Open Developer Tool → Device Hub**, or choose **Manage Devices…** from the run-destination menu. In older Xcode versions, use **Window → Devices and Simulators**.
4. Select your iPhone and follow the pairing instructions. Click **Pair** if it appears. Keep the phone connected while completing the next steps.

#### 2. Enable Developer Mode

1. On the iPhone, open **Settings → Privacy & Security → Developer Mode** and turn it on.
2. Read the prompt and tap **Restart**.
3. After restarting, unlock the phone, confirm that you want to enable Developer Mode, and enter the passcode if asked.

If **Developer Mode** is missing, start pairing the phone with Xcode in step 1 first, then check Settings again. Apple only shows the option after pairing has been initiated or the device was previously paired. See [Apple's Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

#### 3. Sign, build, and install

1. In **Xcode → Settings → Apple Accounts**, sign in to your Apple Account. Older versions may call this tab **Accounts**.
2. Click the blue **RednoteOCR** project icon in the left sidebar. Under **TARGETS**, select **RednoteOCR**, then open **Signing & Capabilities**.
3. Enable **Automatically manage signing**, select your **Personal Team** or development team, and change **Bundle Identifier** to a unique value, such as `com.yourname.RednoteRecipe`. Replace `yourname` with your own identifier. If Xcode shows **Set Up Signing**, use that dialog to select the team and bundle ID instead.
4. In the toolbar, select the **RednoteOCR** scheme and your connected iPhone as the run destination. If Xcode offers **Register Device**, follow that step and wait for device preparation to finish.
5. Click **Run** or press **⌘R**. Keep the phone unlocked. When the build succeeds, Xcode installs and launches the app on your iPhone.

If signing fails, check the selected team and unique bundle ID. If the phone is unavailable, read its status in Device Hub and check that Xcode supports its iOS version. Apple's [device setup guide](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub) and [build and signing guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) explain these screens in more detail.

For a first try, import a clear recipe screenshot, review the extracted ingredients and steps, then save it. This does not need an API key or a Mac backend. Text-heavy images and subtitled videos work best with the local parser.

### Regenerate the project (optional)

The Xcode project is already included. You only need [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change `project.yml` and want to regenerate it:

```bash
xcodegen generate
```

Regenerating restores the settings in `project.yml`. If you want to keep your own bundle ID and signing team, update that file too or select them again in Xcode afterward.

### Optional: AI extraction

Enter your own OpenAI API key in the app's settings. The app sends selected images or video frames and the relevant text to the Responses API, then converts the response into an editable recipe. The key is stored in the device's Keychain.

API requests, including the connection check, may incur usage charges. Enter the key in the app; do not put a real key in `LocalSecrets.swift` or commit one to Git.

#### Model selection and request limits

**All AI calls currently use `gpt-5.4-nano`.** The model is hard-coded, and Settings lets you enter an API key but does not offer a model picker. The app does not automatically switch to another model after a failure.

| Request | Model | `max_output_tokens` |
| --- | --- | --- |
| Recipe extraction from text, images, or video frames | `gpt-5.4-nano` | 2,000 |
| Recipe title check | `gpt-5.4-nano` | 220 |
| Settings connection test | `gpt-5.4-nano` | 20 |

These output caps are values set by this app, not the model's maximum capacity or a total token budget for an import. Input text and images also contribute to usage. The API endpoint is fixed at `https://api.openai.com/v1/responses`; the backend URL setting only configures the Xiaohongshu adapter.

To change the model, edit `model` in [OpenAIRecipeEnhancer.swift](Sources/OpenAIRecipeEnhancer.swift) and `recipeModel` in [OpenAISettingsStore.swift](Sources/OpenAISettingsStore.swift), then rebuild. Update the model names shown in [OCRViewModel.swift](Sources/OCRViewModel.swift) and [OpenAISettingsView.swift](Sources/OpenAISettingsView.swift) as well.

A replacement must work with the existing Responses API requests, including [image inputs](https://developers.openai.com/api/docs/guides/images-vision) and [strict JSON-schema output](https://developers.openai.com/api/docs/guides/structured-outputs). Your API account must have access to it. Check the request parameters and token budgets when changing models; changing the name alone does not verify compatibility. The connection test sends only a short text request, so passing it does not test image extraction or structured output.

### Optional: Xiaohongshu link imports

Some posts need an authenticated browser session to load. For these, the app can use a small backend running on your Mac.

This integration uses [autoclaw-cc/xiaohongshu-skills](https://github.com/autoclaw-cc/xiaohongshu-skills), which provides the Chrome extension, WebSocket bridge, and CLI. Our Python adapter calls that CLI to retrieve posts; this setup does not require a separate MCP server.

```text
iPhone → Python adapter → browser bridge → Chrome logged in to Xiaohongshu
```

Follow [the backend setup guide](LocalBackend/README.md) to install its Python dependencies and Chrome extension. Then enter your Mac's backend address in the app's settings. Local image/video imports and manual recipes do not need the backend.

## How extraction works

For images, the app first looks for readable text. For videos, it samples frames and removes similar text frames. With an API key, it asks the model to organize the ingredients, quantities, steps, recipe sections, tips, and timing notes. A separate request checks the recipe title.

Without a key, or if AI extraction fails, the app can read text from images and video frames with Apple Vision OCR and parse it locally. Link imports first try the configured Mac backend and can fall back to fetching the public page. A public page may not contain everything visible in the logged-in app.

Video processing uses frames and visible text; there is no audio transcription. Always review the extracted quantities and steps before saving or cooking.

## Your data

Recipes, categories, and shopping lists are saved on your device as JSON files. There is no account system or cloud sync. Your API key stays in Keychain and is not included in backups.

When you use AI extraction, selected images, video frames, and relevant text are sent to OpenAI. Local OCR does not send that content to OpenAI. Link imports still need network access.

## Known limitations

- Xiaohongshu imports depend on the link format, available media, and browser login state. They are not guaranteed to work for every post.
- Videos without readable text may produce little useful content. A video download or frame-extraction failure can stop an import.
- The shopping list adds ingredients as separate entries; it does not combine quantities or convert units across recipes.
- Automatic backend discovery is disabled. Set the URL yourself and update it if your Mac's address changes.
- The Mac backend has no login protection or HTTPS encryption. Use it only on a trusted local network; do not expose it to the internet.

## Code layout

| Path | Purpose |
| --- | --- |
| `Sources/` | SwiftUI screens, import workflow, parsing, local storage, and settings |
| `Resources/` | App metadata and asset catalog |
| `skills/recipe-post-parser/` | Markdown prompts bundled with the app and loaded during AI extraction |
| `LocalBackend/` | Python adapter, service scripts, and the browser-bridge submodule |
| `Tests/` | Offline regression checks for recipe normalization and prompt loading |
| `project.yml` | XcodeGen project configuration |

The Markdown prompt files are app resources. You do not need to install an AI agent or a separate skill runner to use the app. The backend request and response format is documented in [LOCAL_BACKEND.md](LOCAL_BACKEND.md).

## Run the checks

On macOS with the Swift toolchain installed:

```bash
python3 Tests/run_recipe_regressions.py
python3 Tests/run_prompt_bundle_regressions.py
```

These check how recipe data and API responses are processed, and whether the bundled prompts load correctly. They run without API keys or a logged-in Xiaohongshu account. They do not test the UI, live AI requests, or authenticated link imports. The Xcode scheme currently has no XCTest targets.

## Third-party code

The optional backend uses [autoclaw-cc/xiaohongshu-skills](https://github.com/autoclaw-cc/xiaohongshu-skills) for its Chrome extension, browser bridge, and CLI. It is included as a pinned Git submodule and has its own [MIT license](https://github.com/autoclaw-cc/xiaohongshu-skills/blob/9d3055b2f45e166b9514af16020e9fd5163a43a4/LICENSE). The iOS app and Python adapter in this repository integrate with that project.

If you cloned without submodules, download it with:

```bash
git submodule update --init --recursive
```

GitHub's source ZIP does not include the submodule contents; use Git if you want to run the backend.
