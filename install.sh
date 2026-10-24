#!/usr/bin/env bash
# Copy the plugin into Omarchy's user plugin directory and enable it.
# Plugin folders may not contain symlinks, so this copies rather than links.
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
id="$(jq -r .id "$src/manifest.json")"
dest="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id"

mkdir -p "$dest"
cp "$src"/manifest.json "$src"/*.qml "$src"/*.js "$dest"/
[[ -f $src/LICENSE ]] && cp "$src/LICENSE" "$dest/"
[[ -f $src/README.md ]] && cp "$src/README.md" "$dest/"

omarchy plugin validate "$dest"
omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin list --json | jq -e --arg id "$id" '.[] | select(.id == $id and .enabled)' >/dev/null \
  || omarchy plugin enable "$id"
echo "Installed $id → $dest"
