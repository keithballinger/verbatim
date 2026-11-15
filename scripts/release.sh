#!/bin/sh
# Build a signed, notarized Verbatim.app and zip it for distribution.
#
# One-time setup:
#   1. Install a "Developer ID Application" certificate in the login keychain
#      (Xcode > Settings > Accounts > Manage Certificates).
#   2. Save notary credentials under a keychain profile:
#        xcrun notarytool store-credentials verbatim-notary \
#          --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#
# Environment:
#   VERBATIM_SIGN_IDENTITY   certificate name; defaults to the Developer ID
#                            Application identity in the keychain
#   VERBATIM_NOTARY_PROFILE  notarytool keychain profile; defaults to
#                            verbatim-notary
#   SKIP_NOTARIZE=1          sign and zip only, to rehearse with another
#                            certificate; Gatekeeper rejects the result
set -eu
cd "$(dirname "$0")/.."

PRODUCTS=.build/Build/Products/Release
APP=$PRODUCTS/Verbatim.app
HELPER=$APP/Contents/Helpers/verbatim
DIST=.build/dist
PROFILE=${VERBATIM_NOTARY_PROFILE:-verbatim-notary}

die() {
  echo "release: $*" >&2
  exit 1
}

IDENTITY=${VERBATIM_SIGN_IDENTITY:-}
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning |
    sed -n 's/.*"\(Developer ID Application: .*\)".*/\1/p')
  [ -n "$IDENTITY" ] ||
    die "no Developer ID Application certificate in the keychain"
  [ "$(printf '%s\n' "$IDENTITY" | wc -l)" -eq 1 ] ||
    die "several Developer ID identities found; set VERBATIM_SIGN_IDENTITY"
fi

# The team ID is the certificate's organizational unit.
TEAM=$(security find-certificate -c "$IDENTITY" -p |
  openssl x509 -noout -subject -nameopt multiline |
  sed -n 's/^ *organizationalUnitName *= *//p')
[ -n "$TEAM" ] || die "cannot read the team ID of \"$IDENTITY\""

# Start from empty products so nothing signed by an earlier build is reused.
rm -rf "$PRODUCTS"
./scripts/build.sh -quiet CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS=--timestamp

# Notarization rejects code without the hardened runtime or a secure timestamp,
# and code that still carries the debugging entitlement.
check_signed() {
  info=$(codesign -dvv "$1" 2>&1)
  printf '%s\n' "$info" | grep -q '^CodeDirectory.*flags=.*runtime' ||
    die "$1: hardened runtime is off"
  printf '%s\n' "$info" | grep -q '^Timestamp=' ||
    die "$1: no secure timestamp"
  if codesign -d --entitlements - --xml "$1" 2>/dev/null |
    grep -q get-task-allow; then
    die "$1: carries the get-task-allow entitlement"
  fi
  if [ "${SKIP_NOTARIZE:-}" != 1 ]; then
    printf '%s\n' "$info" | grep -q '^Authority=Developer ID Application' ||
      die "$1: not signed with a Developer ID Application certificate"
  fi
}
check_signed "$HELPER"
check_signed "$APP"
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")
ZIP=$DIST/Verbatim-$VERSION.zip
package() {
  mkdir -p "$DIST"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
}
package

if [ "${SKIP_NOTARIZE:-}" != 1 ]; then
  # notarytool exits 0 even when Apple rejects the upload, so read the status.
  log=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait 2>&1 |
    tee /dev/stderr)
  printf '%s\n' "$log" | grep -q 'status: Accepted' ||
    die "notarization was not accepted; run: xcrun notarytool log <id> --keychain-profile $PROFILE"
  # Staple the ticket so the app opens offline, then zip the stapled app.
  xcrun stapler staple "$APP"
  package
  spctl --assess --type execute -vv "$APP"
fi

echo "release: $ZIP"
shasum -a 256 "$ZIP"
