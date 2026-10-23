# RednoteRecipe

**English** | [简体中文](README.zh-CN.md)

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

You need a Mac with Xcode and an iPhone or simulator running iOS 17 or later. Finish Xcode's first-launch setup before building.

Clone the repository and open the project:

```bash
git clone --recurse-submodules https://github.com/hoshikuzu00/RednoteRecipe.git
cd RednoteRecipe
open RednoteOCR.xcodeproj
```

In Xcode:

1. Select the **RednoteOCR** scheme.
2. Choose an iPhone simulator.
3. Click **Run**.

For a physical iPhone, select your own development team under **Signing & Capabilities** and use a bundle identifier that your account can sign.

For a first try, import a clear recipe screenshot, review the extracted ingredients and steps, then save it. This does not need an API key or a Mac backend. Text-heavy images and subtitled videos work best with the local parser.

The generated Xcode project is included. If you change `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

### Optional: AI extraction

Enter your own OpenAI API key in the app's settings. The app sends selected images or video frames and the relevant text to the Responses API, then converts the response into an editable recipe. The key is stored in the device's Keychain.

API requests, including the connection check, may incur usage charges. Enter the key in the app; do not put a real key in `LocalSecrets.swift` or commit one to Git.

For developers: the configured model is `gpt-5.4-nano`, set in [OpenAIRecipeEnhancer.swift](Sources/OpenAIRecipeEnhancer.swift) and [OpenAISettingsStore.swift](Sources/OpenAISettingsStore.swift). Your API account needs access to that model.

### Optional: Xiaohongshu link imports

Some posts need an authenticated browser session to load. For these, the app can use a small backend running on your Mac:

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
