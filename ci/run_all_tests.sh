#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# CI Pipeline: Full test suite for the Notify Flutter app
#
# Stages:
#   1. Unit tests (fast, no device needed)
#   2. Integration tests (headless, in-memory DB)
#   3. Build APK (debug, for Maestro)
#   4. Maestro smoke tests (requires emulator)
#
# Usage:
#   ./ci/run_all_tests.sh              # Run all stages
#   ./ci/run_all_tests.sh unit         # Unit tests only
#   ./ci/run_all_tests.sh integration  # Integration tests only
#   ./ci/run_all_tests.sh maestro      # Maestro smoke tests only
#   ./ci/run_all_tests.sh build        # Build APK only
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

STAGE="${1:-all}"
FAILURES=0

log_header() {
  echo ""
  echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  $1${NC}"
  echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
}

log_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

log_failure() {
  echo -e "${RED}✗ $1${NC}"
  FAILURES=$((FAILURES + 1))
}

# ── Stage 1: Unit Tests ────────────────────────────────────────────────────
run_unit_tests() {
  log_header "Stage 1: Unit Tests"

  if flutter test --reporter expanded; then
    log_success "Unit tests passed"
  else
    log_failure "Unit tests failed"
  fi
}

# ── Stage 2: Integration Tests (headless, in-memory DB) ───────────────────
run_integration_tests() {
  log_header "Stage 2: Integration Tests (scenarios)"

  local test_files=(
    "integration_test/scenarios/offline_sync_test.dart"
    "integration_test/scenarios/conflict_resolution_test.dart"
    "integration_test/scenarios/restart_recovery_test.dart"
  )

  # Detect device for integration tests
  local device_flag=""
  if command -v flutter &> /dev/null; then
    local device_id
    device_id=$(flutter devices --machine 2>/dev/null | python3 -c "
import sys, json
try:
    devices = json.load(sys.stdin)
    for d in devices:
        if d.get('targetPlatform','') in ('android-arm','android-arm64','android-x64','android-x86'):
            print(d['id']); break
    else:
        for d in devices:
            if 'emulator' in d.get('id','').lower() or 'chrome' in d.get('id','').lower():
                print(d['id']); break
except: pass
" 2>/dev/null || true)
    if [ -n "$device_id" ]; then
      device_flag="-d $device_id"
    fi
  fi

  for test_file in "${test_files[@]}"; do
    local test_name
    test_name=$(basename "$test_file" .dart)
    echo ""
    echo "  Running: $test_name"

    if flutter test $device_flag "$test_file" --reporter expanded 2>&1; then
      log_success "$test_name passed"
    else
      log_failure "$test_name failed"
    fi
  done
}

# ── Stage 3: Build APK ────────────────────────────────────────────────────
run_build() {
  log_header "Stage 3: Build Debug APK"

  if flutter build apk --debug; then
    log_success "Debug APK built"
  else
    log_failure "APK build failed"
  fi
}

# ── Stage 4: Maestro Smoke Tests ──────────────────────────────────────────
run_maestro_tests() {
  log_header "Stage 4: Maestro Smoke Tests"

  if ! command -v maestro &> /dev/null; then
    log_failure "Maestro CLI not installed (install: curl -Ls https://get.maestro.mobile.dev | bash)"
    return
  fi

  # Check for connected device
  if ! adb devices 2>/dev/null | grep -q "device$"; then
    log_failure "No Android device/emulator connected"
    return
  fi

  local smoke_flows=(
    "maestro/flows/smoke/01_app_launch.yaml"
    "maestro/flows/smoke/02_notes_crud.yaml"
    "maestro/flows/smoke/03_prayers_crud.yaml"
  )

  # Install debug APK if not already installed
  local apk_path="build/app/outputs/flutter-apk/app-debug.apk"
  if [ -f "$apk_path" ]; then
    adb install -r "$apk_path" 2>/dev/null || true
  fi

  for flow in "${smoke_flows[@]}"; do
    local flow_name
    flow_name=$(basename "$flow" .yaml)
    echo ""
    echo "  Running: $flow_name"

    if maestro test "$flow" 2>&1; then
      log_success "$flow_name passed"
    else
      log_failure "$flow_name failed"
    fi
  done
}

# ── Main ───────────────────────────────────────────────────────────────────
case "$STAGE" in
  unit)         run_unit_tests ;;
  integration)  run_integration_tests ;;
  build)        run_build ;;
  maestro)      run_maestro_tests ;;
  all)
    run_unit_tests
    run_integration_tests
    run_build
    run_maestro_tests
    ;;
  *)
    echo "Usage: $0 {all|unit|integration|build|maestro}"
    exit 1
    ;;
esac

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
log_header "Summary"
if [ "$FAILURES" -eq 0 ]; then
  log_success "All stages passed"
  exit 0
else
  log_failure "$FAILURES stage(s) failed"
  exit 1
fi
