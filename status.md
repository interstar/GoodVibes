# Good Vibes — Project Status

## What we are building

A local-first **Flutter desktop app** (Linux, Windows, macOS) that gives non-technical
users the experience of a Unix user who keeps a bunch of custom scripts in their `~/bin` —
but as an **app store** of self-contained HTML/CSS/JS tools.

Two core ideas:

1. **App Store** — the user opens the app and sees a grid of installed tools. Tapping one
   opens it in an **embedded browser window** (WebKitGTK on Linux, WebView2 on Windows,
   WKWebView on macOS via `desktop_webview_window`).
2. **Vibe Studio** — a chat screen where the user describes an app in plain language and
   an **LLM (via Xybrid)** generates it. The result is written to the user's apps folder
   and appears in the store. The LLM is given a system prompt describing the app structure
   so every generated tool follows the same contract.

The "apps" are plain folders on disk under `~/GoodVibes/apps/<app-id>/`, each containing a
`manifest.json` and an `index.html` (plus optional assets). Nothing is proprietary — a user
(or a power-user friend) can hand-edit or copy these folders.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│ Flutter app (good_vibes) — Linux / Windows / macOS        │
│                                                            │
│  Store tab   Vibe Studio tab   Settings tab                │
│     │              │                │                      │
│     ▼              ▼                ▼                      │
│  AppCatalog ──▶ LocalServer ──▶ embedded browser window    │
│  (scans/       (HTTP on         (desktop_webview_window)   │
│   seeds)        127.0.0.1)                                 │
│                          │                                 │
│                    AppGenerator  ◀─── LlmService ── Xybrid │
│                    (parse+write)    (streaming chat)       │
└────────────────────────────────────────────────────────────┘
                          │
              ~/GoodVibes/apps/<app-id>/ { manifest.json, index.html, … }
```

Key decisions (confirmed with the user):

- **Embedded WebKit window** for running apps, with native browser-style title bar.
- **Xybrid routing: auto with cloud fallback** — on-device when possible, cloud gateway for
  higher-quality code generation. Requires an optional Xybrid API key (free at
  dashboard.xybrid.dev), entered in Settings.
- **User directory, auto-created** at `~/GoodVibes/apps` (configurable in Settings).
- **Platforms: Linux + Windows + macOS.**

### The app contract (what the LLM is told)

Each app is a folder containing:

- `manifest.json` — `{ "id", "name", "description", "version", "icon"?, "entry" }`
- `index.html` — the self-contained entry point (optional `styles.css`, `script.js`, assets)

Rules in the system prompt: fully self-contained (no CDNs/network), relative paths,
offline-friendly, single-purpose, light/dark-friendly where sensible.

The LLM must reply with a single `` ```json `` block:

```json
{
  "id": "kebab-case-slug",
  "name": "Human name",
  "description": "Short summary",
  "files": { "index.html": "...", "styles.css": "..." }
}
```

The app parses this, validates the slug, writes the files + manifest, and refreshes the store.

## Progress

| # | Task | Status |
|---|------|--------|
| 1 | Flutter scaffold (linux/windows/macos) + deps | ✅ Done |
| 2 | Manifest model, AppCatalog, SettingsService | ✅ Done |
| 3 | Local HTTP server (serves apps on 127.0.0.1) | ✅ Done |
| 4 | LLM service (Xybrid) + system prompt + app generator | ✅ Done |
| 5 | Store screen + embedded webview launcher | ✅ Done |
| 6 | Vibe Studio chat screen (streaming, ref app, retry) | ✅ Done |
| 7 | Settings screen (API key, apps folder) | ✅ Done |
| 8 | Sample "Hello, World" app + first-run seeding | ✅ Done |
| 9 | `flutter analyze` clean + unit tests passing | ✅ Done |
| 10 | Linux debug build | ✅ Done |
| 11 | Launch + Store + local server verified on Linux | ✅ Done |
| 12 | Vibe Studio end-to-end (live LLM generation) | ✅ Done |

### What works

- `flutter analyze` — **0 issues**
- `flutter test` — **8/8 passing** (AppGenerator parsing for both output formats)
- `flutter build linux --debug` — **builds successfully**
- App launches on Linux; first-run seeding creates `~/GoodVibes/apps/hello-world/`
- **Local HTTP server verified live**: `index.html`, `icon.svg`, `manifest.json` all serve
  200 from the running app; path-traversal requests are rejected (404)
- **Xybrid loads cleanly** at startup (no native-library init errors in the app log)
- **Live LLM e2e passed** (integration test on Linux, on-device model `llama-3.2-1b`, no API
  key): Xybrid init → model load → streaming chat with the real system prompt → generated
  app parsed and installed to disk (`pomodoro-timer` with `manifest.json`/`index.html`/
  `styles.css`). Exercise with:
  `flutter test integration_test/llm_live_test.dart -d linux`
- **Vibe Studio now shows model-download progress** ("Downloading model… 45%") instead of a
  silent wait on first on-device use.

### Design change made during verification

The initial plan had the LLM reply with a `` ```json `` block. Live testing showed on-device
models emit **invalid JSON** (unescaped newlines) and often omit `index.html`. The output
contract was switched to a **line-oriented fenced-file format** that cannot break on escaping:

```
<app>
id: pomodoro-timer
name: Pomodoro Timer
description: A focus timer.

=== FILE: index.html ===
<!DOCTYPE html>
...

=== FILE: styles.css ===
...
</app>
```

The parser accepts three formats, in order: the `<app>` block, a legacy ```json block (for
cloud models), and a bare-HTML rescue (wraps the whole reply as `index.html`).

### What remains

- The default on-device model `qwen3.5-2b` is only partially downloaded (~100 MB of
  ~1.3 GB, interrupted). First use with no API key will finish the download automatically
  (progress is now shown in the UI). Optionally resume it now, or set a Xybrid API key for
  cloud routing instead.
- Windows/macOS builds not yet attempted (need their toolchains; code is platform-agnostic).

## How to run

```bash
flutter pub get
flutter build linux --debug        # or: flutter run -d linux
./build/linux/x64/debug/bundle/good_vibes
```

Linux prerequisites: `libwebkit2gtk-4.1-dev` and `libsoup-3.0-dev` (already installed here).
First build pulls Xybrid's precompiled Rust/ONNX binaries via cargokit (network needed).

## Notes / risks

- `xybrid_flutter` 0.5.0 is very new (published days ago); API may shift.
- `desktop_webview_window` opens a separate native window (not an in-widget view) — matches the
  "runs as a browser" feel.
- Small on-device models are weak at multi-file code generation; the cloud fallback (auto
  routing) is the intended path for quality. Without an API key, generation uses the on-device
  model only.
- On-device model downloads are large (~0.5–2 GB), cached by Xybrid.
- Apps run locally and untrusted-ish — generated apps are plain HTML/JS in the user's own
  folder; no sandboxing beyond "run it in the webview" for now.
