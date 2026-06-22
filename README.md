# Selah — Flutter App

## Build Commands

All commands must be run from the `notify/` directory.

### Run on device (development)

```bash
# QA
flutter run --flavor qa --dart-define-from-file=flavors/qa.json

# Production
flutter run --flavor production --dart-define-from-file=flavors/production.json
```

---

### Generate APK

#### QA Debug
```bash
flutter build apk --flavor qa --debug --dart-define-from-file=flavors/qa.json
```
Output: `build/app/outputs/flutter-apk/selah-qa-debug.apk`

#### QA Release
```bash
flutter build apk --flavor qa --release --dart-define-from-file=flavors/qa.json
```
Output: `build/app/outputs/flutter-apk/selah-qa-release.apk`

#### Production Debug
```bash
flutter build apk --flavor production --debug --dart-define-from-file=flavors/production.json
```
Output: `build/app/outputs/flutter-apk/selah-production-debug.apk`

#### Production Release
```bash
flutter build apk --flavor production --release --dart-define-from-file=flavors/production.json
```
Output: `build/app/outputs/flutter-apk/selah-production-release.apk`

---

### Install on connected device

#### QA Debug
```bash
flutter install --flavor qa --debug --dart-define-from-file=flavors/qa.json
```

#### QA Release
```bash
flutter install --flavor qa --release --dart-define-from-file=flavors/qa.json
```

#### Production Debug
```bash
flutter install --flavor production --debug --dart-define-from-file=flavors/production.json
```

#### Production Release
```bash
flutter install --flavor production --release --dart-define-from-file=flavors/production.json
```

---

### Install a pre-built APK via adb

```bash
# QA Debug
adb install build/app/outputs/flutter-apk/selah-qa-debug.apk

# QA Release
adb install build/app/outputs/flutter-apk/selah-qa-release.apk

# Production Debug
adb install build/app/outputs/flutter-apk/selah-production-debug.apk

# Production Release
adb install build/app/outputs/flutter-apk/selah-production-release.apk
```

Use `adb install -r` to reinstall over an existing build without uninstalling first.
