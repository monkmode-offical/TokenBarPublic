#!/usr/bin/env bash
set -euo pipefail

APP_NAME="TokenBar"
APP_IDENTITY="${APP_IDENTITY:-TokenBar Development}"
APP_BUNDLE="TokenBar.app"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/version.env"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"
DSYM_ZIP="${APP_NAME}-${MARKETING_VERSION}.dSYM.zip"

NOTARY_AUTH_MODE=""
if [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  NOTARY_AUTH_MODE="api_key"
elif [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_AUTH_MODE="keychain_profile"
elif [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-${TEAM_ID:-}}" ]]; then
  NOTARY_AUTH_MODE="apple_id"
else
  cat >&2 <<'EOF'
Missing notarization credentials.
Provide one of:
  1) APP_STORE_CONNECT_API_KEY_P8 + APP_STORE_CONNECT_KEY_ID + APP_STORE_CONNECT_ISSUER_ID
  2) NOTARYTOOL_KEYCHAIN_PROFILE
  3) APPLE_ID + APP_SPECIFIC_PASSWORD + APPLE_TEAM_ID (or TEAM_ID)
EOF
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE is required for release signing/verification." >&2
  exit 1
fi
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi
key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
  echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
  exit 1
fi

if [[ "$NOTARY_AUTH_MODE" == "api_key" ]]; then
  echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/tokenbar-api-key.p8
fi
trap 'rm -f /tmp/tokenbar-api-key.p8 /tmp/${APP_NAME}Notarize.zip' EXIT

CODESIGN_KEYCHAIN="${TOKENBAR_CODESIGN_KEYCHAIN:-${APP_CODESIGN_KEYCHAIN:-}}"
CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
if [[ -n "${CODESIGN_KEYCHAIN}" ]]; then
  CODESIGN_ARGS+=(--keychain "${CODESIGN_KEYCHAIN}")
fi

# Allow building a universal binary if ARCHES is provided; default to universal (arm64 + x86_64).
ARCHES_VALUE=${ARCHES:-"arm64 x86_64"}
ARCH_LIST=( ${ARCHES_VALUE} )
for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c release --arch "$ARCH"
done
ARCHES="${ARCHES_VALUE}" ./Scripts/package_app.sh release

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
APP_ENTITLEMENTS="${ENTITLEMENTS_DIR}/TokenBar.entitlements"
WIDGET_ENTITLEMENTS="${ENTITLEMENTS_DIR}/TokenBarWidget.entitlements"

echo "Signing with $APP_IDENTITY"
if [[ -f "$APP_BUNDLE/Contents/Helpers/TokenBarCLI" ]]; then
  codesign "${CODESIGN_ARGS[@]}" \
    "$APP_BUNDLE/Contents/Helpers/TokenBarCLI"
fi
if [[ -f "$APP_BUNDLE/Contents/Helpers/TokenBarClaudeWatchdog" ]]; then
  codesign "${CODESIGN_ARGS[@]}" \
    "$APP_BUNDLE/Contents/Helpers/TokenBarClaudeWatchdog"
fi
if [[ -d "$APP_BUNDLE/Contents/PlugIns/TokenBarWidget.appex" ]]; then
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP_BUNDLE/Contents/PlugIns/TokenBarWidget.appex/Contents/MacOS/TokenBarWidget"
  codesign "${CODESIGN_ARGS[@]}" \
    --entitlements "$WIDGET_ENTITLEMENTS" \
    "$APP_BUNDLE/Contents/PlugIns/TokenBarWidget.appex"
fi
codesign "${CODESIGN_ARGS[@]}" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP_BUNDLE"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "/tmp/${APP_NAME}Notarize.zip"

echo "Submitting for notarization"
if [[ "$NOTARY_AUTH_MODE" == "api_key" ]]; then
  xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
    --key /tmp/tokenbar-api-key.p8 \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait
elif [[ "$NOTARY_AUTH_MODE" == "keychain_profile" ]]; then
  xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
    --keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE" \
    --wait
else
  TEAM_ID_VALUE="${APPLE_TEAM_ID:-${TEAM_ID:-}}"
  xcrun notarytool submit "/tmp/${APP_NAME}Notarize.zip" \
    --apple-id "$APPLE_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --team-id "$TEAM_ID_VALUE" \
    --wait
fi

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

# Strip any extended attributes that would create AppleDouble files when zipping
xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Packaging dSYM"
FIRST_ARCH="${ARCH_LIST[0]}"
PREFERRED_ARCH_DIR=".build/${FIRST_ARCH}-apple-macosx/release"
DSYM_PATH="${PREFERRED_ARCH_DIR}/${APP_NAME}.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
  MERGED_DSYM="${PREFERRED_ARCH_DIR}/${APP_NAME}.dSYM-universal"
  rm -rf "$MERGED_DSYM"
  cp -R "$DSYM_PATH" "$MERGED_DSYM"
  DWARF_PATH="${MERGED_DSYM}/Contents/Resources/DWARF/${APP_NAME}"
  BINARIES=()
  for ARCH in "${ARCH_LIST[@]}"; do
    ARCH_DSYM=".build/${ARCH}-apple-macosx/release/${APP_NAME}.dSYM/Contents/Resources/DWARF/${APP_NAME}"
    if [[ ! -f "$ARCH_DSYM" ]]; then
      echo "Missing dSYM for ${ARCH} at $ARCH_DSYM" >&2
      exit 1
    fi
    BINARIES+=("$ARCH_DSYM")
  done
  lipo -create "${BINARIES[@]}" -output "$DWARF_PATH"
  DSYM_PATH="$MERGED_DSYM"
fi
"$DITTO_BIN" --norsrc -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
