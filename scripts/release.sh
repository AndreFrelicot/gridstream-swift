#!/bin/bash
set -e

# GridStream macOS Server Release Script
# Builds, signs, notarizes, and optionally publishes to GitHub

# Configuration
APP_NAME="GridStream"
SCHEME="gridstream-macos"
PROJECT="gridstream-macos/gridstream-macos.xcodeproj"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOCAL_XCCONFIG="$PROJECT_ROOT/gridstream-macos/Config/Local.xcconfig"

# Signing team: environment first, then the git-ignored Local.xcconfig.
read_xcconfig() {
    [ -f "$LOCAL_XCCONFIG" ] && sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$LOCAL_XCCONFIG" | tail -1
}
TEAM_ID="${TEAM_ID:-$(read_xcconfig DEVELOPMENT_TEAM)}"
# Name of a notarytool keychain profile created once with:
#   xcrun notarytool store-credentials gridstream-notary --apple-id <id> --team-id <team>
NOTARY_PROFILE="${NOTARY_PROFILE:-gridstream-notary}"
# Its own folder: the script empties it, and build/ holds other work (demo pack, other builds).
BUILD_DIR="$PROJECT_ROOT/build/release"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "\n${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Parse arguments
VERSION=""
PUBLISH=false
DRAFT=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -p|--publish)
            PUBLISH=true
            shift
            ;;
        -d|--draft)
            DRAFT=true
            PUBLISH=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -v, --version VERSION   Version tag (e.g., v1.0.0)"
            echo "  -p, --publish           Publish release to GitHub"
            echo "  -d, --draft             Create as draft release (implies --publish)"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      Build and notarize only"
            echo "  $0 -v v1.0.0 -p         Build, notarize, and publish to GitHub"
            echo "  $0 -v v1.0.0 -d         Build, notarize, and create draft release"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate version if publishing
if $PUBLISH && [ -z "$VERSION" ]; then
    print_error "Version is required when publishing. Use -v/--version"
    exit 1
fi

if [ -z "$TEAM_ID" ]; then
    print_error "No signing team. Set TEAM_ID or DEVELOPMENT_TEAM in gridstream-macos/Config/Local.xcconfig"
    exit 1
fi

# Check for required credentials
check_notarization_credentials() {
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        print_warning "Notarization keychain profile '$NOTARY_PROFILE' not found."
        echo "Create it once with:"
        echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple-id> --team-id $TEAM_ID"
        echo ""
        read -p "Continue without notarization? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return 1
    fi
    return 0
}

# Clean build directory
print_step "Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build the web UI so the archive embeds it (Embed Web UI build phase)
print_step "Building web UI..."
"$SCRIPT_DIR/build-web.sh"

# Build and archive
print_step "Building and archiving $APP_NAME..."
cd "$PROJECT_ROOT"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -IDEBuildLocationStyle=DeriveData \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID"

if [ ! -d "$ARCHIVE_PATH" ]; then
    print_error "Archive failed - no archive created"
    exit 1
fi

print_step "Archive created at $ARCHIVE_PATH"

# Create export options plist
print_step "Creating export options..."
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

# Export archive
print_step "Exporting archive with Developer ID signing..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

if [ ! -d "$APP_PATH" ]; then
    print_error "Export failed - no app bundle created"
    exit 1
fi

print_step "App exported to $APP_PATH"

if [ ! -f "$APP_PATH/Contents/Resources/Public/browser/index.html" ]; then
    print_error "Web UI missing from the app bundle (Contents/Resources/Public/browser)"
    exit 1
fi

# Verify code signing
print_step "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo ""
codesign -dv "$APP_PATH" 2>&1 | grep -E "^(Authority|TeamIdentifier)"

# Create zip for notarization
print_step "Creating zip archive..."
cd "$EXPORT_PATH"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
print_step "Zip created at $ZIP_PATH"

# Notarization
NOTARIZED=false
if check_notarization_credentials; then
    NOTARIZED=true
    print_step "Submitting for notarization..."
    echo "This may take a few minutes..."

    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    print_step "Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    # Recreate zip with stapled app
    print_step "Recreating zip with stapled app..."
    rm "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"

    print_step "Notarization complete!"
else
    print_warning "Skipping notarization"
fi

# Verify final app
print_step "Verifying final app..."
spctl --assess --type execute --verbose=2 "$APP_PATH" 2>&1 || print_warning "Gatekeeper assessment requires notarization"

# Disk image: the app next to an alias of /Applications, to drag it across
print_step "Creating disk image..."
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$BUILD_DIR/$APP_NAME-$APP_VERSION.dmg"
DMG_STAGING="$BUILD_DIR/dmg"
mkdir -p "$DMG_STAGING"
ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -fs HFS+ -format UDZO -ov "$DMG_PATH"

SIGNING_IDENTITY=$(codesign -dvv "$APP_PATH" 2>&1 | sed -n 's/^Authority=\(Developer ID Application: .*\)$/\1/p' | head -1)
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

if $NOTARIZED; then
    print_step "Submitting the disk image for notarization..."
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    xcrun stapler staple "$DMG_PATH"
fi
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH" 2>&1 || print_warning "Gatekeeper assessment requires notarization"

echo ""
echo "Build artifacts:"
echo "  App:  $APP_PATH"
echo "  Zip:  $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"
echo "  DMG:  $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# Publish to GitHub
if $PUBLISH; then
    print_step "Publishing to GitHub..."

    # Check if gh is installed
    if ! command -v gh &> /dev/null; then
        print_error "GitHub CLI (gh) is not installed. Install with: brew install gh"
        exit 1
    fi

    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        print_error "Not authenticated with GitHub. Run: gh auth login"
        exit 1
    fi

    cd "$PROJECT_ROOT"

    RELEASE_NOTES="## $APP_NAME $VERSION

### Download
- **$APP_NAME-$APP_VERSION.dmg** - macOS app (signed and notarized)

### Installation
1. Download the disk image and open it
2. Drag GridStream to the Applications folder

### Requirements
- macOS 15.6 or later
"

    if $DRAFT; then
        print_step "Creating draft release $VERSION..."
        gh release create "$VERSION" "$DMG_PATH" \
            --title "$APP_NAME $VERSION" \
            --notes "$RELEASE_NOTES" \
            --draft
        echo ""
        echo "Draft release created. Review and publish at:"
        gh release view "$VERSION" --json url -q .url
    else
        print_step "Creating release $VERSION..."
        gh release create "$VERSION" "$DMG_PATH" \
            --title "$APP_NAME $VERSION" \
            --notes "$RELEASE_NOTES"
        echo ""
        echo "Release published:"
        gh release view "$VERSION" --json url -q .url
    fi
fi

print_step "Done!"
