# Appify

> Turn any website into a macOS `.app` from the command line.

```bash
appify https://monochrome.tf "Monochrome"
# → Monochrome.app created in ~/Applications
```

**No dependencies.** No Electron. No Chromium. No Python. Uses macOS's native WKWebView — the same engine as Safari. Generated apps work on any Mac running macOS 13+.

---

## Install

```bash
git clone https://github.com/Djozman/Appify
cd Appify
chmod +x ./Scripts/install.sh
./Scripts/install.sh
```

**Requirements:**
- macOS 13+
- Xcode Command Line Tools: `xcode-select --install`

That's it.

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

Appify compiles two Swift binaries:

1. **Launcher** — a tiny native WKWebView app (~500KB). Reads config from environment variables. This binary gets embedded inside Appify at build time.

2. **Appify CLI** — the tool you run. Fetches favicon, builds the `.app` structure, stamps a copy of the Launcher binary into every app it creates.

```
Monochrome.app/
└── Contents/
    ├── Info.plist       ← Bundle metadata
    ├── PkgInfo
    ├── MacOS/
    │   ├── run          ← Wrapper: sets env vars, execs launcher
    │   └── launcher     ← Native Swift/WKWebView binary
    └── Resources/
        └── icon.icns    ← Auto-fetched from site favicon
```

Sessions are shared with Safari — you stay logged in on sites you've already authenticated.

---

## Development

```bash
# Full build (Launcher + Appify)
./Scripts/compile_and_run.sh

# Run directly
.build/release/Appify https://monochrome.tf "Monochrome"
```

No Xcode IDE needed. Works with Zed, VS Code, Neovim — any editor with `sourcekit-lsp`.

---

## Roadmap

- [x] Native WKWebView launcher (zero dependencies)
- [x] `--menu-bar` mode
- [x] Auto favicon fetch + `.icns` conversion
- [x] Custom icon support
- [ ] Homebrew tap
- [ ] `--inject-js` flag
- [ ] `--user-agent` override

---

## License

MIT
