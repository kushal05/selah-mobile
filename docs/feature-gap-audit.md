# Feature Gap Audit (Implementation vs `docs/features.md`)

Date: 2026-02-12
Last verified: 2026-02-14

## Summary
- Core modules are largely present: Notes, Prayers, Promises, Songs, People, Friends, Groups, and Sync.
- Most gap items have been resolved. Remaining items are UI enhancements, missing dashboard sections, and non-functional hardening.

**Totals:** 7 fully implemented, 1 partially done (prayer dashboard). All 17 previously pending schema/data items resolved. 15 items remain pending (see consolidated list at bottom).

## 1. Notes Module
### Implemented
- Rich editor with multiple block types, inline formatting, undo/redo, and autosave.
- Folder CRUD and nested hierarchy.
- Note metadata fields exist (date, preacher, tags).
- Bible reference insertion via `@` trigger exists.

### Pending / Partial
- Folder move/reorder UX is incomplete.
  - Repository layer supports `updateFolder(parentId:)` with circular-reference checking, but no UI exposes folder move or reorder.
  - No explicit `order_index` or `sortOrder` field; list order is hardcoded alphabetical.
  - No dedicated folder move UI flow (only create/rename/delete in folder manager).
- Root folder invariant is not explicitly enforced in schema/repository.
  - Spec says root folder must always exist and cannot be deleted.
- Folder restore (optional) is not implemented.
- Metadata filtering is incomplete.
  - Global search is present, but metadata-specific filtering (date/preacher/tags) is limited.

## 2. Promises & Conditions Module
### Implemented
- Promise CRUD with reference, promise text, notes, tags, favorite status.
- UI supports adding multiple conditions with status.

### Pending / Partial
- ✅ ~~Conditions serialized into `notes` string~~ — `PromiseConditions` Drift table with `PromiseConditionModel` + `PromiseConditionRepository` (CRUD + oplog). Schema v10.
- ✅ ~~Tags stored as comma-separated text~~ — `SyncPromiseTags` junction table with `PromiseTagModel` + `PromiseTagRepository` (diff-based `setTagsForPromise`). Schema v10.

## 3. Prayers Module
### Implemented
- Prayer CRUD with status and frequency.
- Prayer logs table and log repository exist.
- Pray Today screen exists with sequential flow and progress.
- Sharing/collaboration entities and UI exist (shared prayer + collaborators).
- ✅ ~~Prayer detail "Log Prayer" button only shows snackbar~~ — Now fully writes to `prayer_logs` table transactionally, then shows confirmation.
- ✅ ~~Pray Today flow: dialog interruption, session immutability~~ — Dialog has optional note field. Session immutability enforced via `_loggedPrayerIds` set + `sessionDate` grouping.

### Pending / Partial
- ✅ ~~Reminder date/time in JSON metadata~~ — Dedicated `reminderAt` (nullable `IntColumn`) added to `SyncPrayers` table. Recurrence is handled via the existing `PrayerFrequency` enum on the `frequency` field (daily/weekdays/weekly/monthly/asNeeded), not a separate `reminderRecurrence` column. Schema v10.
- ✅ ~~Linked people/tags encoded in `category` field~~ — `SyncPrayerTags` + `SyncPrayerPeople` junction tables with models + repositories. Schema v10.
- ✅ ~~Prayer updates encoded in `prayer.content`~~ — `PrayerUpdates` Drift table with `PrayerUpdateModel` + `PrayerUpdateRepository` (CRUD + oplog). Schema v10.
- ✅ ~~Detail screen linked people read-only~~ — Prayer detail now has add/remove people management UI.
- ⚠️ **PARTIALLY DONE** — Dashboard shows Active/Answered/Archived/All counts. Missing: People cards, Starter Prayer Content, Prayer Log History, global Updates feed.
- Global updates feed (filter by prayer/person/tag) is not implemented as a separate module.

## 4. Songs Module
### Implemented
- Song entity supports lyrics/chords, language, tags, book, key, favorites.
- Lyrics-only and chord view modes exist.
- Fullscreen, share lyrics, edit/delete/favorite are implemented.
- Search screen supports text + tag + key + folder filters.
- ✅ ~~Duplicate song action not implemented~~ — Complete: popup menu item + `_duplicateSong()` handler + `songRepository.duplicateSong()`.

### Pending / Partial
- ✅ ~~No folder tree browsing on home screen~~ — Collapsible folder tree section with recursive hierarchy, expand/collapse, active folder highlighting, and song count per folder.
- ✅ ~~Multi-select/bulk song actions~~ — Long-press enters select mode with checkbox UI, bulk move (via FolderSelectionDialog) and bulk delete with confirmation.
- ✅ ~~Folder subtree filter~~ — Songs home screen filters by selected folder ID. Swipe-to-move action added for individual songs.

## 5. Cross-Cutting: Tags, Search, Audit
### Implemented
- Tags exist across multiple modules.
- Global search exists across Notes/Prayers/Promises/People/Songs.
- Prayer logs and sync timestamps exist.
- ✅ ~~Central tag management not implemented~~ — `tagRepository.renameTag()` and `tagRepository.mergeTags()` both implemented with oplog sync. No dedicated management screen yet — available at repo level and inline in metadata panel.

### Pending / Partial
- ✅ ~~Global search text input only~~ — Entity type filter chips (All/Songs/Notes/Prayers/Promises/People) added with toggle multi-select. Results filtered by active selections.
- ❌ **STILL PENDING** — Notes version history: `version` field incremented and oplog entries created, but no history retrieval methods, screen, or diff viewer.

## 6. Bible Reference Feature (New Features Section)
### Implemented
- `@` trigger in editor and Bible picker flow.
- Bible reference blocks with edit/change-version/copy/remove actions.
- Local verse lookup support through Bible DB.

### Pending / Partial
- Picker is missing some spec details:
  - Book search input (e.g., "Gen", "1 Cor") not present in picker UI.
  - OT/NT tab switcher is not explicit (current UI shows sections, not tabs).
  - Verse preview snippets in selection step are not shown.
- Data model behavior differs from spec:
  - Current insert path stores coordinates and resolves verse text dynamically instead of storing a verse text snapshot at insert time.
- Offline "pending download then auto-fill later" flow is not implemented as described (current approach expects local DB availability).

## 7. Shareable/Collaborative Prayers
### Implemented
- Shared prayer metadata, collaborator roles, sharing UI, collaborator management UI.
- Backend sync routes include social entity support and fan-out hooks.
- ✅ ~~Permission enforcement not reflected in UI~~ — `_PrayerPermissions` class computes `canEdit/canLog/canAddUpdates/canManageSharing` from `SharedPrayerModel` flags + collaborator role. UI buttons consistently disabled/hidden based on permissions.

### Pending / Partial
- ✅ ~~No user attribution on updates~~ — `PrayerUpdateModel` stores `userId`; `TimelineItem` now shows author name (resolved from collaborator usernames). Prayer detail displays "You" or collaborator username on each update.

## 8. Friends Feature
### Implemented
- Username profile, username search, send/accept/reject requests, friendships list, blocking UI hooks.
- ✅ ~~Friend-request opt-out not enforced~~ — `sendRequest()` checks target's `friendRequestsEnabled` and throws `FriendRequestValidationException`. Toggle in ProfileSettingsScreen.

### Pending / Partial
- ✅ ~~`@username` mention support~~ — Add Update bottom sheet shows collaborator `@username` chips for quick insertion. `TimelineItem` renders `@username` patterns in bold purple via `RichText` with regex parsing.

## 9. Church Community Groups
### Implemented
- Group CRUD, membership roles, join via code, member management, announcements, group prayer linkage.
- ✅ ~~Leave-group / access revocation UX limited~~ — Leave button with confirmation dialog in group detail. Admin removal via ManageMembersScreen. Both with proper error handling.

### Pending / Partial
- ✅ ~~Group type enum missing `ministry`~~ — `ministry` added to `GroupType` enum with DB serialization.
- ✅ ~~No `joinPolicy` field~~ — `joinPolicy` column added to `SyncGroups` table + `GroupModel` + `GroupRepository`. Schema v10. Actual enum values are `codeOnly` (displays as "Invite Only") and `open`. Note: the `approval` join policy from the spec is **not implemented** — only two policies exist.
- ✅ ~~Group prayer completion stats~~ — Prayers tab shows Active/Answered/Archived stat chips, actual prayer titles (cross-referenced from PrayerModel), status badges, and tap-to-navigate. Stats computed from linked prayer statuses.

## 10. Non-Functional Expectations
### Likely Covered
- Offline-first architecture with local Drift + sync engine is present.
- Sync oplog/versioning/user ownership fields are broadly implemented.

### Still Needs Hardening / Verification
- Stress/performance validation on large datasets is not documented in code/tests.
- End-to-end regression coverage for all social/group/collaboration permission paths appears incomplete.

## Appendix: Consolidated Pending Items

All items confirmed still pending as of 2026-02-14:

### Notes
1. Folder move/reorder UI (repo supports it, no UI)
2. Root folder deletion guard (no schema or repo-level enforcement)
3. Folder restore/undelete
4. Metadata-specific filtering on notes (date/preacher/tags)

### Prayers
5. Prayer dashboard: People cards section
6. Prayer dashboard: Starter Prayer Content section
7. Prayer dashboard: Prayer Log History section
8. Global updates feed (filter by prayer/person/tag) as separate module

### Bible Reference Picker
9. Book search input (e.g., "Gen", "1 Cor")
10. OT/NT testament tab switcher
11. Verse preview snippets in selection step

### Cross-Cutting
12. Notes version history (retrieval methods, screen, diff viewer)
13. Dedicated tag management screen (repo methods exist, no standalone UI)

### Groups
14. `approval` join policy (spec calls for 3 policies; only `codeOnly`/`open` exist)

### Non-Functional
15. Stress/performance testing and E2E regression coverage for social/collaboration paths

## Appendix: Schema Version Reference

Current schema version: **v12**

| Version | Tables Added |
|---------|-------------|
| v9 | `PrayerUpdates` |
| v10 | `PromiseConditions`, `SyncPromiseTags`, `SyncPrayerTags`, `SyncPrayerPeople`, `joinPolicy` on Groups |
| v12 | `SyncSongTags` (migrated from comma-separated) |
