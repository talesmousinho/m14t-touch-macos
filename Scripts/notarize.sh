#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_PATH="${1:-$ROOT/.build/artifacts/M14tTouch-Installer.pkg}"

if [[ ! -f "$PKG_PATH" ]]; then
    echo "Package not found: $PKG_PATH" >&2
    exit 1
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    cat >&2 <<EOF
NOTARY_PROFILE is required.

Create one with:
  xcrun notarytool store-credentials PROFILE_NAME --apple-id APPLE_ID --team-id TEAM_ID --password APP_SPECIFIC_PASSWORD

Then run:
  NOTARY_PROFILE=PROFILE_NAME Scripts/notarize.sh $PKG_PATH
EOF
    exit 1
fi

xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$PKG_PATH"
spctl --assess --type install "$PKG_PATH"
