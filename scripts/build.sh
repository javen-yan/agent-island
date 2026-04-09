#!/bin/bash
# Build Agent Island for release
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/AgentIsland.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
BRIDGE_BINARY="$PROJECT_DIR/bridge-rs/target/release/agent-island-bridge"
APP_IN_ARCHIVE="$ARCHIVE_PATH/Products/Applications/Agent Island.app"
APP_IN_EXPORT="$EXPORT_PATH/Agent Island.app"
APP_RESOURCES_PATHS=(
    "$APP_IN_ARCHIVE/Contents/Resources"
    "$APP_IN_EXPORT/Contents/Resources"
)
CI_NO_SIGN="${AGENT_ISLAND_NO_SIGN:-0}"
RELEASE_VERSION="${AGENT_ISLAND_RELEASE_VERSION:-}"
RELEASE_BUILD_NUMBER="${AGENT_ISLAND_RELEASE_BUILD_NUMBER:-}"

run_xcodebuild() {
    if command -v xcpretty >/dev/null 2>&1; then
        "$@" | xcpretty
    else
        "$@"
    fi
}

xcode_version_args=()
if [ -n "$RELEASE_VERSION" ]; then
    xcode_version_args+=("MARKETING_VERSION=$RELEASE_VERSION")
fi
if [ -n "$RELEASE_BUILD_NUMBER" ]; then
    xcode_version_args+=("CURRENT_PROJECT_VERSION=$RELEASE_BUILD_NUMBER")
fi

has_developer_id_certificate() {
    security find-identity -p basic -v | grep -q "Developer ID Application"
}

echo "=== Building Agent Island ==="
echo ""

if [ ! -f "$BRIDGE_BINARY" ]; then
    echo "Building Rust bridge first..."
    "$PROJECT_DIR/scripts/build-rust-bridge.sh"
fi

if [ ! -x "$BRIDGE_BINARY" ]; then
    echo "ERROR: Rust bridge binary not executable: $BRIDGE_BINARY"
    exit 1
fi

if [ "$CI_NO_SIGN" = "1" ]; then
    echo "CI unsigned build mode enabled (AGENT_ISLAND_NO_SIGN=1)"

    # Clean previous builds
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

    UNSIGNED_BUILD_DIR="$BUILD_DIR/Unsigned"

    echo "Building without code signing..."
    run_xcodebuild xcodebuild build \
        -project "$PROJECT_DIR/AgentIsland.xcodeproj" \
        -scheme AgentIsland \
        -configuration Release \
        -destination "generic/platform=macOS" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_KEYCHAIN="" \
        CONFIGURATION_BUILD_DIR="$UNSIGNED_BUILD_DIR" \
        "${xcode_version_args[@]}"

    if [ ! -d "$UNSIGNED_BUILD_DIR/Agent Island.app" ]; then
        echo "ERROR: Unsigned app not found at $UNSIGNED_BUILD_DIR/Agent Island.app"
        exit 1
    fi

    rm -rf "$APP_IN_EXPORT"
    mkdir -p "$EXPORT_PATH"
    cp -R "$UNSIGNED_BUILD_DIR/Agent Island.app" "$APP_IN_EXPORT"

echo ""
echo "Embedding Rust bridge into app bundle..."
embedded_count=0
for resource_path in "$APP_IN_EXPORT/Contents/Resources"; do
    if [ -d "$resource_path" ]; then
        cp "$BRIDGE_BINARY" "$resource_path/agent-island-bridge"
        chmod +x "$resource_path/agent-island-bridge"
        if [ -x "$resource_path/agent-island-bridge" ]; then
            echo "Embedded bridge at: $resource_path/agent-island-bridge"
            embedded_count=$((embedded_count + 1))
        else
            echo "ERROR: Embedded bridge is not executable: $resource_path/agent-island-bridge"
            exit 1
        fi
    fi
done
if [ "$embedded_count" -eq 0 ]; then
    echo "ERROR: Failed to embed Rust bridge into app bundle"
    exit 1
fi

    echo ""
    echo "=== Build Complete ==="
    echo "App exported to: $APP_IN_EXPORT"
    echo ""
    echo "Next: Run ./scripts/create-release.sh to notarize and create DMG"
    exit 0
fi

if ! has_developer_id_certificate; then
    echo "Developer ID certificate not found, building unsigned output for local use."
    echo "CI unsigned build mode fallback (signing disabled)."
    rm -rf "$APP_IN_EXPORT"
    mkdir -p "$BUILD_DIR" "$EXPORT_PATH"

    UNSIGNED_BUILD_DIR="$BUILD_DIR/Unsigned"
    run_xcodebuild xcodebuild build \
        -project "$PROJECT_DIR/AgentIsland.xcodeproj" \
        -scheme AgentIsland \
        -configuration Release \
        -destination "generic/platform=macOS" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        CODE_SIGNING_KEYCHAIN="" \
        CONFIGURATION_BUILD_DIR="$UNSIGNED_BUILD_DIR" \
        "${xcode_version_args[@]}"

    if [ ! -d "$UNSIGNED_BUILD_DIR/Agent Island.app" ]; then
        echo "ERROR: Unsigned app not found at $UNSIGNED_BUILD_DIR/Agent Island.app"
        exit 1
    fi
    cp -R "$UNSIGNED_BUILD_DIR/Agent Island.app" "$APP_IN_EXPORT"
else
    # Build and archive
    echo "Archiving..."
    run_xcodebuild xcodebuild archive \
        -project "$PROJECT_DIR/AgentIsland.xcodeproj" \
        -scheme AgentIsland \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -destination "generic/platform=macOS" \
        ENABLE_HARDENED_RUNTIME=YES \
        CODE_SIGN_STYLE=Automatic \
        "${xcode_version_args[@]}"

    # Create ExportOptions.plist if it doesn't exist
    EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
    cat > "$EXPORT_OPTIONS" << 'EOF'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>method</key>
        <string>developer-id</string>
        <key>destination</key>
        <string>export</string>
        <key>signingStyle</key>
        <string>automatic</string>
    </dict>
    </plist>
EOF

    # Export the archive
    echo ""
    echo "Exporting..."
    run_xcodebuild xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS"
fi

cd "$PROJECT_DIR"

echo ""
echo "Embedding Rust bridge into app bundle..."
embedded_count=0
for resource_path in "${APP_RESOURCES_PATHS[@]}"; do
    if [ -d "$resource_path" ]; then
        cp "$BRIDGE_BINARY" "$resource_path/agent-island-bridge"
        chmod +x "$resource_path/agent-island-bridge"
        if [ -x "$resource_path/agent-island-bridge" ]; then
            echo "Embedded bridge at: $resource_path/agent-island-bridge"
            embedded_count=$((embedded_count + 1))
        else
            echo "ERROR: Embedded bridge is not executable: $resource_path/agent-island-bridge"
            exit 1
        fi
    fi
done
if [ "$embedded_count" -eq 0 ]; then
    echo "ERROR: Failed to embed Rust bridge into app bundle"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
echo "App exported to: $EXPORT_PATH/Agent Island.app"
echo ""
echo "Next: Run ./scripts/create-release.sh to notarize and create DMG"
