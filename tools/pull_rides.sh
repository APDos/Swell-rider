#!/usr/bin/env bash
# Copies the ride recordings off the iPhone into rides/ (git-ignored).
# Usage: tools/pull_rides.sh [device]   (device: name or id from `xcrun devicectl list devices`;
# defaults to the only connected iPhone)
set -euo pipefail
cd "$(dirname "$0")/.."
DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
	DEVICE="$(xcrun devicectl list devices 2>/dev/null | awk '/iPhone/ && /connected/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-/) {print $i; exit}}')"
	[[ -z "$DEVICE" ]] && { echo "No connected iPhone found; pass the device name or id." >&2; exit 1; }
fi
mkdir -p rides
touch rides/.gdignore   # keep Godot from importing the CSVs as translations (and packing them into builds)
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
	--domain-identifier com.apdos.swellrider --source Documents/rides --destination rides >/dev/null
ls -1t rides | head -20
