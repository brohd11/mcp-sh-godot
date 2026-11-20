#!/bin/sh
# Vendor the mcp-sh-godot plugin's release export into addon/mcp_sh_godot, which go:embed
# carries and `mcp_sh_godot addon install` writes. Commit the result.
#
#   scripts/fetch_addon.sh             # latest release of brohd11/godot-mcp-sh-plugin
#   scripts/fetch_addon.sh v0.2.0      # that tag
#   scripts/fetch_addon.sh --zip FILE  # a local export zip (development only)
#
# Needs curl, jq and unzip. GITHUB_TOKEN (or GH_TOKEN) raises the API rate limit.
set -eu

REPO="brohd11/godot-mcp-sh-plugin"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/addon/mcp_sh_godot"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mcp-sh-godot-addon.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

if [ "${1:-}" = "--zip" ]; then
	[ -n "${2:-}" ] || { echo "usage: $0 --zip FILE" >&2; exit 2; }
	zip=$2
	source="$zip"
else
	if [ -n "${1:-}" ]; then
		api="https://api.github.com/repos/$REPO/releases/tags/$1"
	else
		api="https://api.github.com/repos/$REPO/releases/latest"
	fi
	token=${GITHUB_TOKEN:-${GH_TOKEN:-}}
	if [ -n "$token" ]; then
		curl -fsSL -H "Authorization: Bearer $token" "$api" > "$TMP/release.json"
	else
		curl -fsSL "$api" > "$TMP/release.json"
	fi
	tag=$(jq -r '.tag_name' "$TMP/release.json")
	url=$(jq -r '[.assets[] | select(.name | endswith(".zip"))][0].browser_download_url // empty' "$TMP/release.json")
	[ -n "$url" ] || { echo "error: release $tag of $REPO has no zip asset" >&2; exit 1; }
	zip="$TMP/addon.zip"
	curl -fsSL -o "$zip" "$url"
	source="$REPO $tag"
fi

unzip -q "$zip" -d "$TMP/x"
src=$(find "$TMP/x" -type d -path '*/addons/mcp_sh_godot' | head -1)
[ -n "$src" ] && [ -f "$src/plugin.cfg" ] || { echo "error: no addons/mcp_sh_godot/plugin.cfg in $zip" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$src" "$DEST"
version=$(sed -n 's/^version="\(.*\)"/\1/p' "$DEST/plugin.cfg")
echo "vendored mcp-sh-godot addon $version from $source into addon/mcp_sh_godot"
