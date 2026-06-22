import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/remote/remote_config_keys.dart';
import '../../../../core/config/remote/remote_config_providers.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/tutorial/sequences/app_tutorial_sequences.dart';
import '../../../../core/tutorial/tutorial_controller.dart';
import '../../../../core/tutorial/tutorial_providers.dart';
import '../widgets/daily_focus_card.dart';
import '../widgets/daily_habits_widget.dart';
import '../widgets/overview_grid.dart';
import '../widgets/quick_actions_row.dart';

/// Home dashboard screen — light hero band + scrollable content body.
class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() =>
      _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  DateTime? _lastBackPressed;

  @override
  void initState() {
    super.initState();
    // Check for a pending tutorial after the first frame so all widgets have
    // laid out and their RenderBox positions are available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartTutorial());
  }

  Future<void> _maybeStartTutorial() async {
    final service = ref.read(tutorialServiceProvider);
    if (!service.isPending()) return;
    if (!mounted) return;
    // Brief delay so the scroll view settles before we read render positions.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    ref.read(tutorialControllerProvider).start(context, homeTutorialSteps());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tutorialReplayRequestedProvider, (_, requested) {
      if (requested) {
        ref.read(tutorialReplayRequestedProvider.notifier).state = false;
        _maybeStartTutorial();
      }
    });

    final now = DateTime.now();
    final profileAsync = ref.watch(currentUserProfileProvider);
    final firstName = profileAsync.valueOrNull?.displayName.split(' ').firstOrNull ?? '';
    final greeting = _getGreeting(now);
    final personalGreeting =
        firstName.isNotEmpty ? '$greeting, $firstName' : greeting;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        final now = DateTime.now();
        final tooLong = _lastBackPressed == null ||
            now.difference(_lastBackPressed!) > const Duration(seconds: 2);

        if (tooLong) {
          _lastBackPressed = now;
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Press back again to exit'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }

        SystemNavigator.pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.scaffoldGray,
        body: CustomScrollView(
          slivers: [
            // ── Light hero band ──────────────────────────────────────────
            SliverToBoxAdapter(
                child: _DashboardHero(
                    greeting: personalGreeting,
                    date: _getFormattedDate(now))),

            // ── Scrollable content (sections are remote-config orderable) ──
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildSectionWidgets(
                    _resolveSections(
                      ref
                          .watch(remoteConfigProvider)
                          .getJson(RcKeys.homeSections),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Default home sections, top to bottom. The server may hide or reorder them
  /// per id via the `home.sections` override map.
  static const _defaultSections = [
    'dailyFocus',
    'dailyHabits',
    'quickActions',
    'overview',
  ];

  /// Resolves the ordered, visible section ids from the override map, falling
  /// back to the defaults if an override would hide everything.
  List<String> _resolveSections(Map<String, dynamic> overrides) {
    // (order, baseIndex, id) — baseIndex keeps equal `order` values deterministic.
    final positioned = <(int, int, String)>[];
    for (var i = 0; i < _defaultSections.length; i++) {
      final id = _defaultSections[i];
      final ov = overrides[id];
      var order = i;
      if (ov is Map) {
        if (ov['visible'] == false) continue;
        if (ov['order'] is num) order = (ov['order'] as num).toInt();
      }
      positioned.add((order, i, id));
    }
    positioned.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    final result = positioned.map((e) => e.$3).toList();
    return result.isEmpty ? _defaultSections : result;
  }

  /// Maps a section id to its widget (tutorial keys preserved). Unknown ids are
  /// skipped.
  Widget? _sectionWidget(String id) {
    switch (id) {
      case 'dailyFocus':
        return DailyFocusCard(key: tutorialKey(TutorialKeyId.dailyFocusCard));
      case 'dailyHabits':
        return const DailyHabitsWidget();
      case 'quickActions':
        return QuickActionsRow(key: tutorialKey(TutorialKeyId.quickActionsRow));
      case 'overview':
        return const OverviewGrid();
    }
    return null;
  }

  List<Widget> _buildSectionWidgets(List<String> ids) {
    final widgets = <Widget>[];
    for (final id in ids) {
      final w = _sectionWidget(id);
      if (w == null) continue;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 28));
      widgets.add(w);
    }
    return widgets;
  }

  String _getGreeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getFormattedDate(DateTime now) {
    final weekday = _getWeekday(now.weekday);
    final month = _getMonth(now.month);
    return '$weekday, $month ${now.day}';
  }

  String _getWeekday(int weekday) {
    const weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return weekdays[weekday - 1];
  }

  String _getMonth(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return months[month - 1];
  }
}

/// Light hero band at the top of the home dashboard, matching the scaffold.
class _DashboardHero extends StatelessWidget {
  final String greeting;
  final String date;

  const _DashboardHero({required this.greeting, required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppTheme.scaffoldGray,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // App icon
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      greeting,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined,
                    color: Colors.grey.shade600, size: 22),
                onPressed: () => context.push(Routes.settings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
