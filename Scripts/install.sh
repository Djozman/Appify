#!/bin/bash
# Build both targets and install appify to ~/bin (no sudo needed)
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Building Launcher binary..."
swift build -c release --product Launcher

echo "Embedding Launcher into Appify resources..."
mkdir -p Sources/Appify/Resources
cp .build/release/Launcher Sources/Appify/Resources/Launcher

echo "Building Appify CLI..."
swift build -c release --product Appify

# Install to ~/bin if it exists or can be created, no sudo required
USER_BIN="$HOME/.local/bin"
mkdir -p "$USER_BIN"

if cp .build/release/Appify "$USER_BIN/appify" 2>/dev/null; then
    chmod +x "$USER_BIN/appify"
    INSTALL_PATH="$USER_BIN/appify"
    # Remind user to add ~/.local/bin to PATH if not already there
    if ! echo "$PATH" | grep -q "$USER_BIN"; then
        echo ""
        echo "  Note: Add this to your shell profile (~/.zshrc or ~/.bash_profile):"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo "  Then run: source ~/.zshrc"
    fi
else
    # Fallback: /usr/local/bin requires sudo
    INSTALL_PATH="/usr/local/bin/appify"
    echo "Installing to $INSTALL_PATH (requires password)..."
    sudo cp .build/release/Appify "$INSTALL_PATH"
    sudo chmod +x "$INSTALL_PATH"
fi

echo ""
echo "✓ Installed to $INSTALL_PATH"
echo ""
echo "Turn any website into a macOS app:"
echo "  appify <url>"
echo ""
echo "Examples:"
echo "  appify https://notion.so"
echo "  appify https://linear.app"
echo "  appify https://reddit.com"
