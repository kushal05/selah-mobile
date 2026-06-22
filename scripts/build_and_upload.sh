#!/usr/bin/env bash
# build_and_upload.sh — Build a release APK and publish it to S3.
#
# Usage:
#   ./scripts/build_and_upload.sh [FLAVOR] [RELEASE_NOTES]
#
# Arguments:
#   FLAVOR         production | qa  (default: production)
#   RELEASE_NOTES  Optional release note string (default: "Bug fixes and improvements")
#
# Prerequisites:
#   - AWS CLI configured with s3:PutObject / s3:GetObject / s3:DeleteObject / s3:ListBucket
#   - Flutter SDK on PATH
#   - S3_BUCKET and S3_REGION env vars set (or edit the defaults below)
#
# S3 layout produced:
#   s3://$S3_BUCKET/app-updates/
#     metadata.json           ← production source of truth (latest only)
#     metadata-qa.json        ← QA source of truth (latest only)
#     manifest.json           ← production rolling list of recent builds
#     manifest-qa.json        ← QA rolling list of recent builds
#     builds/
#       production/
#         app-production-v1.0.1+101.apk
#         app-production-v1.0.2+102.apk   ← at most MAX_BUILDS kept
#       qa/
#         app-qa-v1.0.1+101.apk
#         app-qa-v1.0.2+102.apk           ← rotated independently

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────

FLAVOR="${1:-production}"
RELEASE_NOTES="${2:-Bug fixes and improvements}"

S3_BUCKET="${S3_BUCKET:-YOUR_BUCKET_NAME}"
S3_REGION="${S3_REGION:-ap-south-1}"
S3_PREFIX="app-updates"
MAX_BUILDS=10
MIN_KEEP=3   # never delete below this count, even if MAX_BUILDS says so

# ── Validate ──────────────────────────────────────────────────────────────────

if [[ "$FLAVOR" != "production" && "$FLAVOR" != "qa" ]]; then
  echo "ERROR: FLAVOR must be 'production' or 'qa', got: $FLAVOR" >&2
  exit 1
fi

if [[ "$S3_BUCKET" == "YOUR_BUCKET_NAME" ]]; then
  echo "ERROR: Set the S3_BUCKET environment variable before running." >&2
  exit 1
fi

# ── Read version from pubspec.yaml ────────────────────────────────────────────

PUBSPEC="pubspec.yaml"
if [[ ! -f "$PUBSPEC" ]]; then
  echo "ERROR: Run this script from the notify/ directory (pubspec.yaml not found)." >&2
  exit 1
fi

VERSION_LINE=$(grep '^version:' "$PUBSPEC" | head -1)
FULL_VERSION=$(echo "$VERSION_LINE" | sed 's/version:[[:space:]]*//' | tr -d '[:space:]')
APP_VERSION="${FULL_VERSION%+*}"   # e.g. "1.0.2"
BUILD_NUMBER="${FULL_VERSION#*+}"  # e.g. "102"

if [[ -z "$APP_VERSION" || -z "$BUILD_NUMBER" || "$APP_VERSION" == "$BUILD_NUMBER" ]]; then
  echo "ERROR: Could not parse version+buildNumber from pubspec.yaml. Got: $FULL_VERSION" >&2
  echo "Expected format:  version: 1.0.2+102" >&2
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Flavor        : $FLAVOR"
echo "  Version       : $APP_VERSION"
echo "  Build number  : $BUILD_NUMBER"
echo "  S3 bucket     : $S3_BUCKET ($S3_REGION)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Build APK ─────────────────────────────────────────────────────────────────

echo ""
echo "▶ Building release APK…"
# Run pub get first; ignore exit code 1 caused by Windows Developer Mode
# symlink warning — dependencies are still resolved correctly.
flutter pub get 2>&1 | grep -v "Building with plugins requires symlink" \
                     | grep -v "Please enable Developer Mode" \
                     | grep -v "start ms-settings" || true

flutter build apk --release \
  --flavor "$FLAVOR" \
  --dart-define-from-file="flavors/${FLAVOR}.json" \
  --no-pub

# Flutter outputs to different paths depending on whether a flavor is used.
APK_FLAVOR_PATH="build/app/outputs/flutter-apk/app-${FLAVOR}-release.apk"
APK_PLAIN_PATH="build/app/outputs/flutter-apk/app-release.apk"

if [[ -f "$APK_FLAVOR_PATH" ]]; then
  APK_SOURCE="$APK_FLAVOR_PATH"
elif [[ -f "$APK_PLAIN_PATH" ]]; then
  APK_SOURCE="$APK_PLAIN_PATH"
else
  echo "ERROR: APK not found at expected paths after build." >&2
  exit 1
fi

APK_NAME="app-${FLAVOR}-v${APP_VERSION}+${BUILD_NUMBER}.apk"
APK_S3_PREFIX="${S3_PREFIX}/builds/${FLAVOR}"   # e.g. app-updates/builds/production
TMP_APK="/tmp/${APK_NAME}"
cp "$APK_SOURCE" "$TMP_APK"
echo "  Built: $TMP_APK ($(du -sh "$TMP_APK" | cut -f1))"

# ── Upload APK to S3 ──────────────────────────────────────────────────────────

echo ""
echo "▶ Uploading APK…"
aws s3 cp "$TMP_APK" \
  "s3://${S3_BUCKET}/${APK_S3_PREFIX}/${APK_NAME}" \
  --region "$S3_REGION" \
  --no-progress

# The S3 object key contains a literal '+'. In a URL path S3 treats a raw '+'
# as a space, so the *download URL* must percent-encode it as %2B — otherwise
# clients get a 403 and Android shows "There was a problem parsing the package".
# (The object key itself keeps the '+'; only the URL is encoded.)
APK_NAME_URL="${APK_NAME//+/%2B}"
APK_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${APK_S3_PREFIX}/${APK_NAME_URL}"
echo "  Uploaded: $APK_URL"

# ── Update metadata.json ──────────────────────────────────────────────────────

echo ""
echo "▶ Updating metadata.json…"
CREATED_AT=$(date +%s)000   # milliseconds

# Flavor-specific metadata key — defined early so it's available for the
# existing-metadata download below.
if [[ "$FLAVOR" == "qa" ]]; then
  METADATA_KEY="${S3_PREFIX}/metadata-qa.json"
else
  METADATA_KEY="${S3_PREFIX}/metadata.json"
fi

# Determine minSupportedBuild:
# - Pull existing metadata to preserve the current minSupportedBuild unless
#   FORCE_MIN_BUILD is set explicitly.
EXISTING_META_FILE="/tmp/metadata_existing.json"
aws s3 cp \
  "s3://${S3_BUCKET}/${METADATA_KEY}" \
  "$EXISTING_META_FILE" \
  --region "$S3_REGION" \
  --quiet 2>/dev/null || true   # ignore if this is the first upload

if [[ -f "$EXISTING_META_FILE" ]]; then
  # Parse minSupportedBuild using grep — no jq or python path issues on Windows.
  MIN_BUILD=$(grep '"minSupportedBuild"' "$EXISTING_META_FILE" \
    | grep -o '[0-9]\+' | head -1)
  [[ -z "$MIN_BUILD" ]] && MIN_BUILD="$BUILD_NUMBER"
else
  MIN_BUILD="$BUILD_NUMBER"
fi

# Allow explicit override via env var.
MIN_BUILD="${FORCE_MIN_BUILD:-$MIN_BUILD}"

cat > /tmp/metadata.json <<EOF
{
  "latestVersion": "${APP_VERSION}",
  "latestBuildNumber": ${BUILD_NUMBER},
  "minSupportedBuild": ${MIN_BUILD},
  "forceUpdate": ${FORCE_UPDATE:-false},
  "apkUrl": "${APK_URL}",
  "releaseNotes": "${RELEASE_NOTES}",
  "createdAt": ${CREATED_AT}
}
EOF

aws s3 cp /tmp/metadata.json \
  "s3://${S3_BUCKET}/${METADATA_KEY}" \
  --region "$S3_REGION" \
  --content-type "application/json" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --no-progress

echo "  Updated: s3://${S3_BUCKET}/${METADATA_KEY}"

# ── Update manifest.json (rolling last-3 list) ────────────────────────────────
#
# manifest.json keeps the most recent 3 builds for the in-app QA build picker.
# We rebuild it by prepending this build to the existing manifest and trimming
# to MANIFEST_KEEP. python3 is required (already used elsewhere in this repo's
# tooling) for safe JSON editing.

MANIFEST_KEEP=3

if [[ "$FLAVOR" == "qa" ]]; then
  MANIFEST_KEY="${S3_PREFIX}/manifest-qa.json"
else
  MANIFEST_KEY="${S3_PREFIX}/manifest.json"
fi

echo ""
echo "▶ Updating ${MANIFEST_KEY##*/}…"

EXISTING_MANIFEST_FILE="/tmp/manifest_existing.json"
rm -f "$EXISTING_MANIFEST_FILE"
aws s3 cp \
  "s3://${S3_BUCKET}/${MANIFEST_KEY}" \
  "$EXISTING_MANIFEST_FILE" \
  --region "$S3_REGION" \
  --quiet 2>/dev/null || true

NEW_MANIFEST_FILE="/tmp/manifest_new.json"

python3 - "$EXISTING_MANIFEST_FILE" "$NEW_MANIFEST_FILE" \
  "$FLAVOR" "$APP_VERSION" "$BUILD_NUMBER" "$APK_URL" \
  "$RELEASE_NOTES" "$CREATED_AT" "$MANIFEST_KEEP" <<'PYEOF'
import json, os, sys

(_, existing_path, out_path, flavor, app_version, build_number,
 apk_url, release_notes, created_at, keep) = sys.argv

build_number = int(build_number)
created_at   = int(created_at)
keep         = int(keep)

builds = []
if os.path.exists(existing_path) and os.path.getsize(existing_path) > 0:
    try:
        with open(existing_path) as f:
            data = json.load(f)
        builds = data.get("builds", []) or []
    except Exception:
        builds = []

# Drop any prior entry with the same buildNumber (re-upload of the same build).
builds = [b for b in builds if b.get("buildNumber") != build_number]

builds.insert(0, {
    "version":      app_version,
    "buildNumber":  build_number,
    "apkUrl":       apk_url,
    "releaseNotes": release_notes,
    "createdAt":    created_at,
})

# Sort newest-first by buildNumber so re-runs converge on a deterministic order.
builds.sort(key=lambda b: b.get("buildNumber", 0), reverse=True)
builds = builds[:keep]

with open(out_path, "w") as f:
    json.dump({
        "flavor":    flavor,
        "updatedAt": created_at,
        "builds":    builds,
    }, f, indent=2)
PYEOF

aws s3 cp "$NEW_MANIFEST_FILE" \
  "s3://${S3_BUCKET}/${MANIFEST_KEY}" \
  --region "$S3_REGION" \
  --content-type "application/json" \
  --cache-control "no-cache, no-store, must-revalidate" \
  --no-progress

echo "  Updated: s3://${S3_BUCKET}/${MANIFEST_KEY}"

# ── Rotate old builds (keep last MAX_BUILDS, scoped to this flavor) ───────────

echo ""
echo "▶ Rotating old builds (keeping last ${MAX_BUILDS})…"

# List only this flavor's APKs so prod and QA rotations stay independent.
ALL_BUILDS=$(aws s3 ls "s3://${S3_BUCKET}/${APK_S3_PREFIX}/" \
  --region "$S3_REGION" \
  | awk '{print $4}' \
  | grep '\.apk$' \
  | sort -t'+' -k2 -n)

TOTAL=$(echo "$ALL_BUILDS" | grep -c '\.apk' || true)
echo "  Total builds on S3: $TOTAL"

DELETE_COUNT=$(( TOTAL - MAX_BUILDS ))

if [[ $DELETE_COUNT -le 0 ]]; then
  echo "  Nothing to rotate."
else
  KEEP_COUNT=$(( TOTAL - DELETE_COUNT ))
  if [[ $KEEP_COUNT -lt $MIN_KEEP ]]; then
    echo "  ⚠ Skipping rotation — would drop below MIN_KEEP=${MIN_KEEP}."
  else
    TO_DELETE=$(echo "$ALL_BUILDS" | head -n "$DELETE_COUNT")
    while IFS= read -r build; do
      [[ -z "$build" ]] && continue
      echo "  Deleting: $build"
      aws s3 rm "s3://${S3_BUCKET}/${APK_S3_PREFIX}/${build}" \
        --region "$S3_REGION"
    done <<< "$TO_DELETE"
    echo "  Deleted $DELETE_COUNT old build(s)."
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Build uploaded successfully"
echo "  APK URL : $APK_URL"
echo "  Metadata: https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${METADATA_KEY}"
echo "  Manifest: https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${MANIFEST_KEY}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
