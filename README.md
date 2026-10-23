# RednoteRecipe

Turn recipe screenshots, videos, and Xiaohongshu (Rednote) links into recipes you can edit and cook from.

Recipes saved from social media often spread the ingredients and instructions across captions, images, and video subtitles. RednoteRecipe brings that information into one place: an ingredient list, cooking steps, and any notes or recipe sections. You can review the result before saving it, check off steps while cooking, and add ingredients to a shopping list.

This is a personal iOS project built with SwiftUI. The Xcode project and app target are still named `RednoteOCR`.

## What you can do

- Import images or videos from Photos or Files, paste a shared link, or enter a recipe by hand.
- Extract recipe details with an optional OpenAI API key. Without a key, local image and video imports use Apple's on-device text recognition and a rule-based parser.
- Edit recipes, assign categories, search the library, rate dishes, and keep track of completed steps.
- Add ingredients to a shopping checklist that stays saved between app launches.
- Export recipes, categories, and shopping items as a JSON backup. When importing a backup, review recipes with matching titles and choose whether to replace them or keep both.

## Run the app

You need a Mac with Xcode and an iPhone or simulator running iOS 17 or later. Finish Xcode's first-launch setup before building.

```bash
git clone --recurse-submodules https://github.com/hoshikuzu00/RednoteRecipe.git
cd RednoteRecipe
open RednoteOCR.xcodeproj
```

In Xcode, select the **RednoteOCR** scheme, choose an iPhone simulator, and run. For a physical iPhone, choose your own development team under **Signing & Capabilities** and use a bundle identifier that your account can sign.

The generated Xcode project is included. If you change `project.yml`, regenerate it with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

To try the app without configuring any services, import a clear recipe screenshot, review the extracted ingredients and steps, then save it. Text-heavy images and subtitled videos work best with the local parser.

### Optional: AI extraction

Enter your own OpenAI API key in the app's settings. The app sends selected images or video frames and the relevant text to the Responses API, then converts the response into an editable recipe. The key is stored in the device's Keychain.

The source currently selects `gpt-5.4-nano` in `OpenAIRecipeEnhancer.swift` and `OpenAISettingsStore.swift`. Your API account needs access to the configured model. API requests, including the connection check, may incur usage charges. Do not put a real key in `LocalSecrets.swift` or commit one to Git.

### Optional: Xiaohongshu link imports

Some posts need an authenticated browser session to load. For these, the app can use a small backend running on your Mac:

```text
iPhone → Python adapter → browser bridge → Chrome logged in to Xiaohongshu
```

Follow [the backend setup guide](LocalBackend/README.md) to install its Python dependencies and Chrome extension. Then enter your Mac's backend address in the app's settings. The backend is optional for local image/video imports and manual recipes.

## How extraction works

For images, the app first looks for readable text. For videos, it samples frames and filters similar text frames. With an API key, it asks the model to return ingredients, quantities, steps, sections, tips, and time hints in a defined JSON structure. It also makes a separate pass to check the recipe title.

Without a key, or when an AI extraction request fails, the image/frame workflow can use Vision OCR and local parsing. Link imports first try the configured Mac backend and can fall back to fetching the public page. A public page may not contain everything visible in the logged-in app.

Video processing uses frames and visible text; there is no audio transcription. Always review the extracted quantities and steps before saving or cooking.

## Data and current limitations

Recipes, categories, and shopping lists are saved as JSON files in the app's local storage. There is no account system or cloud sync. Backups do not include your API key. AI extraction sends the selected source content to OpenAI; local OCR does not require that request. Link imports still need network access.

A few boundaries matter when trying the app:

- Xiaohongshu imports depend on the link format, available media, and browser login state. They are not guaranteed to work for every post.
- Videos without readable text may produce little useful content. A video download or frame-extraction failure can stop an import.
- The shopping list appends ingredients; it does not combine quantities or convert units across recipes.
- Automatic backend discovery is disabled. Set the URL yourself and update it if your Mac's address changes.
- The Mac adapter has no authentication or TLS. It is intended for a trusted local network, not a public server.

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

## Checks

On macOS with the Swift toolchain installed:

```bash
python3 Tests/run_recipe_regressions.py
python3 Tests/run_prompt_bundle_regressions.py
```

These check recipe normalization, response parsing, and loading prompts from a bundle. They run without API keys or a logged-in Xiaohongshu account. They do not test the UI, live AI requests, or authenticated link imports. The Xcode scheme currently has no XCTest targets.

## Third-party code

The optional backend uses [autoclaw-cc/xiaohongshu-skills](https://github.com/autoclaw-cc/xiaohongshu-skills) for its Chrome extension, browser bridge, and CLI. It is included as a pinned Git submodule and has its own [MIT license](LocalBackend/xiaohongshu-skills/LICENSE). The iOS app and Python adapter in this repository integrate with that project.

If you cloned without submodules, download it with:

```bash
git submodule update --init --recursive
```

GitHub's source ZIP does not include the submodule contents; use Git if you want to run the backend.
