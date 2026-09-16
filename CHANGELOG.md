# Changelog

All notable changes to Selah. Dates are release dates; the build number in
parentheses matches `version:` in `pubspec.yaml`.

## 0.2.4+32 — 17 September 2026

**If you are on build 30 or 31, this is the one that will install.** Those two
were signed with the wrong key and Android refused them; this is signed with
the same key as 29 and earlier.

### Tags

- **Write `#faith` in a note and it becomes a tag.** The word is tinted purple
  as you type, and reads the same way when you open the note later. Delete the
  text and the tag goes with it.
- **Tag a verse.** Expand a Bible reference in a note and there is a tag
  control in its bottom-right corner. The tag applies to the whole reference
  and is added to the note's tags too.
- **Verse tags show while you read.** A tagged verse carries its tags at the
  bottom right in the Bible reader, from every note that tagged it. Tap one to
  see the notes that carry it.
- **`Faith` and `faith` are now one tag.** Tags are lowercase, and existing
  ones are folded together the first time you open this build. Tags on
  prayers and promises used to be silently lost when two tags were merged;
  they are carried over now, and a merge reaches your other devices.

### The app no longer tells you things it does not know

- **Your habits.** A tap on a habit whose state had not loaded yet deleted the
  completion it could not see — the tap that was meant to record it destroyed
  it instead. Both places this appeared are fixed, and a habit whose state is
  unknown no longer looks "not done".
- **Bookmarking a chapter** had the same fault: a tap before the bookmark
  loaded removed it.
- **Highlights, bookmarks and streaks** now say when they could not be loaded,
  instead of showing an empty page, a missing strip, or "0 days" — each of
  which reads as "your data is gone".
- **Home** no longer says "No active prayers" while it is still reading.

### Bible

- **No Bible downloaded?** The verse picker now offers the download in its
  first step, instead of letting you pick a book, chapter and verse before
  coming up empty. Bible search does the same.
- **Opening a chapter with no Bible installed used to crash the screen.**
- **Highlights are saved properly.** Saving, editing and removing one was
  never waited on, so a failure was silent — the highlight simply did not
  appear, or would not delete.
- **The reference picker is legible in dark mode.** Its close button was
  near-invisible, and the book names sat at 2:1 contrast.

### Elsewhere

- Quick Actions show a bar underneath so it is clear the row scrolls, the
  folder lays out as a proper grid, and the tiles share one height.
- More dark-mode contrast fixes across notes, settings, trash and search.

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
