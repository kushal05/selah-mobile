import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'routes.dart';
import '../sync/providers/sync_providers.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/forgot_password_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/home/presentation/screens/home_dashboard_screen.dart';
import '../../features/home/presentation/screens/weekly_digest_screen.dart';
import '../../features/notes/presentation/screens/notes_home_screen.dart';
import '../../features/notes/presentation/screens/note_detail_screen.dart';
import '../../features/notes/presentation/screens/note_editor_screen.dart';
import '../../features/prayers/presentation/screens/prayers_dashboard_screen.dart';
import '../../features/prayers/presentation/screens/prayer_detail_screen.dart';
import '../../features/prayers/presentation/screens/add_prayer_screen.dart';
import '../../features/promises/presentation/screens/promises_list_screen.dart';
import '../../features/promises/presentation/screens/promise_detail_screen.dart';
import '../../features/promises/presentation/screens/add_promise_screen.dart';
import '../../features/people/presentation/screens/people_list_screen.dart';
import '../../features/people/presentation/screens/person_detail_screen.dart';
import '../../features/people/presentation/screens/add_person_screen.dart';
import '../../features/songs/presentation/screens/songs_home_screen.dart';
import '../../features/songs/presentation/screens/song_detail_screen.dart';
import '../../features/songs/presentation/screens/add_song_screen.dart';
import '../../features/songs/presentation/screens/song_search_screen.dart';
import '../../features/search/presentation/screens/global_search_screen.dart';
import '../../features/bible_search/presentation/screens/bible_search_screen.dart';
import '../../features/bible/presentation/screens/bible_home_screen.dart';
import '../../features/bible/presentation/screens/bible_chapter_screen.dart';
import '../../features/bible/presentation/screens/bible_history_screen.dart';
import '../../features/bible/presentation/screens/memorization_screen.dart';
import '../../features/bible/presentation/screens/memorization_review_screen.dart';
import '../../features/settings/presentation/screens/changelog_screen.dart';
import '../../features/settings/presentation/screens/notification_settings_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/sync_status_screen.dart';
import '../../features/settings/presentation/screens/devices_screen.dart';
import '../../features/prayers/presentation/screens/pray_today_screen.dart';
import '../../features/prayers/presentation/screens/prayer_updates_feed_screen.dart';
import '../domain/enums/prayer_enums.dart';
import '../../features/prayers/presentation/screens/prayer_analytics_screen.dart';
import '../../features/prayers/presentation/screens/prayer_collaborators_screen.dart';
import '../../features/prayers/presentation/screens/prayer_list_screen.dart';
import '../../features/friends/presentation/screens/friends_list_screen.dart';
import '../../features/friends/presentation/screens/friend_requests_screen.dart';
import '../../features/friends/presentation/screens/username_search_screen.dart';
import '../../features/friends/presentation/screens/profile_settings_screen.dart';
import '../../features/auth/presentation/screens/complete_profile_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/groups/presentation/screens/groups_list_screen.dart';
import '../../features/groups/presentation/screens/create_group_screen.dart';
import '../../features/groups/presentation/screens/group_detail_screen.dart';
import '../../features/groups/presentation/screens/manage_members_screen.dart';
import '../../features/tags/presentation/screens/tag_management_screen.dart';
import '../../features/settings/presentation/screens/trash_screen.dart';
import '../../features/bible/presentation/screens/bible_versions_screen.dart';
import '../../features/feedback/presentation/providers/feedback_notification_provider.dart';
import '../../features/home/presentation/providers/widget_sync_coordinator.dart';
import '../services/home_widget_service.dart';
import '../sync/providers/notification_handler_provider.dart';
import '../sync/providers/push_notification_providers.dart';
import '../../features/feedback/presentation/screens/feedback_list_screen.dart';
import '../../features/feedback/presentation/screens/create_feedback_screen.dart';
import '../../features/feedback/presentation/screens/feedback_thread_screen.dart';
import '../../features/social/presentation/screens/social_home_screen.dart';
import '../../features/social/presentation/screens/share_code_screen.dart';
import '../../features/social/presentation/screens/shared_with_me_screen.dart';
import '../../features/notes/presentation/screens/public_note_viewer_screen.dart';
import '../../features/habits/presentation/screens/habits_screen.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'navigator_keys.dart';

export 'navigator_keys.dart';

/// Custom fade+slide page transition for auth routes (300ms).
CustomTransitionPage<void> _authPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.03),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// Returns true for routes that should not be saved as pending deep links
/// (tab roots, home, auth routes — these are default destinations, not
/// deep link targets).
bool _isDefaultRoute(String location) {
  const defaults = {
    Routes.home,
    Routes.notesHome,
    Routes.prayers,
    Routes.bible,
    Routes.promises,
    Routes.songs,
    Routes.social,
    Routes.search,
    Routes.bibleSearch,
  };
  return defaults.contains(location);
}

/// Adapts a Stream to a Listenable for GoRouter refresh.
/// Exposes [notify] so external code (e.g. provider listeners) can also
/// trigger a router re-evaluation.
class _GoRouterRefreshNotifier extends ChangeNotifier {
  _GoRouterRefreshNotifier(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  void notify() => notifyListeners();

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

/// Root application router provider
/// Manages all navigation including auth guard, bottom tabs, and detail screens
final appRouterProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);
  final prefs = ref.watch(sharedPreferencesProvider);

  // Activate the profile completeness watcher so it updates the flag
  // reactively when profile data arrives (e.g. after sync).
  ref.watch(profileCompletenessWatcherProvider);

  // Activate feedback notification watcher for admin replies.
  ref.watch(feedbackNotificationWatcherProvider);

  // Activate FCM token registration and foreground/background message handler.
  ref.watch(fcmTokenRegistrationProvider);
  ref.watch(notificationHandlerProvider);

  // Activate the home-screen widget coordinator so widget data stays in sync
  // with the local database for the lifetime of the app.
  ref.watch(widgetSyncCoordinatorProvider);

  final refreshNotifier =
      _GoRouterRefreshNotifier(authService.authStateChanges);

  // Also refresh the router when profile completeness changes.
  ref.listen<bool?>(profileCompleteProvider, (prev, next) {
    refreshNotifier.notify();
  });

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: Routes.splash,
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final fullUri = state.uri.toString();

      // Home-screen widget taps arrive as `selah://widget/...`. Flutter's
      // platform deep-link handling forwards the raw URI to the router (which
      // can't match a scheme'd location), so translate it to an in-app path
      // here. This also covers the case where the OS, not the home_widget
      // plugin, delivers the launch URI.
      if (state.uri.scheme == 'selah') {
        return HomeWidgetService.widgetUriToAppPath(state.uri) ?? Routes.home;
      }

      // Never redirect away from the splash screen — it handles its own
      // navigation after performing auth / profile checks.
      if (location == Routes.splash) return null;

      // Public share deeplinks bypass the auth guard so recipients without
      // an account can open view-only note links. The viewer screen calls
      // the unauthenticated `/v1/public/notes/:token` endpoint directly.
      if (location.startsWith('/share/')) return null;

      // A user "exists" if a token was ever stored, regardless of expiry.
      // Token refresh is handled by the sync/API layer.
      final hasUser = authService.currentToken != null;
      final isAuthRoute = location.startsWith('/auth') ||
          location == Routes.onboarding;
      final isCompleteProfileRoute = location == Routes.completeProfile;

      // No user? Save deep link destination and send to login/onboarding.
      if (!hasUser && !isAuthRoute) {
        // Save the intended destination so we can resume after login.
        if (!_isDefaultRoute(location)) {
          ref.read(pendingDeepLinkProvider.notifier).state = fullUri;
        }
        final hasSeenOnboarding =
            prefs.getBool('has_seen_onboarding') ?? false;
        return hasSeenOnboarding ? Routes.login : Routes.onboarding;
      }

      // Has user but on auth route? Resume pending deep link or go home.
      if (hasUser && isAuthRoute) {
        final pending = ref.read(pendingDeepLinkProvider);
        if (pending != null) {
          ref.read(pendingDeepLinkProvider.notifier).state = null;
          return pending;
        }
        return Routes.home;
      }

      // Has user: check profile completeness.
      if (hasUser && !isCompleteProfileRoute) {
        final profileComplete = ref.read(profileCompleteProvider);
        if (profileComplete == false) {
          // Preserve the pending deep link while completing profile,
          // but don't overwrite an existing pending link from the auth step.
          final existing = ref.read(pendingDeepLinkProvider);
          if (existing == null && !_isDefaultRoute(location)) {
            ref.read(pendingDeepLinkProvider.notifier).state = fullUri;
          }
          return Routes.completeProfile;
        }
      }

      // On complete-profile but profile is already complete?
      // Resume pending deep link or go home.
      if (hasUser && isCompleteProfileRoute) {
        final profileComplete = ref.read(profileCompleteProvider);
        if (profileComplete == true) {
          final pending = ref.read(pendingDeepLinkProvider);
          if (pending != null) {
            ref.read(pendingDeepLinkProvider.notifier).state = null;
            return pending;
          }
          return Routes.home;
        }
      }

      return null;
    },
    routes: [
      // Splash (initial route)
      GoRoute(
        path: Routes.splash,
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SplashScreen(),
      ),

      // Auth routes (outside shell) — custom fade transition
      GoRoute(
        path: Routes.onboarding,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) => _authPage(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: Routes.login,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) => _authPage(state, const LoginScreen()),
      ),
      GoRoute(
        path: Routes.register,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) => _authPage(state, const RegisterScreen()),
      ),
      GoRoute(
        path: Routes.forgotPassword,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) => _authPage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: Routes.completeProfile,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (_, state) => _authPage(state, const CompleteProfileScreen()),
      ),

      // Search (global overlay)
      GoRoute(
        path: Routes.search,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          key: state.pageKey,
          child: const GlobalSearchScreen(),
          fullscreenDialog: true,
        ),
      ),

      // Public share deeplink — no auth required. Resolves a token and
      // renders a read-only snapshot. Registered at the root so it works
      // before login (users opening a link from someone else).
      GoRoute(
        path: '/share/:token',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return MaterialPage(
            key: state.pageKey,
            child: PublicNoteViewerScreen(token: token),
            fullscreenDialog: true,
          );
        },
      ),

      // Inbox for incoming tier-2 shares (requires auth — falls under the
      // normal auth redirect guard since it lives outside the login paths).
      GoRoute(
        path: '/shared-with-me',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, _) => const SharedWithMeScreen(),
      ),

      // Bible verse search (dedicated, separate from global search)
      GoRoute(
        path: Routes.bibleSearch,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final selectMode =
              state.uri.queryParameters['select'] == 'true';
          return MaterialPage(
            key: state.pageKey,
            child: BibleSearchScreen(selectMode: selectMode),
            fullscreenDialog: true,
          );
        },
      ),

      // Legacy group routes — redirect to Social tab
      GoRoute(
        path: Routes.groups,
        parentNavigatorKey: rootNavigatorKey,
        redirect: (_, _) => Routes.socialGroups,
      ),
      GoRoute(
        path: Routes.groupDetail,
        parentNavigatorKey: rootNavigatorKey,
        redirect: (context, state) {
          final groupId = state.pathParameters['groupId']!;
          return '/social/groups/$groupId';
        },
        routes: [
          GoRoute(
            path: 'members',
            redirect: (context, state) {
              final groupId = state.pathParameters['groupId']!;
              return '/social/groups/$groupId/members';
            },
          ),
        ],
      ),

      // Shell = Bottom Tabs with isolated back stacks
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppScaffold(shell: navigationShell);
        },
        branches: [
          _homeBranch(),
          _notesBranch(),
          _prayersBranch(),
          _bibleBranch(),
          _promisesBranch(),
          _songsBranch(),
          _socialBranch(),
        ],
      ),
    ],
  );

  // Handle the FCM message that launched the app from terminated state.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    handleInitialFcmMessage();
  });

  return router;
});

/// Home tab navigation branch
StatefulShellBranch _homeBranch() {
  return StatefulShellBranch(
    navigatorKey: homeTabKey,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomeDashboardScreen(),
        routes: [
          GoRoute(
            path: 'habits',
            builder: (_, _) => const HabitsScreen(),
          ),
          GoRoute(
            path: 'digest',
            builder: (_, _) => const WeeklyDigestScreen(),
          ),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'sync-status',
                builder: (_, _) => const SyncStatusScreen(),
              ),
              GoRoute(
                path: 'notifications',
                builder: (_, _) => const NotificationSettingsScreen(),
              ),
              GoRoute(
                path: 'changelog',
                builder: (_, _) => const ChangelogScreen(),
              ),
              GoRoute(
                path: 'tags',
                builder: (_, _) => const TagManagementScreen(),
              ),
              GoRoute(
                path: 'trash',
                builder: (_, _) => const TrashScreen(),
              ),
              GoRoute(
                path: 'devices',
                builder: (_, _) => const DevicesScreen(),
              ),
              GoRoute(
                path: 'bible-versions',
                builder: (_, _) => const BibleVersionsScreen(),
              ),
              // Feedback (v22)
              GoRoute(
                path: 'feedback',
                builder: (_, _) => const FeedbackListScreen(),
                routes: [
                  GoRoute(
                    path: 'new',
                    builder: (_, _) => const CreateFeedbackScreen(),
                  ),
                  GoRoute(
                    path: ':threadId',
                    builder: (context, state) {
                      final threadId = state.pathParameters['threadId']!;
                      return FeedbackThreadScreen(threadId: threadId);
                    },
                  ),
                ],
              ),
              // Friends moved to Social tab (v21).
              // Redirect legacy routes for backward compat.
              GoRoute(
                path: 'friends',
                redirect: (_, _) => Routes.socialFriends,
                routes: [
                  GoRoute(
                    path: 'requests',
                    redirect: (_, _) => Routes.socialFriendRequests,
                  ),
                  GoRoute(
                    path: 'search',
                    redirect: (_, _) => Routes.socialFriendsSearch,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Notes tab navigation branch with nested detail route
StatefulShellBranch _notesBranch() {
  return StatefulShellBranch(
    navigatorKey: notesTabKey,
    routes: [
      GoRoute(
        path: Routes.notesHome,
        builder: (_, _) => const NotesHomeScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) {
              final folderId = state.uri.queryParameters['folderId'];
              final initialTitle = state.uri.queryParameters['initialTitle'];
              return NoteEditorScreen(folderId: folderId, initialTitle: initialTitle);
            },
          ),
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

/// Prayers tab navigation branch with nested detail route
StatefulShellBranch _prayersBranch() {
  return StatefulShellBranch(
    navigatorKey: prayersTabKey,
    routes: [
      GoRoute(
        path: Routes.prayers,
        builder: (_, _) => const PrayersDashboardScreen(),
        routes: [
          GoRoute(
            path: 'today',
            builder: (context, state) {
              final logId = state.uri.queryParameters['log'];
              return PrayTodayScreen(logPrayerId: logId);
            },
          ),
          GoRoute(
            path: 'updates',
            builder: (_, _) => const PrayerUpdatesFeedScreen(),
          ),
          GoRoute(
            path: 'list',
            builder: (context, state) {
              final statusParam = state.uri.queryParameters['status'];
              final status = statusParam != null
                  ? PrayerStatus.values.firstWhere(
                      (s) => s.name == statusParam,
                      orElse: () => PrayerStatus.active,
                    )
                  : null;
              return PrayerListScreen(status: status);
            },
          ),
          GoRoute(
            path: 'analytics',
            builder: (_, _) => const PrayerAnalyticsScreen(),
          ),
          GoRoute(
            path: 'new',
            builder: (_, _) => const AddPrayerScreen(),
          ),
          GoRoute(
            path: ':prayerId',
            builder: (context, state) {
              final id = state.pathParameters['prayerId']!;
              return PrayerDetailScreen(prayerId: id);
            },
            routes: [
              GoRoute(
                path: 'collaborators',
                builder: (context, state) {
                  final id = state.pathParameters['prayerId']!;
                  return PrayerCollaboratorsScreen(prayerId: id);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Bible tab with book/chapter browser and chapter reading screen.
StatefulShellBranch _bibleBranch() {
  return StatefulShellBranch(
    navigatorKey: bibleTabKey,
    routes: [
      GoRoute(
        path: Routes.bible,
        builder: (_, _) => const BibleHomeScreen(),
        routes: [
          GoRoute(
            path: 'chapter',
            builder: (context, state) {
              final bookId =
                  int.parse(state.uri.queryParameters['bookId']!);
              final chapter =
                  int.parse(state.uri.queryParameters['chapter']!);
              final translation =
                  state.uri.queryParameters['translation'] ?? 'KJV';
              final verseParam = state.uri.queryParameters['verse'];
              final verse =
                  verseParam != null ? int.tryParse(verseParam) : null;
              return BibleChapterScreen(
                bookId: bookId,
                chapter: chapter,
                initialTranslation: translation,
                scrollToVerse: verse,
              );
            },
          ),
          GoRoute(
            path: 'history',
            builder: (_, _) => const BibleHistoryScreen(),
          ),
          GoRoute(
            path: 'memorization',
            builder: (_, _) => const MemorizationScreen(),
            routes: [
              GoRoute(
                path: 'review',
                builder: (_, _) => const MemorizationReviewScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Promises tab navigation branch with nested detail route
StatefulShellBranch _promisesBranch() {
  return StatefulShellBranch(
    navigatorKey: promisesTabKey,
    routes: [
      GoRoute(
        path: Routes.promises,
        builder: (_, _) => const PromisesListScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, _) => const AddPromiseScreen(),
          ),
          GoRoute(
            path: ':promiseId',
            builder: (context, state) {
              final id = state.pathParameters['promiseId']!;
              return PromiseDetailScreen(promiseId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = state.pathParameters['promiseId']!;
                  return AddPromiseScreen(promiseId: id);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// Songs tab navigation branch with nested detail route
StatefulShellBranch _songsBranch() {
  return StatefulShellBranch(
    navigatorKey: songsTabKey,
    routes: [
      GoRoute(
        path: Routes.songs,
        builder: (_, _) => const SongsHomeScreen(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (_, _) => const AddSongScreen(),
          ),
          GoRoute(
            path: 'search',
            builder: (_, _) => const SongSearchScreen(),
          ),
          GoRoute(
            path: ':songId',
            builder: (context, state) {
              final id = state.pathParameters['songId']!;
              return SongDetailScreen(songId: id);
            },
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) {
                  final id = state.pathParameters['songId']!;
                  return AddSongScreen(songId: id);
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// People tab navigation branch with nested detail route
/// Social tab: merged People + Friends + Groups (v21).
StatefulShellBranch _socialBranch() {
  return StatefulShellBranch(
    navigatorKey: socialTabKey,
    routes: [
      GoRoute(
        path: Routes.social,
        builder: (_, _) => const SocialHomeScreen(),
        routes: [
          // ── People (moved from /people) ──
          GoRoute(
            path: 'people',
            builder: (_, _) => const PeopleListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const AddPersonScreen(),
              ),
              GoRoute(
                path: ':personId',
                builder: (context, state) {
                  final id = state.pathParameters['personId']!;
                  return PersonDetailScreen(personId: id);
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (context, state) {
                      final id = state.pathParameters['personId']!;
                      return AddPersonScreen(personId: id);
                    },
                  ),
                ],
              ),
            ],
          ),

          // ── Friends (moved from /home/settings/friends) ──
          GoRoute(
            path: 'friends',
            builder: (_, _) => const FriendsListScreen(),
            routes: [
              GoRoute(
                path: 'requests',
                builder: (_, _) => const FriendRequestsScreen(),
              ),
              GoRoute(
                path: 'search',
                builder: (_, _) => const UsernameSearchScreen(),
              ),
              GoRoute(
                path: 'profile',
                builder: (_, _) => const ProfileSettingsScreen(),
              ),
            ],
          ),

          // ── Share code deep link resolution ──
          GoRoute(
            path: 'share/:shareCode',
            builder: (context, state) {
              final code = state.pathParameters['shareCode']!;
              return ShareCodeScreen(shareCode: code);
            },
          ),

          // ── Groups (moved from /groups) ──
          GoRoute(
            path: 'groups',
            builder: (_, _) => const GroupsListScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) => const CreateGroupScreen(),
              ),
              GoRoute(
                path: ':groupId',
                builder: (context, state) {
                  final id = state.pathParameters['groupId']!;
                  return GroupDetailScreen(groupId: id);
                },
                routes: [
                  GoRoute(
                    path: 'members',
                    builder: (context, state) {
                      final id = state.pathParameters['groupId']!;
                      return ManageMembersScreen(groupId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
