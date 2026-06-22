# Per-Tab Accent Color Theming — Analysis & Changes

## Color Mapping

| Tab | Feature | Color | Constant | Hex |
|-----|---------|-------|----------|-----|
| 0 | Home | Blue | `brandBlue` | #2D6CDF |
| 1 | Notes | Purple | `brandPurple` | #7B61FF |
| 2 | Prayers | Blue | `brandBlue` | #2D6CDF |
| 3 | Bible | Green | `emerald` | #27AE60 |
| 4 | Promises | Dark Pink | `rosePink` | #E74C6F |
| 5 | Songs | Orange | `orange` | #FF9F43 |
| 6 | Social | Teal | `teal` | #4ECDC4 |

## Files Changed

### Core
- `lib/core/theme/app_theme.dart` — Updated `tabColors` array

### Home Dashboard
- `lib/features/home/presentation/widgets/overview_grid.dart` — Promises card: coral → rosePink
- `lib/features/home/presentation/widgets/quick_actions_row.dart` — Promise action: coral → rosePink

### Shared Cards
- `lib/shared/widgets/cards/promise_card.dart` — coral → rosePink
- `lib/shared/widgets/cards/song_card.dart` — brandPurple (chords badge) → orange

### Songs Feature (brandPurple → orange)
- `lib/features/songs/presentation/screens/songs_home_screen.dart` — checkboxes, selection, folder icons
- `lib/features/songs/presentation/screens/song_detail_screen.dart` — transpose bar, music icons, chords, tab selector
- `lib/features/songs/presentation/screens/song_search_screen.dart` — key/scale badges
- `lib/features/songs/presentation/screens/add_song_screen.dart` — chord input fields

### Promises Feature (coral/brandBlue → rosePink)
- `lib/features/promises/presentation/screens/promises_list_screen.dart` — FAB
- `lib/features/promises/presentation/screens/promise_detail_screen.dart` — linked prayer icon
- `lib/features/promises/presentation/screens/add_promise_screen.dart` — active status color

### Groups Feature (brandBlue → teal)
- `lib/features/groups/presentation/screens/groups_list_screen.dart` — FAB, create button
- `lib/features/groups/presentation/screens/create_group_screen.dart` — type chips, create button
- `lib/features/groups/presentation/screens/manage_members_screen.dart` — add button, role indicators
- `lib/features/groups/presentation/screens/group_detail_screen.dart` — tabs, icons, FABs, action buttons (PrayerStatus.active kept as brandBlue — semantic)
- `lib/features/groups/presentation/widgets/group_card.dart` — church group color
- `lib/features/groups/presentation/widgets/announcement_card.dart` — pin indicator

### Friends Feature (brandBlue → teal)
- `lib/features/friends/presentation/widgets/friend_card.dart` — avatar
- `lib/features/friends/presentation/widgets/friend_request_card.dart` — avatar, accept button
- `lib/features/friends/presentation/screens/friends_list_screen.dart` — pending badge, add button
- `lib/features/friends/presentation/screens/friend_requests_screen.dart` — tab indicator
- `lib/features/friends/presentation/screens/username_search_screen.dart` — search border, add button
- `lib/features/friends/presentation/screens/profile_settings_screen.dart` — save button, avatar, toggle

## Intentionally NOT Changed
- **Prayers feature** — Already uses `brandBlue` (matches "blue")
- **Notes feature** — Already uses `brandPurple` (matches "purple")
- **Bible feature** — Already uses `emerald`/`bibleGreen` (matches "green")
- **PrayerStatus.active** in group_detail_screen — Semantic color (active prayer = blue), not tab accent
- **Auth/onboarding screens** — Brand colors, not tab-specific
- **Diff view colors** — Semantic (red=removed, green=added)
- **Shared dialogs** — Used in notes context, purple is correct
