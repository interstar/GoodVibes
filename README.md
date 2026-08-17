# Good Vibes

Good Vibes is a local-first Flutter desktop app for creating and running small
personal tools. It is aimed at non-technical users who want the practical feel of
having a folder of custom scripts, but presented as a simple app store of local
HTML/CSS/JS apps.

The generated tools are ordinary folders on disk. They can be copied, backed up,
edited by hand, or shared with someone else.

## What It Does

Good Vibes has three main areas:

- **Store**: shows installed local tools in a grid.
- **Vibe Studio**: a chat interface where the user describes a tool and an LLM
  generates it.
- **Settings**: stores AI profiles, secure API-key references, and the apps folder location.

Opening a tool launches it in a separate native webview window. On Linux this
uses WebKitGTK, on Windows WebView2, and on macOS WKWebView through
`desktop_webview_window`.

## How Local Apps Work

Apps live under:

```text
~/GoodVibes/apps/<app-id>/
```

Each app folder contains:

```text
manifest.json
index.html
optional assets, stylesheets, scripts, icons, etc.
```

The manifest shape is:

```json
{
  "id": "kebab-case-slug",
  "name": "Human readable name",
  "description": "Short summary",
  "version": "1.0.0",
  "icon": "icon.svg",
  "entry": "index.html"
}
```

Good Vibes starts a local HTTP server on `127.0.0.1` and serves the app folders
from there. This avoids `file://` browser restrictions and lets generated apps
use normal relative paths, JavaScript modules, assets, and `fetch` for local
files.

## Generated App Contract

The Vibe Studio tells the LLM to create self-contained apps:

- no CDNs
- no remote fonts or images
- no network requests
- relative paths only
- offline-friendly
- single-purpose
- complete `index.html` entry point

The preferred LLM output format is a line-oriented app block:

```text
<app>
id: pomodoro-timer
name: Pomodoro Timer
description: A simple focus timer.

=== FILE: index.html ===
<!DOCTYPE html>
<html>
...
</html>

=== FILE: styles.css ===
...
</app>
```

The parser also accepts a legacy JSON block and a bare HTML fallback.

## Architecture

```text
Flutter desktop app
  |
  |-- StoreScreen
  |     `-- AppCatalog scans ~/GoodVibes/apps
  |
  |-- VibeScreen
  |     |-- AppGenerator builds prompts, parses model output, writes files
  |     `-- LlmService streams responses through Xybrid
  |
  |-- SettingsScreen
  |     `-- SettingsService persists API key and apps directory
  |
  `-- LocalServer serves apps on 127.0.0.1
        `-- desktop_webview_window opens each app URL
```

## Requirements

This project targets Flutter desktop:

- Linux
- Windows
- macOS

The current local setup has been verified on Ubuntu 24.04.

Linux packages:

```bash
sudo apt update
sudo apt install -y \
  build-essential g++ g++-14 libstdc++-14-dev \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev \
  libwebkit2gtk-4.1-dev libsoup-3.0-dev \
  libsecret-1-0 libsecret-1-dev
```

Flutter:

```bash
sudo snap install flutter --classic
flutter config --enable-linux-desktop
flutter doctor -v
```

The Android toolchain is not required for this desktop app.

## Build

From this directory:

```bash
./build.sh
```

The script runs:

```bash
flutter pub get
flutter analyze
flutter test
flutter build linux --debug
```

The debug executable is written to:

```text
build/linux/x64/debug/bundle/good_vibes
```

Run it directly:

```bash
./build/linux/x64/debug/bundle/good_vibes
```

Or run through Flutter:

```bash
flutter run -d linux
```

## LLM Setup

Good Vibes uses `xybrid_flutter`.

Without an API key, Xybrid can use an on-device model. The first run may download
large model files, usually hundreds of megabytes to a few gigabytes.

With a Xybrid API key, the app can use cloud fallback for better code generation
quality. The Settings tab also supports OpenAI-compatible cloud profiles such as
Together AI, DeepSeek, OpenAI, or a custom endpoint. API keys are stored with the
platform secure store (libsecret on Linux, Keychain on macOS, Credential Manager
on Windows).

## Project Layout

```text
lib/main.dart                  startup and service wiring
lib/app.dart                   Flutter app shell and tab navigation
lib/screens/store_screen.dart  installed app grid
lib/screens/vibe_screen.dart   chat-based app generation
lib/screens/settings_screen.dart
lib/screens/app_window.dart    native webview launcher
lib/services/app_catalog.dart  app scanning and sample seeding
lib/services/app_generator.dart
lib/services/local_server.dart
lib/services/llm_service.dart
lib/services/settings_service.dart
assets/samples/hello-world/    bundled first-run sample app
test/                          parser/unit tests
integration_test/              live LLM integration test
```

## Useful Commands

```bash
flutter analyze
flutter test
flutter build linux --debug
flutter test integration_test/llm_live_test.dart -d linux
```

The live integration test may trigger model downloads and can take a long time on
first run.

## Notes

- Generated apps are local HTML/JS/CSS and should be treated as user-owned files.
- Apps are served locally, but there is no strong sandbox beyond the webview.
- `desktop_webview_window` opens apps in separate native windows rather than an
  embedded widget inside the main Flutter UI.
- `xybrid_flutter` is new, so its API and behavior may change.
