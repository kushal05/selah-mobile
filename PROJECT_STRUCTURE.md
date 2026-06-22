# Project Structure

This Flutter application follows a feature-based architecture with clean separation of concerns.

## Folder Organization

```
lib/
├── core/                           # Core functionality
│   ├── navigation/                 # Navigation configuration
│   │   ├── app_router.dart        # Main router with go_router
│   │   ├── bottom_nav_item.dart   # Bottom navigation configuration
│   │   ├── nav_actions.dart       # Type-safe navigation actions
│   │   └── routes.dart            # Route path constants
│   └── theme/                      # Theme configuration
│       └── app_theme.dart         # Material 3 theme
│
├── features/                       # Feature modules
│   ├── home/                      # Home/Dashboard
│   │   └── presentation/
│   │       ├── screens/
│   │       │   └── home_dashboard_screen.dart
│   │       └── widgets/
│   │           ├── daily_focus_card.dart
│   │           ├── quick_actions_row.dart
│   │           └── overview_grid.dart
│   │
│   ├── notes/                     # Notes module
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── notes_home_screen.dart
│   │       │   └── note_detail_screen.dart
│   │       └── widgets/
│   │           ├── folder_row.dart
│   │           ├── note_row.dart
│   │           └── metadata_row.dart
│   │
│   ├── prayers/                   # Prayers module
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── prayers_dashboard_screen.dart
│   │       │   └── prayer_detail_screen.dart
│   │       └── widgets/
│   │           └── prayer_focus_card.dart
│   │
│   ├── promises/                  # Promises module
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── promises_list_screen.dart
│   │       │   └── promise_detail_screen.dart
│   │       └── widgets/
│   │           ├── promise_card.dart
│   │           └── condition_row.dart
│   │
│   ├── people/                    # People module
│   │   └── presentation/
│   │       ├── screens/
│   │       │   ├── people_list_screen.dart
│   │       │   └── person_detail_screen.dart
│   │       └── widgets/
│   │           ├── person_card.dart
│   │           └── linked_card.dart
│   │
│   └── search/                    # Global search
│       └── presentation/
│           ├── screens/
│           │   └── global_search_screen.dart
│           └── widgets/
│               ├── search_section.dart
│               └── search_row.dart
│
└── shared/                        # Shared widgets and utilities
    └── widgets/
        ├── app_scaffold.dart      # Bottom navigation scaffold
        ├── bullet.dart            # Bulleted list item
        ├── checkbox_row.dart      # Checkbox with label
        ├── status_chip.dart       # Status badge
        ├── tag_row.dart           # Tag display row
        └── timeline_item.dart     # Timeline entry
```

## Architecture Principles

### 1. Feature-Based Organization
Each major feature (Notes, Prayers, Promises, People) has its own folder containing:
- **screens/**: Full-page screens
- **widgets/**: Feature-specific reusable components

### 2. Separation of Concerns
- **core/**: App-wide configuration (theme, navigation)
- **features/**: Business logic organized by domain
- **shared/**: Cross-feature reusable components

### 3. Navigation Architecture
Following the specification from `docs/navigation.md`:
- Single root navigator with `go_router`
- Bottom tabs maintain isolated back stacks
- Type-safe navigation via `NavActions`
- Deep-link ready with path parameters

### 4. Design System
Material 3 design with:
- Consistent color scheme (primary: #2D6CDF, secondary: #7B61FF)
- Typography scale from Material Design
- Reusable component library in `shared/widgets/`

## Key Files

- **[main.dart](lib/main.dart)**: Application entry point
- **[app_router.dart](lib/core/navigation/app_router.dart)**: Complete navigation graph
- **[app_theme.dart](lib/core/theme/app_theme.dart)**: Theme configuration
- **[routes.dart](lib/core/navigation/routes.dart)**: Centralized route paths

## Next Steps

1. **Install dependencies**: Run `flutter pub get` to install `go_router`
2. **Data layer**: Add domain and data layers for each feature
3. **State management**: Integrate Provider/Riverpod/Bloc
4. **API integration**: Connect to backend services
5. **Local storage**: Implement offline-first with Isar/Hive
6. **Rich text editor**: Add a proper editor for notes (e.g., flutter_quill)

## Dependencies

Current dependencies in `pubspec.yaml`:
- `flutter`: SDK
- `go_router: ^14.6.2`: Navigation
- `flutter_lints: ^6.0.0`: Linting (dev)

## Running the App

```bash
# Get dependencies
flutter pub get

# Run on your device/emulator
flutter run
```

## Design Specifications

All screens follow the designs in:
- [features.md](docs/features.md) - Feature requirements
- [screens.md](docs/screens.md) - Screen implementations
- [navigation.md](docs/navigation.md) - Navigation rules
