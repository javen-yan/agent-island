#!/bin/bash
# Generate a Sparkle appcast.xml that is hosted on GitHub Pages
# while the downloadable update archive remains on GitHub Releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

VERSION_TAG="${VERSION_TAG:-${1:-}}"
DMG_PATH="${DMG_PATH:-${2:-}}"
OUTPUT_DIR="${OUTPUT_DIR:-${3:-$PROJECT_DIR/build/appcast-pages}}"
KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$PROJECT_DIR/.sparkle-keys/eddsa_private_key}"
GITHUB_REPO="${GITHUB_REPO:-javen-yan/agent-island}"
EXISTING_APPCAST_URL="${EXISTING_APPCAST_URL:-}"

if [ -z "$VERSION_TAG" ]; then
    echo "ERROR: VERSION_TAG is required"
    echo "Usage: VERSION_TAG=v1.0.0 DMG_PATH=/path/to/AgentIsland-v1.0.0.dmg $0"
    exit 1
fi

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG_PATH must point to an existing DMG"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "ERROR: Sparkle private key not found at $KEY_FILE"
    exit 1
fi

GENERATE_APPCAST=""
POSSIBLE_PATHS=(
    "$HOME/Library/Developer/Xcode/DerivedData/AgentIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
)

for path_pattern in "${POSSIBLE_PATHS[@]}"; do
    for path in $path_pattern; do
        if [ -x "$path" ]; then
            GENERATE_APPCAST="$path"
            break 2
        fi
    done
done

if [ -z "$GENERATE_APPCAST" ]; then
    echo "ERROR: Could not find Sparkle generate_appcast tool"
    echo "Run xcodebuild -resolvePackageDependencies or build the project first."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
cp "$DMG_PATH" "$TMP_DIR/"

"$GENERATE_APPCAST" --ed-key-file "$KEY_FILE" "$TMP_DIR"

APPCAST_PATH="$TMP_DIR/appcast.xml"
if [ ! -f "$APPCAST_PATH" ]; then
    echo "ERROR: generate_appcast did not produce appcast.xml"
    exit 1
fi

RELEASE_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION_TAG/$(basename "$DMG_PATH")"
OWNER="${GITHUB_REPO%%/*}"
REPO_NAME="${GITHUB_REPO#*/}"

if [ -z "$EXISTING_APPCAST_URL" ]; then
    EXISTING_APPCAST_URL="https://$OWNER.github.io/$REPO_NAME/appcast.xml"
fi

EXISTING_APPCAST_PATH="$TMP_DIR/existing-appcast.xml"
if curl -fsSL "$EXISTING_APPCAST_URL" -o "$EXISTING_APPCAST_PATH"; then
    echo "Fetched existing appcast from: $EXISTING_APPCAST_URL"
else
    echo "No existing appcast found at: $EXISTING_APPCAST_URL"
    rm -f "$EXISTING_APPCAST_PATH"
fi

python3 - <<'PY' "$APPCAST_PATH" "$RELEASE_URL" "$EXISTING_APPCAST_PATH"
import sys
import email.utils
import xml.etree.ElementTree as ET

appcast_path, release_url, existing_appcast_path = sys.argv[1], sys.argv[2], sys.argv[3]

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE_NS)

def local_name(tag: str) -> str:
    return tag.split("}", 1)[-1] if "}" in tag else tag

def item_key(item):
    version = None
    title = None
    enclosure_url = None
    pub_date = None
    for child in item:
        name = local_name(child.tag)
        if name == "version":
            version = (child.text or "").strip()
        elif name == "shortVersionString" and not version:
            version = (child.text or "").strip()
        elif name == "title":
            title = (child.text or "").strip()
        elif name == "pubDate":
            pub_date = (child.text or "").strip()
        elif name == "enclosure":
            enclosure_url = child.attrib.get("url", "").strip()
    return version or title or enclosure_url or pub_date or ET.tostring(item, encoding="unicode")

def item_sort_key(item):
    pub_date = ""
    version = ""
    title = ""
    for child in item:
        name = local_name(child.tag)
        if name == "pubDate":
            pub_date = (child.text or "").strip()
        elif name == "version":
            version = (child.text or "").strip()
        elif name == "title":
            title = (child.text or "").strip()

    try:
        parsed_pub_date = email.utils.parsedate_to_datetime(pub_date)
        if parsed_pub_date.tzinfo is None:
            timestamp = parsed_pub_date.timestamp()
        else:
            timestamp = parsed_pub_date.astimezone().timestamp()
    except Exception:
        timestamp = float("-inf")

    return (timestamp, version, title)

new_tree = ET.parse(appcast_path)
new_root = new_tree.getroot()

for enclosure in new_root.iter():
    if local_name(enclosure.tag) == "enclosure":
        enclosure.set("url", release_url)

new_channel = next((child for child in new_root if local_name(child.tag) == "channel"), None)
if new_channel is None:
    raise SystemExit("Generated appcast missing channel element")

items_by_key = {}
for child in list(new_channel):
    if local_name(child.tag) == "item":
        items_by_key[item_key(child)] = child

try:
    existing_tree = ET.parse(existing_appcast_path)
except (FileNotFoundError, ET.ParseError):
    existing_tree = None

if existing_tree is not None:
    existing_root = existing_tree.getroot()
    existing_channel = next((child for child in existing_root if local_name(child.tag) == "channel"), None)
    if existing_channel is not None:
        for item in existing_channel:
            if local_name(item.tag) != "item":
                continue
            key = item_key(item)
            if key not in items_by_key:
                items_by_key[key] = item

for child in list(new_channel):
    if local_name(child.tag) == "item":
        new_channel.remove(child)

for item in sorted(items_by_key.values(), key=item_sort_key, reverse=True):
    new_channel.append(item)

new_tree.write(appcast_path, encoding="utf-8", xml_declaration=True)
PY

cp "$APPCAST_PATH" "$OUTPUT_DIR/appcast.xml"
echo "Generated GitHub Pages appcast at: $OUTPUT_DIR/appcast.xml"
echo "Release download URL: $RELEASE_URL"
