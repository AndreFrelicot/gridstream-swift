#!/bin/sh
# Xcode "Stamp Git Commit" build phase (iPad app): writes the short git commit
# the app is built from into the built Info.plist (GridStreamCommit), shown in
# the server menu. "-dirty" marks uncommitted changes to tracked files; such a
# build also gets its build time, since the commit alone does not identify it.
set -eu

PLIST="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
COMMIT="$(git -C "${SRCROOT}" describe --always --dirty --exclude='*' 2>/dev/null || echo unknown)"
case "$COMMIT" in
    *-dirty) COMMIT="$COMMIT $(date '+%b %d %H:%M')" ;;
esac

plutil -replace GridStreamCommit -string "$COMMIT" "$PLIST"
