#!/bin/bash
# ──────────────────────────────────────────────
# Run Maestro UI Tests on a connected device
# ──────────────────────────────────────────────
#
# Usage:
#   ./run_maestro_tests.sh              # Run ALL Maestro flows
#   ./run_maestro_tests.sh 01           # Run only auth flows
#   ./run_maestro_tests.sh 02           # Run only notes flows
#   ./run_maestro_tests.sh <filename>   # Run a specific flow file
#
# Prerequisites:
#   - Maestro CLI installed: curl -Ls "https://get.maestro.mobile.dev" | bash
#   - Physical device or emulator connected (check: adb devices)
#   - App installed on device (flutter install)

set -e
cd "$(dirname "$0")"

echo "═══════════════════════════════════════════"
echo " Notify App — Maestro UI Tests"
echo "═══════════════════════════════════════════"
echo ""

# Check Maestro is installed
if ! command -v maestro &> /dev/null; then
    echo "ERROR: Maestro CLI not found."
    echo ""
    echo "Install it with:"
    echo "  curl -Ls \"https://get.maestro.mobile.dev\" | bash"
    echo ""
    echo "Or on Windows (PowerShell):"
    echo "  iex ((New-Object System.Net.WebClient).DownloadString('https://get.maestro.mobile.dev'))"
    echo ""
    exit 1
fi

# Check device connected
if ! adb devices 2>/dev/null | grep -q "device$"; then
    echo "WARNING: No Android device detected via adb."
    echo "Make sure a device/emulator is connected."
    echo ""
fi

run_flow() {
    local flow_file=$1
    local name=$2
    echo "──────────────────────────────────────────"
    echo "Running: $name"
    echo "Flow:    $flow_file"
    echo "──────────────────────────────────────────"
    maestro test "$flow_file" 2>&1
    echo ""
}

if [ -z "$1" ] || [ "$1" = "all" ]; then
    echo "Running ALL Maestro flows..."
    echo ""
    for flow_file in maestro/[0-9]*.yaml; do
        name=$(basename "$flow_file" .yaml)
        run_flow "$flow_file" "$name"
    done
    echo "═══════════════════════════════════════════"
    echo " ALL MAESTRO FLOWS COMPLETE"
    echo "═══════════════════════════════════════════"
else
    case "$1" in
        01|auth)        run_flow maestro/01_auth_onboarding.yaml     "Auth & Onboarding" ;;
        02|notes)       run_flow maestro/02_notes.yaml                "Notes" ;;
        03|folders)     run_flow maestro/03_folders.yaml               "Folders" ;;
        04|prayers)     run_flow maestro/04_prayers.yaml               "Prayers" ;;
        05|promises)    run_flow maestro/05_promises.yaml              "Promises" ;;
        06|songs)       run_flow maestro/06_songs.yaml                 "Songs" ;;
        07|people)      run_flow maestro/07_people.yaml                "People" ;;
        08|bible)       run_flow maestro/08_bible.yaml                 "Bible" ;;
        09|search)      run_flow maestro/09_search.yaml                "Search" ;;
        10|tags)        run_flow maestro/10_tags.yaml                  "Tags" ;;
        11|social)      run_flow maestro/11_social.yaml                "Social" ;;
        12|home)        run_flow maestro/12_home_settings.yaml         "Home & Settings" ;;
        13|nav)         run_flow maestro/13_navigation.yaml            "Navigation" ;;
        14|offline)     run_flow maestro/14_offline.yaml               "Offline" ;;
        15|history)     run_flow maestro/15_version_history.yaml       "Version History" ;;
        16|perf)        run_flow maestro/16_performance.yaml           "Performance" ;;
        *)              run_flow "maestro/${1}.yaml"                   "$1" ;;
    esac
fi
