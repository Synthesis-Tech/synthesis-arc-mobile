#!/usr/bin/env bash
#
# deploy-testflight.sh — Archive Forge Commander (iOS) and upload to TestFlight.
#
# One-command remote deploy. Designed to be run locally OR over SSH from the field:
#   ssh devops@macbook-pro 'cd ~/Projects/active/synthesis-arc-mobile && ./scripts/deploy-testflight.sh'
#
# Auth: App Store Connect API key (Team Key, App Manager role).
#   Key file: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8  (chmod 600)
#   Key ID / Issuer ID are NOT secret and are set below.
#
# What it does:
#   1. Bumps CFBundleVersion (build number) so the upload is unique (TestFlight rejects dupes).
#   2. Cleans + archives the SynthesisArc_iOS scheme (Release) with automatic distribution signing.
#   3. Exports an App Store .ipa via ExportOptions.plist.
#   4. Uploads the .ipa to App Store Connect / TestFlight.
#
# Build #1 is expected to go through the Xcode Organizer GUI (it mints the distribution cert).
# After that first GUI upload has primed signing, this script handles every subsequent deploy.

set -euo pipefail

# ---- Config -----------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="SynthesisArc_iOS"
CONFIG="Release"
PROJECT="${PROJECT_DIR}/SynthesisArc.xcodeproj"
INFO_PLIST="${PROJECT_DIR}/SynthesisArc/Info.plist"
EXPORT_OPTS="${PROJECT_DIR}/scripts/ExportOptions.plist"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/ForgeCommander.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"

# App Store Connect API key (non-secret identifiers; the .p8 is the secret)
ASC_KEY_ID="ZU87A99896"
ASC_ISSUER_ID="69a6de97-90d1-47e3-e053-5b8c7c11a4d1"
ASC_KEY_PATH="${HOME}/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

# ---- Helpers ----------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Pre-flight checks ------------------------------------------------------
[ -f "$ASC_KEY_PATH" ] || fail "API key not found at $ASC_KEY_PATH. Generate one in App Store Connect → Users and Access → Integrations and place it there (chmod 600)."
[ -d "$PROJECT" ]      || fail "Xcode project not found at $PROJECT"
[ -f "$INFO_PLIST" ]   || fail "Info.plist not found at $INFO_PLIST"
[ -f "$EXPORT_OPTS" ]  || fail "ExportOptions.plist not found at $EXPORT_OPTS"
command -v xcodebuild >/dev/null || fail "xcodebuild not on PATH"

# ---- 1. Bump build number ---------------------------------------------------
CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
# Numeric bump; if the value isn't a plain integer, fall back to a timestamp-free incrementable scheme.
if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  NEW_BUILD=$((CURRENT_BUILD + 1))
else
  fail "CFBundleVersion '$CURRENT_BUILD' is not a plain integer; bump it manually or adjust this script."
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$INFO_PLIST"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
log "Build number ${CURRENT_BUILD} → ${NEW_BUILD} (version ${SHORT_VERSION})"

# ---- 2. Archive -------------------------------------------------------------
log "Cleaning previous build output"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

log "Archiving ${SCHEME} (${CONFIG}) — this can take a few minutes"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=U8S9ZLXFJ4 \
  | tail -40

[ -d "$ARCHIVE_PATH" ] || fail "Archive did not produce $ARCHIVE_PATH"
log "Archive created: $ARCHIVE_PATH"

# ---- 3. Export .ipa ---------------------------------------------------------
log "Exporting App Store .ipa"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | tail -40

IPA_PATH="$(/bin/ls "$EXPORT_DIR"/*.ipa 2>/dev/null | head -1 || true)"
[ -n "$IPA_PATH" ] && [ -f "$IPA_PATH" ] || fail "Export did not produce an .ipa in $EXPORT_DIR"
log "Exported: $IPA_PATH"

# ---- 4. Upload to TestFlight ------------------------------------------------
log "Uploading to App Store Connect / TestFlight"
xcrun altool --upload-app \
  -f "$IPA_PATH" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

log "Upload submitted. Build ${SHORT_VERSION} (${NEW_BUILD}) is now processing in App Store Connect."
log "Processing usually takes 15 min to a few hours. It'll appear in TestFlight → iOS Builds when ready."
