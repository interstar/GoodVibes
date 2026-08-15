# UI Refactor: Integrated App Editing

## What We Want

Good Vibes should eventually make running and editing an app feel like one
continuous workspace.

The desired flow:

- Opening an app shows the app full-width in the window.
- A small edit button appears in the top-right corner.
- Clicking edit changes the window into a split view:
  - left: app-specific chat transcript for editing
  - right: live app preview
- The user asks the local AI to update the app.
- The AI modifies the app files on disk.
- The preview reloads automatically as code changes are written.
- Clicking into the app preview returns it to full-window mode.

This would turn Good Vibes from a generate-then-run tool into an iterative
run-inspect-edit-reload environment.

## Why We Are Not Doing It Today

The current app preview uses `desktop_webview_window`. That package opens a
separate native webview window. It is not a normal Flutter widget that can be
placed inside a `Row`, `SplitView`, or other shared Flutter layout next to the
chat panel.

Current shape:

```dart
final webview = await WebviewWindow.create();
webview.launch(url);
```

Desired shape:

```dart
Row(
  children: [
    ChatPanel(...),
    Expanded(child: EmbeddedWebView(url: appUrl)),
  ],
)
```

The desired shape requires an embeddable webview inside the Flutter widget
tree.

## Platform Status

- macOS: official `webview_flutter` supports an embedded `WebViewWidget` via
  WKWebView.
- Windows: likely feasible with a third-party WebView2 package such as
  `webview_flutter_windows`, which renders into the Flutter widget tree.
- Linux: the hard case. There is no official Linux implementation for
  `webview_flutter`. Available packages are either separate-window based or use
  native overlay approaches with focus, clipping, and stacking limitations.

Because Linux is the currently verified development target for this project,
the integrated split editor should start as a technical spike rather than a
direct product refactor.

## Likely Future Work

- Build a small branch/prototype with an app-scoped editor screen.
- Test a real embedded preview on Linux first.
- Decide whether the edit button can be an overlay or must live in a reserved
  Flutter toolbar outside the webview.
- Add an edit-mode AI prompt that reads existing app files and returns full
  replacement files or a constrained patch format.
- Add file watching or explicit reload after writes.
- Use cache-busted app URLs when reloading generated files.
