# Appify

> Turn any website into a macOS `.app` from the command line.

```bash
appify https://monochrome.tf "Monochrome"
# → Monochrome.app created in ~/Applications
```

No Xcode IDE. No Electron. No Chromium. Uses native WKWebView — the same engine as Safari.

---

## Install

```bash
git clone https://github.com/Djozman/Appify
cd Appify
./Scripts/install.sh
```

**Requirements:**
- macOS 13+
- Xcode Command Line Tools: `xcode-select --install`
- pywebview (runtime dep for generated apps): `pip install pywebview`

---

## Usage

```
appify <url> <name> [options]
```

| Option | Default | Description |
|---|---|---|
| `--width <int>` | `1280` | Default window width |
| `--height <int>` | `800` | Default window height |
| `--icon <path>` | auto | `.png` or `.icns` icon |
| `--output <path>` | `~/Applications` | Where to save the `.app` |
| `--no-favicon` | off | Skip favicon auto-fetch |
| `--menu-bar` | off | Run as menu bar app (no Dock icon) |

### Examples

```bash
appify https://monochrome.tf "Monochrome"
appify https://notion.so "Notion" --width 1200 --height 900
appify https://reddit.com "Reddit" --icon ~/Downloads/reddit.png
appify https://linear.app "Linear" --menu-bar
appify https://chat.openai.com "ChatGPT" --output ~/Desktop
```

---

## How it works

Appify builds a standard macOS `.app` bundle:

```
Monochrome.app/
└── Contents/
    ├── Info.plist       ← Bundle metadata (name, ID, icon)
    ├── PkgInfo
    ├── MacOS/
    │   └── launcher     ← Shell script that starts pywebview
    └── Resources/
        └── icon.icns    ← Auto-fetched from site favicon
```

The launcher uses **pywebview**, which wraps macOS's native **WKWebView**. No Electron, no Chromium. Sessions are shared with Safari — you stay logged in automatically.

---

## Development

```bash
# Build
swift build

# Build release
swift build -c release

# Run directly
.build/release/Appify https://monochrome.tf "Monochrome"

# Dev loop
./Scripts/compile_and_run.sh
```

No Xcode IDE needed. Works with Zed, VS Code, Neovim — any editor with `sourcekit-lsp`.

---

## Roadmap

- [x] `--menu-bar` mode
- [x] Auto favicon fetch + `.icns` conversion  
- [x] Custom icon support
- [ ] Native Swift WKWebView launcher (remove pywebview dependency)
- [ ] `--inject-js` flag for custom JS at startup
- [ ] Homebrew tap
- [ ] `--user-agent` override

---

## License

MIT
