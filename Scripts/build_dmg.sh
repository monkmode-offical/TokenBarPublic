#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

CONF="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

source "$ROOT/version.env"
SIGNING_MODE="${TOKENBAR_SIGNING:-identity}"
ALLOW_ADHOC_DMG="${TOKENBAR_ALLOW_ADHOC_DMG:-0}"
DEFAULT_RELEASE_IDENTITY="Developer ID Application: TokenBar Team (Y5PE65HELJ)"

has_signing_identity() {
  local identity="${1:-}"
  [[ -n "$identity" ]] || return 1
  security find-identity -p codesigning -v 2>/dev/null | grep -F "$identity" >/dev/null 2>&1
}

resolve_release_identity() {
  if [[ -n "${APP_IDENTITY:-}" ]]; then
    if has_signing_identity "${APP_IDENTITY}"; then
      printf "%s\n" "${APP_IDENTITY}"
      return 0
    fi
    echo "ERROR: APP_IDENTITY is set but not available in keychain: ${APP_IDENTITY}" >&2
    return 1
  fi

  if has_signing_identity "$DEFAULT_RELEASE_IDENTITY"; then
    printf "%s\n" "$DEFAULT_RELEASE_IDENTITY"
    return 0
  fi

  local detected=""
  detected="$(security find-identity -p codesigning -v 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1)"
  if has_signing_identity "$detected"; then
    printf "%s\n" "$detected"
    return 0
  fi
  return 1
}

if [[ "$SIGNING_MODE" == "adhoc" ]]; then
  if [[ "$ALLOW_ADHOC_DMG" != "1" ]]; then
    cat >&2 <<'EOF'
ERROR: Refusing to build a distributable DMG with ad-hoc signing.
Use TOKENBAR_ALLOW_ADHOC_DMG=1 TOKENBAR_SIGNING=adhoc only for local testing.
EOF
    exit 1
  fi
else
  RELEASE_IDENTITY="$(resolve_release_identity || true)"
  if [[ -z "$RELEASE_IDENTITY" ]]; then
    cat >&2 <<'EOF'
ERROR: No Developer ID Application signing identity found for DMG builds.
Install your Developer ID cert or set APP_IDENTITY to a valid Developer ID Application identity.
EOF
    exit 1
  fi
  export APP_IDENTITY="$RELEASE_IDENTITY"
fi

TOKENBAR_SIGNING="$SIGNING_MODE" "$ROOT/Scripts/package_app.sh" "$CONF"

APP_BUNDLE="$ROOT/TokenBar.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "ERROR: expected app bundle at $APP_BUNDLE" >&2
  exit 1
fi

DMG_NAME="TokenBar-${MARKETING_VERSION}.dmg"
DMG_PATH="$ROOT/$DMG_NAME"
STAGING_DIR="$(mktemp -d /tmp/tokenbar-dmg.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT

cp -R "$APP_BUNDLE" "$STAGING_DIR/TokenBar.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "TokenBar" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGNING_MODE" != "adhoc" ]]; then
  codesign --force --timestamp --sign "$APP_IDENTITY" "$DMG_PATH"
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

echo "Created $DMG_PATH"
