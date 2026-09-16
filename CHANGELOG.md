# Changelog

All notable changes to Selah. Dates are release dates; the build number in
parentheses matches `version:` in `pubspec.yaml`.

## 0.2.3+31 — 16 September 2026

- **The "update available" prompt no longer vanishes on its own.** It appeared
  during startup and was wiped a moment later by the app navigating to the
  home screen — too fast to read, let alone act on. It now waits until the app
  has settled and stays until you choose Update or Later.

## 0.2.2+30 — 16 September 2026

The first release after a full accessibility and UX pass. Most of this is
visible: the home screen, dark mode, and the places the app used to tell you
the wrong thing.

### Home

- **Quick Actions now reach the whole app.** The row scrolls and carries seven
  actions instead of four — New Promise, Songs and Add person were previously
  only reachable through the More tab. **See more** opens all of them at once.
- **The daily card is a carousel.** Today's prayer, a verse you saved, and
  wherever your Bible reading stopped. It advances on its own, loops in both
  directions, and stops as soon as you swipe it yourself.
- Quick action tiles are translucent, and the folder is frosted glass.

### Fixed things that were telling you something untrue

- **Trash said "Trash is empty" when it had failed to load.** It now says what
  went wrong and offers to retry, and only claims to be empty when it knows.
- **Dates disagreed with each other.** One screen showed "Sep 15, 2026" and
  another "15 Sep". All dates now follow one format and your device's locale.
- Prayers created inside a group could attach the wrong prayer to the group.

### Dark mode

- The Bible translation chip, the Notes filter chips, several text fields, the
  revision diff view and the Settings cards were all rendering light-theme
  colours on a dark background.
- Text and icon colours across the app now meet WCAG contrast in both themes.

### Reading and navigation

- **Bible search had no back button.** It does now.
- Tab headings are the same size and position on every tab.
- Section headings in Settings line up with the cards they introduce.

### Under the hood

- Every user-facing string moved into the localisation files, so the app can
  be translated without touching code.
- Minimum iOS raised to 15 (required by Xcode 27; no supported device is
  affected).
- Four quality gates now run in CI: static analysis, an accessibility lint, a
  contrast audit across both themes, and 362 tests.

---

*Earlier releases predate this changelog.*
