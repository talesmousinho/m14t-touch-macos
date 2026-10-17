#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_PATH="${1:-$ROOT/.build/artifacts/M14tTouch-2.1.0.dmg}"

if [[ ! -f "$TARGET_PATH" ]]; then
    echo "Artifact not found: $TARGET_PATH" >&2
    exit 1
fi

if [[ -z "${NOTARY_PROFILE:-}" ]]; then
    cat >&2 <<EOF
NOTARY_PROFILE is required.

Create one with:
  xcrun notarytool store-credentials PROFILE_NAME --apple-id APPLE_ID --team-id TEAM_ID --password APP_SPECIFIC_PASSWORD

Then run:
  NOTARY_PROFILE=PROFILE_NAME Scripts/notarize.sh $TARGET_PATH
EOF
    exit 1
fi

xcrun notarytool submit "$TARGET_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$TARGET_PATH"
spctl --assess --type open --context context:primary-signature "$TARGET_PATH"
