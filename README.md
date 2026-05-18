# Appify

> Turn any website into a macOS `.app` from the command line.

```bash
appify https://monochrome.tf
```

A native setup UI appears — confirm the name, preview the auto-fetched favicon, choose a custom icon if you want, then click **Create App**. Done. The app is in `/Applications`.

**No dependencies.** No Electron. No Chromium. No Python. Uses macOS's native WKWebView.

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

---

## Usage

```bash
appify <url> [name] [options]
```

Running `appify` opens a setup window where you can:
- Edit the URL and app name
- See the auto-fetched favicon as the app icon
- Choose a custom `.png` or `.icns` icon instead
- Set window size
- Toggle menu bar mode

| Option | Default | Description |
|---|---|---|
| `--width <int>` | `1280` | Default window width |
| `--height <int>` | `800` | Default window height |
| `--icon <path>` | auto | Pre-fill icon (`.png` or `.icns`) |
| `--output <path>` | `/Applications` | Where to save the `.app` |
| `--no-favicon` | off | Skip favicon auto-fetch |
| `--menu-bar` | off | Pre-check menu bar mode |

---

## How it works

```
Monochrome.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   ├── run          <- Wrapper: sets env vars, execs launcher
    │   └── launcher     <- Native Swift/WKWebView binary
    └── Resources/
        └── icon.icns    <- Auto-fetched or custom
```

Sessions are shared with Safari — you stay logged in.

---

## License

MIT
