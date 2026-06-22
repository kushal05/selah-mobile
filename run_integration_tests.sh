#!/bin/bash
# ──────────────────────────────────────────────
# Run Flutter Integration Tests on a connected device
# ──────────────────────────────────────────────
#
# Usage:
#   ./run_integration_tests.sh              # Run ALL integration tests
#   ./run_integration_tests.sh auth         # Run only auth tests
#   ./run_integration_tests.sh notes        # Run only notes tests
#   ./run_integration_tests.sh <name>       # Run a specific test file
#
# Prerequisites:
#   - Physical device or emulator connected (check: flutter devices)
#   - App dependencies installed (flutter pub get)

set -e
cd "$(dirname "$0")"

DEVICE_ID=""
# Auto-detect first connected device
if command -v flutter &> /dev/null; then
    DEVICE_ID=$(flutter devices --machine 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
fi

echo "═══════════════════════════════════════════"
echo " Notify App — Integration Tests"
echo "═══════════════════════════════════════════"

if [ -n "$DEVICE_ID" ]; then
    echo "Device: $DEVICE_ID"
    DEVICE_FLAG="-d $DEVICE_ID"
else
    echo "Device: auto-detect (first available)"
    DEVICE_FLAG=""
fi
echo ""

run_test() {
    local test_file=$1
    local name=$2
    echo "──────────────────────────────────────────"
    echo "Running: $name"
    echo "File:    $test_file"
    echo "──────────────────────────────────────────"
    flutter test $DEVICE_FLAG "$test_file" --reporter expanded 2>&1
    echo ""
}

if [ -z "$1" ] || [ "$1" = "all" ]; then
    echo "Running ALL integration tests..."
    echo ""
    run_test integration_test/auth_onboarding_test.dart       "1. Auth & Onboarding"
    run_test integration_test/notes_test.dart                  "2. Notes & Editor"
    run_test integration_test/folders_test.dart                 "3. Folders"
    run_test integration_test/prayers_test.dart                 "4. Prayers"
    run_test integration_test/promises_songs_test.dart          "5. Promises & Songs"
    run_test integration_test/people_test.dart                  "6. People"
    run_test integration_test/bible_test.dart                   "7. Bible"
    run_test integration_test/search_tags_test.dart             "8. Search & Tags"
    run_test integration_test/social_test.dart                  "9. Social (Groups, Friends)"
    run_test integration_test/home_settings_nav_test.dart       "10. Home, Settings, Navigation"
    run_test integration_test/sync_oplog_test.dart              "11. Sync, Conflict, Oplog"
    run_test integration_test/remaining_features_test.dart      "12. Remaining Features"
    echo "═══════════════════════════════════════════"
    echo " ALL INTEGRATION TESTS COMPLETE"
    echo "═══════════════════════════════════════════"
else
    case "$1" in
        auth)       run_test integration_test/auth_onboarding_test.dart   "Auth & Onboarding" ;;
        notes)      run_test integration_test/notes_test.dart              "Notes & Editor" ;;
        folders)    run_test integration_test/folders_test.dart             "Folders" ;;
        prayers)    run_test integration_test/prayers_test.dart             "Prayers" ;;
        promises)   run_test integration_test/promises_songs_test.dart      "Promises & Songs" ;;
        songs)      run_test integration_test/promises_songs_test.dart      "Promises & Songs" ;;
        people)     run_test integration_test/people_test.dart              "People" ;;
        bible)      run_test integration_test/bible_test.dart               "Bible" ;;
        search)     run_test integration_test/search_tags_test.dart         "Search & Tags" ;;
        tags)       run_test integration_test/search_tags_test.dart         "Search & Tags" ;;
        social)     run_test integration_test/social_test.dart              "Social" ;;
        home)       run_test integration_test/home_settings_nav_test.dart   "Home, Settings, Navigation" ;;
        settings)   run_test integration_test/home_settings_nav_test.dart   "Home, Settings, Navigation" ;;
        nav)        run_test integration_test/home_settings_nav_test.dart   "Home, Settings, Navigation" ;;
        sync)       run_test integration_test/sync_oplog_test.dart          "Sync, Conflict, Oplog" ;;
        remaining)  run_test integration_test/remaining_features_test.dart  "Remaining Features" ;;
        *)          run_test "integration_test/${1}_test.dart"              "$1" ;;
    esac
fi
