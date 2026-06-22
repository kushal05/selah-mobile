Below is a **1:1 Flutter navigation alternative** for your Compose navigation spec.

It follows the **same principles**, **same mental model**, and **same guarantees**:

* Single root navigator
* Bottom tabs are **roots**
* Detail screens are **never roots**
* ID-based routing
* Deep-link safe
* Back-stack isolation per tab
* Production-grade & future-proof

You can save this as:

```
NAVIGATION_SPEC_FLUTTER.md
```

and treat it as the **authoritative Flutter navigation reference**.

---

# 🧭 APP NAVIGATION SPEC (FLUTTER)

**Flutter – Notes / Prayers / Promises**
**Navigator 2.0 via `go_router` (recommended)**

> Why `go_router`?
>
> * Declarative
> * Deep-link ready
> * Nested navigation
> * Bottom-tab back-stack preservation
> * Official Flutter team package

---

## 0️⃣ Navigation Design Principles (DO NOT SKIP)

These are **identical** to your Compose rules.

### Non-Negotiables

* One **root router**
* Bottom tabs are **navigation roots**
* Detail screens are **never roots**
* IDs are passed via **path parameters**
* Navigation logic stays **out of widgets**
* Each tab maintains its **own back stack**

---

## 1️⃣ Route Definitions (Single Source of Truth)

> These paths must **never change casually**
> Safe for **deep links**, **analytics**, and **restoration**

```dart
// navigation/routes.dart
abstract class Routes {
  /* ───────────── Root ───────────── */
  static const home = '/home';

  /* ───────────── Search ───────────── */
  static const search = '/search';

  /* ───────────── Notes ───────────── */
  static const notesHome = '/notes';
  static const noteDetail = '/notes/:noteId';

  /* ───────────── People ───────────── */
  static const people = '/people';
  static const personDetail = '/people/:personId';

  /* ───────────── Prayers ───────────── */
  static const prayers = '/prayers';
  static const prayerDetail = '/prayers/:prayerId';

  /* ───────────── Promises ───────────── */
  static const promises = '/promises';
  static const promiseDetail = '/promises/:promiseId';
}
```

---

## 2️⃣ Bottom Navigation Definition

Flutter equivalent of your `BottomNavItem` sealed class.

```dart
// navigation/bottom_nav_item.dart
import 'package:flutter/material.dart';
import 'routes.dart';

class BottomNavItem {
  final String route;
  final String label;
  final IconData icon;

  const BottomNavItem(this.route, this.label, this.icon);
}

const bottomNavItems = [
  BottomNavItem(Routes.home, 'Home', Icons.home),
  BottomNavItem(Routes.notesHome, 'Notes', Icons.description),
  BottomNavItem(Routes.prayers, 'Prayers', Icons.favorite),
  BottomNavItem(Routes.promises, 'Promises', Icons.bookmark),
  BottomNavItem(Routes.people, 'More', Icons.menu),
];
```

---

## 3️⃣ Root Router (Single Source of Truth)

This replaces **NavHost**.

```dart
// navigation/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'routes.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final homeTabKey = GlobalKey<NavigatorState>();
final notesTabKey = GlobalKey<NavigatorState>();
final prayersTabKey = GlobalKey<NavigatorState>();
final promisesTabKey = GlobalKey<NavigatorState>();
final peopleTabKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  routes: [
    /// SEARCH (global overlay)
    GoRoute(
      path: Routes.search,
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, __) => const GlobalSearchScreen(),
    ),

    /// SHELL = Bottom Tabs
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return AppScaffold(shell: navigationShell);
      },
      branches: [
        _homeBranch(),
        _notesBranch(),
        _prayersBranch(),
        _promisesBranch(),
        _peopleBranch(),
      ],
    ),
  ],
);
```

---

## 4️⃣ Bottom-Tab Navigation (Back-Stack Safe)

This is the **Flutter equivalent of nested graphs**.

### 4.1 Home Branch

```dart
StatefulShellBranch _homeBranch() {
  return StatefulShellBranch(
    navigatorKey: homeTabKey,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (_, __) => const HomeDashboardScreen(),
      ),
    ],
  );
}
```

---

### 4.2 Notes Branch

```dart
StatefulShellBranch _notesBranch() {
  return StatefulShellBranch(
    navigatorKey: notesTabKey,
    routes: [
      GoRoute(
        path: Routes.notesHome,
        builder: (_, __) => const NotesHomeScreen(),
        routes: [
          GoRoute(
            path: ':noteId',
            builder: (context, state) {
              final id = state.pathParameters['noteId']!;
              return NoteDetailScreen(noteId: id);
            },
          ),
        ],
      ),
    ],
  );
}
```

---

### 4.3 Prayers Branch

```dart
StatefulShellBranch _prayersBranch() {
  return StatefulShellBranch(
    navigatorKey: prayersTabKey,
    routes: [
      GoRoute(
        path: Routes.prayers,
        builder: (_, __) => const PrayersDashboardScreen(),
        routes: [
          GoRoute(
            path: ':prayerId',
            builder: (context, state) {
              final id = state.pathParameters['prayerId']!;
              return PrayerDetailScreen(prayerId: id);
            },
          ),
        ],
      ),
    ],
  );
}
```

---

### 4.4 Promises Branch

```dart
StatefulShellBranch _promisesBranch() {
  return StatefulShellBranch(
    navigatorKey: promisesTabKey,
    routes: [
      GoRoute(
        path: Routes.promises,
        builder: (_, __) => const PromisesListScreen(),
        routes: [
          GoRoute(
            path: ':promiseId',
            builder: (context, state) {
              final id = state.pathParameters['promiseId']!;
              return PromiseDetailScreen(promiseId: id);
            },
          ),
        ],
      ),
    ],
  );
}
```

---

### 4.5 People Branch

```dart
StatefulShellBranch _peopleBranch() {
  return StatefulShellBranch(
    navigatorKey: peopleTabKey,
    routes: [
      GoRoute(
        path: Routes.people,
        builder: (_, __) => const PeopleListScreen(),
        routes: [
          GoRoute(
            path: ':personId',
            builder: (context, state) {
              final id = state.pathParameters['personId']!;
              return PersonDetailScreen(personId: id);
            },
          ),
        ],
      ),
    ],
  );
}
```

---

## 5️⃣ App Scaffold (Bottom Tabs)

Flutter equivalent of Compose `Scaffold + BottomNav`.

```dart
class AppScaffold extends StatelessWidget {
  final StatefulNavigationShell shell;

  const AppScaffold({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: shell.currentIndex,
        onTap: shell.goBranch,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: 'Notes'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Prayers'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Promises'),
          BottomNavigationBarItem(icon: Icon(Icons.menu), label: 'More'),
        ],
      ),
    );
  }
}
```

---

## 6️⃣ Navigation Helpers (Strongly Recommended)

Exact Flutter equivalent of `NavActions`.

```dart
// navigation/nav_actions.dart
import 'package:go_router/go_router.dart';

class NavActions {
  final GoRouter router;

  NavActions(this.router);

  void openNote(String id) => router.go('/notes/$id');
  void openPrayer(String id) => router.go('/prayers/$id');
  void openPerson(String id) => router.go('/people/$id');
  void openPromise(String id) => router.go('/promises/$id');
  void search() => router.push('/search');
  void back() => router.pop();
}
```

---

## 7️⃣ Back-Stack Rules (Guaranteed)

| Action           | Result                     |
| ---------------- | -------------------------- |
| Bottom tab click | Switches root branch       |
| Detail screen    | Pushes within tab stack    |
| Back press       | Pops one level             |
| Switching tabs   | Preserves each tab stack   |
| Search           | Global overlay (root)      |
| Deep link        | Lands correctly with stack |

---

## 8️⃣ Navigation Flow Diagram (Same Mental Model)

```
HOME
 ├─ Search
 │   ├─ Note Detail
 │   ├─ Prayer Detail
 │   ├─ Person Detail
 │   └─ Promise Detail
 │
 ├─ Notes ── Note Detail
 │
 ├─ Prayers ── Prayer Detail
 │
 ├─ Promises ── Promise Detail
 │
 └─ People ── Person Detail ── Prayer Detail
```

---

## 9️⃣ What You Can Plug In Immediately

✅ go_router
✅ Nested tab navigation
✅ ID-based routing
✅ Deep-link safe
✅ Back-stack preservation
✅ Clean separation of concerns

---