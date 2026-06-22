#!/usr/bin/env bash
# setup_s3.sh — One-time S3 setup for OTA APK distribution.
#
# Run this ONCE before your first build. It:
#   1. Creates the S3 bucket
#   2. Configures public read access (metadata.json + builds/)
#   3. Sets CORS so the app can fetch metadata directly
#   4. Creates a least-privilege IAM policy + user for CI/CD
#   5. Uploads an initial empty metadata.json
#   6. Patches flavors/production.json and flavors/qa.json with the real URLs
#
# Usage:
#   S3_BUCKET=selah-app-builds S3_REGION=ap-south-1 ./scripts/setup_s3.sh
#
# Required env vars:
#   S3_BUCKET   — globally unique S3 bucket name you want to create
#   S3_REGION   — AWS region (e.g. ap-south-1, us-east-1)
#
# Optional env vars:
#   AWS_PROFILE        — named profile in ~/.aws/credentials (default: default)
#   CREATE_IAM_USER    — set to "true" to create a dedicated CI/CD IAM user
#   CI_USERNAME        — IAM username for the CI/CD user (default: selah-ci-deployer)

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────

S3_BUCKET="${S3_BUCKET:-}"
S3_REGION="${S3_REGION:-}"
S3_PREFIX="app-updates"
AWS_PROFILE="${AWS_PROFILE:-default}"
CREATE_IAM_USER="${CREATE_IAM_USER:-false}"
CI_USERNAME="${CI_USERNAME:-selah-ci-deployer}"

# ── Validate ──────────────────────────────────────────────────────────────────

if [[ -z "$S3_BUCKET" || -z "$S3_REGION" ]]; then
  echo "ERROR: S3_BUCKET and S3_REGION must be set." >&2
  echo ""
  echo "Example:"
  echo "  S3_BUCKET=selah-app-builds S3_REGION=ap-south-1 ./scripts/setup_s3.sh"
  exit 1
fi

if ! command -v aws &>/dev/null; then
  echo "ERROR: AWS CLI not found. Install it from https://aws.amazon.com/cli/" >&2
  exit 1
fi

PUBSPEC="pubspec.yaml"
if [[ ! -f "$PUBSPEC" ]]; then
  echo "ERROR: Run this script from the notify/ directory (pubspec.yaml not found)." >&2
  exit 1
fi

AWS="aws --profile $AWS_PROFILE --region $S3_REGION"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  S3 bucket  : $S3_BUCKET"
echo "  Region     : $S3_REGION"
echo "  IAM user   : $( [[ "$CREATE_IAM_USER" == "true" ]] && echo "$CI_USERNAME (will create)" || echo "skipped" )"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Create S3 bucket ───────────────────────────────────────────────────────

echo "▶ Creating S3 bucket: $S3_BUCKET…"

# us-east-1 does not accept LocationConstraint.
if [[ "$S3_REGION" == "us-east-1" ]]; then
  $AWS s3api create-bucket \
    --bucket "$S3_BUCKET" 2>/dev/null \
    && echo "  Created." \
    || echo "  Already exists — continuing."
else
  $AWS s3api create-bucket \
    --bucket "$S3_BUCKET" \
    --create-bucket-configuration LocationConstraint="$S3_REGION" 2>/dev/null \
    && echo "  Created." \
    || echo "  Already exists — continuing."
fi

# ── 2. Disable Block Public Access ───────────────────────────────────────────
# Required before a public bucket policy can be applied.

echo ""
echo "▶ Disabling Block Public Access…"
$AWS s3api put-public-access-block \
  --bucket "$S3_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
echo "  Done."

# ── 3. Bucket policy — public GET on app-updates/ only ───────────────────────
# Scope is intentionally narrow: only the app-updates prefix is public.

echo ""
echo "▶ Applying bucket policy…"
BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadAppUpdates",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${S3_BUCKET}/${S3_PREFIX}/*"
    }
  ]
}
EOF
)

$AWS s3api put-bucket-policy \
  --bucket "$S3_BUCKET" \
  --policy "$BUCKET_POLICY"
echo "  Policy applied (public GET on /${S3_PREFIX}/*)."

# ── 4. CORS ───────────────────────────────────────────────────────────────────
# Allows the Flutter app (running on any origin) to fetch metadata.json via
# XMLHttpRequest / fetch on web builds. Also satisfies Android WebView contexts.

echo ""
echo "▶ Configuring CORS…"
CORS_CONFIG=$(cat <<EOF
{
  "CORSRules": [
    {
      "AllowedOrigins": ["*"],
      "AllowedMethods": ["GET", "HEAD"],
      "AllowedHeaders": ["*"],
      "MaxAgeSeconds": 3600
    }
  ]
}
EOF
)

$AWS s3api put-bucket-cors \
  --bucket "$S3_BUCKET" \
  --cors-configuration "$CORS_CONFIG"
echo "  CORS configured."

# ── 5. Bucket versioning (optional safety net) ────────────────────────────────
# Enables recovery of accidentally overwritten metadata.json.

echo ""
echo "▶ Enabling bucket versioning…"
$AWS s3api put-bucket-versioning \
  --bucket "$S3_BUCKET" \
  --versioning-configuration Status=Enabled
echo "  Versioning enabled."

# ── 6. Lifecycle rule — auto-expire old object versions after 30 days ─────────
# Keeps the bucket from accumulating stale versions of metadata.json.

echo ""
echo "▶ Setting lifecycle rule for old versions…"
LIFECYCLE=$(cat <<EOF
{
  "Rules": [
    {
      "ID": "ExpireOldVersions",
      "Status": "Enabled",
      "Filter": { "Prefix": "${S3_PREFIX}/" },
      "NoncurrentVersionExpiration": { "NoncurrentDays": 30 }
    }
  ]
}
EOF
)

$AWS s3api put-bucket-lifecycle-configuration \
  --bucket "$S3_BUCKET" \
  --lifecycle-configuration "$LIFECYCLE"
echo "  Lifecycle rule applied."

# ── 7. IAM policy + user for CI/CD (optional) ────────────────────────────────

ACCOUNT_ID=$($AWS sts get-caller-identity --query Account --output text)
CI_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/SelahCiDeployer"

if [[ "$CREATE_IAM_USER" == "true" ]]; then
  echo ""
  echo "▶ Creating IAM policy: SelahCiDeployer…"

  CI_POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListBuilds",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::${S3_BUCKET}",
      "Condition": {
        "StringLike": { "s3:prefix": "${S3_PREFIX}/*" }
      }
    },
    {
      "Sid": "ReadWriteAppUpdates",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${S3_BUCKET}/${S3_PREFIX}/*"
    }
  ]
}
EOF
)

  # Create or update the policy.
  if $AWS iam get-policy --policy-arn "$CI_POLICY_ARN" &>/dev/null; then
    echo "  Policy already exists — skipping creation."
  else
    $AWS iam create-policy \
      --policy-name SelahCiDeployer \
      --description "Least-privilege access for Selah CI/CD APK uploads" \
      --policy-document "$CI_POLICY_DOC" \
      --region us-east-1   # IAM is global; region flag is ignored but avoids warnings
    echo "  Policy created: $CI_POLICY_ARN"
  fi

  echo ""
  echo "▶ Creating IAM user: $CI_USERNAME…"
  if $AWS iam get-user --user-name "$CI_USERNAME" &>/dev/null; then
    echo "  User already exists — skipping creation."
  else
    $AWS iam create-user --user-name "$CI_USERNAME"
    echo "  User created."
  fi

  echo ""
  echo "▶ Attaching policy to user…"
  $AWS iam attach-user-policy \
    --user-name "$CI_USERNAME" \
    --policy-arn "$CI_POLICY_ARN"
  echo "  Policy attached."

  echo ""
  echo "▶ Creating access key for $CI_USERNAME…"
  ACCESS_KEY_OUTPUT=$($AWS iam create-access-key --user-name "$CI_USERNAME")

  ACCESS_KEY_ID=$(echo "$ACCESS_KEY_OUTPUT" | python3 -c \
    "import json,sys; k=json.load(sys.stdin)['AccessKey']; print(k['AccessKeyId'])")
  SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_OUTPUT" | python3 -c \
    "import json,sys; k=json.load(sys.stdin)['AccessKey']; print(k['SecretAccessKey'])")

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  IAM credentials for CI/CD (save these now — shown once)"
  echo "  AWS_ACCESS_KEY_ID     = $ACCESS_KEY_ID"
  echo "  AWS_SECRET_ACCESS_KEY = $SECRET_ACCESS_KEY"
  echo ""
  echo "  Add to your CI environment or ~/.aws/credentials:"
  echo ""
  echo "  [selah-ci]"
  echo "  aws_access_key_id     = $ACCESS_KEY_ID"
  echo "  aws_secret_access_key = $SECRET_ACCESS_KEY"
  echo "  region                = $S3_REGION"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  # Write a named profile entry to a local .env file for reference.
  cat > scripts/.ci_credentials.env <<CREDS
# Generated by setup_s3.sh — add to your CI secrets, then delete this file.
AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
AWS_DEFAULT_REGION=$S3_REGION
S3_BUCKET=$S3_BUCKET
S3_REGION=$S3_REGION
CREDS
  echo "  Also written to scripts/.ci_credentials.env (do NOT commit this file)"
fi

# ── 8. Upload initial metadata.json ──────────────────────────────────────────

echo ""
echo "▶ Uploading initial metadata.json…"

VERSION_LINE=$(grep '^version:' "$PUBSPEC" | head -1)
FULL_VERSION=$(echo "$VERSION_LINE" | sed 's/version:[[:space:]]*//' | tr -d '[:space:]')
APP_VERSION="${FULL_VERSION%+*}"
BUILD_NUMBER="${FULL_VERSION#*+}"
CREATED_AT=$(date +%s)000

INITIAL_META=$(cat <<EOF
{
  "latestVersion": "${APP_VERSION}",
  "latestBuildNumber": ${BUILD_NUMBER},
  "minSupportedBuild": ${BUILD_NUMBER},
  "forceUpdate": false,
  "apkUrl": "",
  "releaseNotes": "Initial release",
  "createdAt": ${CREATED_AT}
}
EOF
)

# Production metadata.json
echo "$INITIAL_META" | $AWS s3 cp - \
  "s3://${S3_BUCKET}/${S3_PREFIX}/metadata.json" \
  --content-type "application/json" \
  --cache-control "no-cache, no-store, must-revalidate"

# QA metadata.json (same initial content)
echo "$INITIAL_META" | $AWS s3 cp - \
  "s3://${S3_BUCKET}/${S3_PREFIX}/metadata-qa.json" \
  --content-type "application/json" \
  --cache-control "no-cache, no-store, must-revalidate"

echo "  Uploaded."

# ── 9. Patch flavors/*.json with the real S3 URLs ────────────────────────────

PROD_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${S3_PREFIX}/metadata.json"
QA_URL="https://${S3_BUCKET}.s3.${S3_REGION}.amazonaws.com/${S3_PREFIX}/metadata-qa.json"

patch_flavor() {
  local FILE="$1"
  local URL="$2"
  if [[ ! -f "$FILE" ]]; then
    echo "  ⚠ $FILE not found — skipping patch."
    return
  fi
  # Replace the UPDATE_METADATA_URL value in-place using python for safe JSON editing.
  python3 - "$FILE" "$URL" <<'PYEOF'
import json, sys
path, url = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
data["UPDATE_METADATA_URL"] = url
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PYEOF
  echo "  Patched $FILE → $URL"
}

echo ""
echo "▶ Patching flavor files with real S3 URLs…"
patch_flavor "flavors/production.json" "$PROD_URL"
patch_flavor "flavors/qa.json"         "$QA_URL"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ S3 setup complete"
echo ""
echo "  Production metadata : $PROD_URL"
echo "  QA metadata         : $QA_URL"
echo ""
echo "  Next steps:"
echo "    1. Verify flavors/production.json and flavors/qa.json are updated."
if [[ "$CREATE_IAM_USER" == "true" ]]; then
echo "    2. Add the credentials from scripts/.ci_credentials.env to your CI"
echo "       secrets, then delete the file."
echo "    3. Run your first build:"
echo "       S3_BUCKET=$S3_BUCKET S3_REGION=$S3_REGION ./scripts/build_and_upload.sh"
else
echo "    2. Run your first build:"
echo "       S3_BUCKET=$S3_BUCKET S3_REGION=$S3_REGION ./scripts/build_and_upload.sh"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
