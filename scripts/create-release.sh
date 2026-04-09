#!/bin/bash
# Create a release: notarize, create DMG, sign for Sparkle, upload to GitHub, prepare GitHub Pages appcast
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
EXPORT_PATH="$BUILD_DIR/export"
RELEASE_DIR="$PROJECT_DIR/releases"
KEYS_DIR="$PROJECT_DIR/.sparkle-keys"

# GitHub repository (owner/repo format)
GITHUB_REPO="javen-yan/agent-island"

PAGES_OUTPUT_DIR="${AGENT_ISLAND_PAGES_DIR:-$BUILD_DIR/pages}"
PREPARE_GITHUB_APPCAST_SCRIPT="$PROJECT_DIR/scripts/prepare-github-appcast.sh"

APP_PATH="$EXPORT_PATH/Agent Island.app"
APP_NAME="AgentIsland"
KEYCHAIN_PROFILE="AgentIsland"

echo "=== Creating Release ==="
echo ""

# Check if app exists
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

# Get version from app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")

echo "Version: $VERSION (build $BUILD)"
echo ""

mkdir -p "$RELEASE_DIR"

# ============================================
# Step 1: Notarize the app
# ============================================
echo "=== Step 1: Notarizing ==="

# Check if keychain profile exists
if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" &>/dev/null; then
    echo ""
    echo "No keychain profile found. Set up credentials with:"
    echo ""
    echo "  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
    echo "      --apple-id \"your@email.com\" \\"
    echo "      --team-id \"2DKS5U9LV4\" \\"
    echo "      --password \"xxxx-xxxx-xxxx-xxxx\""
    echo ""
    echo "Create an app-specific password at: https://appleid.apple.com"
    echo ""
    read -p "Skip notarization for now? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
    SKIP_NOTARIZATION=true
    echo "WARNING: Skipping notarization. Users will see Gatekeeper warnings!"
else
    # Create zip for notarization
    ZIP_PATH="$BUILD_DIR/$APP_NAME-$VERSION.zip"
    echo "Creating zip for notarization..."
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"

    rm "$ZIP_PATH"
    echo "Notarization complete!"
fi

echo ""

# ============================================
# Step 2: Create DMG
# ============================================
echo "=== Step 2: Creating DMG ==="

DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
DMG_STAGING_DIR="$BUILD_DIR/dmg-staging"

# Remove existing DMG if present
if [ -f "$DMG_PATH" ]; then
    echo "Removing existing DMG..."
    rm -f "$DMG_PATH"
fi

rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_PATH" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
cat > "$DMG_STAGING_DIR/README.txt" <<'EOF'
AgentIsland Installation Notes

If macOS says the app cannot be opened, run:

xattr -cr "/Applications/Agent Island.app"
EOF

# Check if create-dmg is available (prettier DMG)
if command -v create-dmg &> /dev/null; then
    echo "Using create-dmg for prettier output..."
    create-dmg \
        --volname "AgentIsland" \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "Agent Island.app" 150 200 \
        --app-drop-link 450 200 \
        --hide-extension "Agent Island.app" \
        "$DMG_PATH" \
        "$DMG_STAGING_DIR"
else
    echo "Using hdiutil (install create-dmg for prettier DMG: brew install create-dmg)"
    hdiutil create -volname "AgentIsland" \
        -srcfolder "$DMG_STAGING_DIR" \
        -ov -format UDZO \
        "$DMG_PATH"
fi

echo "DMG created: $DMG_PATH"
echo ""

# ============================================
# Step 3: Notarize the DMG
# ============================================
if [ -z "$SKIP_NOTARIZATION" ]; then
    echo "=== Step 3: Notarizing DMG ==="

    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait

    xcrun stapler staple "$DMG_PATH"
    echo "DMG notarized!"
    echo ""
fi

# ============================================
# Step 4: Sign for Sparkle and generate appcast
# ============================================
echo "=== Step 4: Signing for Sparkle ==="

# Find Sparkle tools
SPARKLE_SIGN=""
GENERATE_APPCAST=""

POSSIBLE_PATHS=(
    "$HOME/Library/Developer/Xcode/DerivedData/AgentIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin"
)

for path_pattern in "${POSSIBLE_PATHS[@]}"; do
    for path in $path_pattern; do
        if [ -x "$path/sign_update" ]; then
            SPARKLE_SIGN="$path/sign_update"
            GENERATE_APPCAST="$path/generate_appcast"
            break 2
        fi
    done
done

if [ -z "$SPARKLE_SIGN" ]; then
    echo "WARNING: Could not find Sparkle tools."
    echo "Build the project in Xcode first to download Sparkle package."
    echo ""
    echo "Skipping Sparkle signing. You'll need to manually:"
    echo "1. Sign the DMG with sign_update"
    echo "2. Generate appcast with generate_appcast"
else
    # Check for private key
    if [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
        echo "WARNING: No private key found at $KEYS_DIR/eddsa_private_key"
        echo "Run ./scripts/generate-keys.sh first"
        echo ""
        echo "Skipping Sparkle signing."
    else
        # Generate signature
        echo "Signing DMG for Sparkle..."
        SIGNATURE=$("$SPARKLE_SIGN" --ed-key-file "$KEYS_DIR/eddsa_private_key" "$DMG_PATH")

        echo ""
        echo "Sparkle signature:"
        echo "$SIGNATURE"
        echo ""

        # Generate/update appcast
        echo "Generating appcast..."
        APPCAST_DIR="$RELEASE_DIR/appcast"
        mkdir -p "$APPCAST_DIR"

        # Copy DMG to appcast directory
        cp "$DMG_PATH" "$APPCAST_DIR/"

        # Generate appcast.xml
        "$GENERATE_APPCAST" --ed-key-file "$KEYS_DIR/eddsa_private_key" "$APPCAST_DIR"

        echo "Appcast generated at: $APPCAST_DIR/appcast.xml"
    fi
fi

echo ""

# ============================================
# Step 5: Create GitHub Release
# ============================================
echo "=== Step 5: Creating GitHub Release ==="

if ! command -v gh &> /dev/null; then
    echo "WARNING: gh CLI not found. Install with: brew install gh"
    echo "Skipping GitHub release."
else
    # Check if release already exists
    if gh release view "v$VERSION" --repo "$GITHUB_REPO" &>/dev/null; then
        echo "Release v$VERSION already exists. Updating..."
        gh release upload "v$VERSION" "$DMG_PATH" --repo "$GITHUB_REPO" --clobber
    else
        echo "Creating release v$VERSION..."
        gh release create "v$VERSION" "$DMG_PATH" \
            --repo "$GITHUB_REPO" \
            --title "AgentIsland v$VERSION" \
            --notes "## AgentIsland v$VERSION

### Installation
1. Download \`$APP_NAME-$VERSION.dmg\`
2. Open the DMG and drag AgentIsland to Applications
3. Launch AgentIsland from Applications

### Auto-updates
After installation, AgentIsland will automatically check for updates."
    fi

    GITHUB_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$VERSION/$APP_NAME-$VERSION.dmg"
    echo "GitHub release created: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
    echo "Download URL: $GITHUB_DOWNLOAD_URL"
fi

echo ""

# ============================================
# Step 6: Prepare GitHub Pages appcast payload
# ============================================
echo "=== Step 6: Preparing GitHub Pages Payload ==="

if [ -z "$GITHUB_DOWNLOAD_URL" ]; then
    echo "GitHub release URL unavailable"
    echo "Skipping GitHub Pages payload preparation."
elif [ ! -x "$PREPARE_GITHUB_APPCAST_SCRIPT" ]; then
    echo "Helper script not executable: $PREPARE_GITHUB_APPCAST_SCRIPT"
    echo "Skipping GitHub Pages payload preparation."
elif [ ! -f "$KEYS_DIR/eddsa_private_key" ]; then
    echo "Sparkle private key missing at $KEYS_DIR/eddsa_private_key"
    echo "Skipping GitHub Pages payload preparation."
else
    mkdir -p "$PAGES_OUTPUT_DIR"
    VERSION_TAG="v$VERSION" \
    DMG_PATH="$DMG_PATH" \
    OUTPUT_DIR="$PAGES_OUTPUT_DIR" \
    SPARKLE_PRIVATE_KEY_FILE="$KEYS_DIR/eddsa_private_key" \
    GITHUB_REPO="$GITHUB_REPO" \
    "$PREPARE_GITHUB_APPCAST_SCRIPT"

    echo "Prepared appcast.xml at $PAGES_OUTPUT_DIR/appcast.xml"
    echo "Publish this file to GitHub Pages to serve Sparkle updates."
fi

if [ -f "$RELEASE_DIR/appcast/appcast.xml" ]; then
    echo "Local Sparkle appcast remains available at: $RELEASE_DIR/appcast/appcast.xml"
else
    echo "Local Sparkle appcast not generated."
fi

echo ""

echo "=== Release Complete ==="
echo ""
echo "Files created:"
echo "  - DMG: $DMG_PATH"
if [ -f "$RELEASE_DIR/appcast/appcast.xml" ]; then
    echo "  - Appcast: $RELEASE_DIR/appcast/appcast.xml"
fi
if [ -n "$GITHUB_DOWNLOAD_URL" ]; then
    echo "  - GitHub: https://github.com/$GITHUB_REPO/releases/tag/v$VERSION"
fi
if [ -f "$PAGES_OUTPUT_DIR/appcast.xml" ]; then
    echo "  - Pages payload: $PAGES_OUTPUT_DIR/appcast.xml"
fi
