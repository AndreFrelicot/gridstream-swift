#!/bin/bash
# Xcode "Embed Web UI" build phase: rebuilds the Angular bundle when the web
# sources changed since the last build, then copies it into the app bundle.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WEB_DIR="$REPO_DIR/gridstream-web"
BUNDLE_DIR="$REPO_DIR/gridstream-macos/Public/browser"
INDEX="$BUNDLE_DIR/index.html"

needs_build() {
    [ ! -f "$INDEX" ] && return 0
    [ -n "$(find "$WEB_DIR" \( -name node_modules -o -name .angular -o -name dist \) -prune \
        -o -type f -newer "$INDEX" -print -quit)" ]
}

# Xcode runs build phases with a minimal PATH: fall back to the login shell's.
find_npm() {
    command -v npm 2>/dev/null && return
    "${SHELL:-/bin/zsh}" -lic 'command -v npm' 2>/dev/null | tail -n 1
}

if needs_build; then
    NPM="$(find_npm || true)"
    if [ -x "$NPM" ]; then
        export PATH="$(dirname "$NPM"):$PATH"
        cd "$WEB_DIR"
        if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
            echo "Installing web dependencies..."
            npm ci
        fi
        echo "Building the web UI..."
        npx ng build --configuration production
    elif [ -f "$INDEX" ]; then
        echo "warning: npm not found; embedding a web UI older than its sources. Run scripts/build-web.sh to rebuild it."
    fi
fi

if [ -f "$INDEX" ]; then
    DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/Public"
    mkdir -p "$DEST"
    rsync -a --delete "$BUNDLE_DIR/" "$DEST/browser/"
else
    echo "warning: Web UI not embedded: npm not found. Install Node.js or run scripts/build-web.sh."
fi
