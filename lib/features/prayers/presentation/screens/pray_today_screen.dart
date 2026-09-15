import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../providers/pray_today_provider.dart';
import '../widgets/pray_today_card.dart';
import '../widgets/pray_today_completion.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../shared/utils/date_format.dart';

/// Unified daily prayer flow screen
///
/// Generates a list of today's prayers and provides a sequential
/// logging experience without interruptions.
class PrayTodayScreen extends ConsumerStatefulWidget {
  const PrayTodayScreen({super.key, this.logPrayerId});

  /// When set (e.g. from the home-screen "log" widget button), the log flow for
  /// this prayer opens automatically once today's prayers have loaded.
  final String? logPrayerId;

  @override
  ConsumerState<PrayTodayScreen> createState() => _PrayTodayScreenState();
}

class _PrayTodayScreenState extends ConsumerState<PrayTodayScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  List<PrayerModel> _todaysPrayers = [];
  Set<String> _loggedPrayerIds = {};
  bool _isLoading = true;
  bool _autoLogAttempted = false;
  String _sessionDate = '';

  @override
  void initState() {
    super.initState();
    _sessionDate = _getTodayDate();
    _loadTodaysPrayers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _getTodayDate() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadTodaysPrayers() async {
    try {
      final userId = ref.read(currentUserIdProvider);
      final prayTodayService = ref.read(prayTodayServiceProvider);
      final prayerLogRepo = ref.read(prayerLogRepositoryProvider);

      // Launch both independent queries in parallel
      final todaysPrayersFuture = prayTodayService.todaysPrayers(userId);
      final todaysLogsFuture =
          prayerLogRepo.getLogsBySessionDate(_sessionDate, userId);

      final todaysPrayers = await todaysPrayersFuture;
      final todaysLogs = await todaysLogsFuture;

      final loggedIds = todaysLogs.map((l) => l.prayerId).toSet();

      // Create card keys
      for (final prayer in todaysPrayers) {
        _cardKeys[prayer.id] = GlobalKey();
      }

      if (mounted) {
        setState(() {
          _todaysPrayers = todaysPrayers;
          _loggedPrayerIds = loggedIds;
          _isLoading = false;
        });
        _maybeAutoLogFromWidget();
      }
    } catch (e, st) {
      debugPrint('Failed to load today\'s prayers: $e\n$st');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// If launched from the home-screen "log" widget button, open the log flow
  /// for that prayer once (after the list has loaded).
  void _maybeAutoLogFromWidget() {
    if (_autoLogAttempted) return;
    final logId = widget.logPrayerId;
    if (logId == null || logId.isEmpty) return;
    _autoLogAttempted = true;
    if (_loggedPrayerIds.contains(logId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // ignore: discarded_futures
        _logPrayer(logId);
      }
    });
  }

  Future<void> _logPrayer(String prayerId) async {
    final userId = ref.read(currentUserIdProvider);
    final prayerLogRepo = ref.read(prayerLogRepositoryProvider);

    // Show optional note dialog
    final note = await _showNoteDialog();
    if (note == null) return; // User cancelled

    try {
      await prayerLogRepo.logPrayer(
        prayerId: prayerId,
        userId: userId,
        note: note,
        sessionDate: _sessionDate,
      );
    } catch (e, st) {
      debugPrint('Failed to log prayer: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n(context).failedToLogPrayer),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _loggedPrayerIds.add(prayerId);
    });

    // Auto-scroll to next unlogged prayer
    _scrollToNextUnlogged(prayerId);
  }

  Future<String?> _showNoteDialog() async {
    final controller = TextEditingController();
    try {
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n(context).logPrayer),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n(context).addAnOptionalNoteOrLeaveBlank,
                style: TextStyle(fontSize: 16, color: context.mutedText),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: l10n(context).optionalReflection,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.hairline),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(l10n(context).actionCancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: Text(l10n(context).log),
            ),
          ],
        ),
      );
      return result;
    } finally {
      controller.dispose();
    }
  }

  void _scrollToNextUnlogged(String justLoggedId) {
    // Find the next unlogged prayer after the one just logged
    final currentIndex =
        _todaysPrayers.indexWhere((p) => p.id == justLoggedId);
    if (currentIndex < 0) return;

    for (int i = currentIndex + 1; i < _todaysPrayers.length; i++) {
      if (!_loggedPrayerIds.contains(_todaysPrayers[i].id)) {
        final key = _cardKeys[_todaysPrayers[i].id];
        if (key?.currentContext != null) {
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              Scrollable.ensureVisible(
                key!.currentContext!,
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                alignment: 0.2,
              );
            }
          });
        }
        return;
      }
    }
  }

  bool get _allPrayersLogged {
    if (_todaysPrayers.isEmpty) return false;
    return _todaysPrayers.every((p) => _loggedPrayerIds.contains(p.id));
  }

  int get _loggedCount =>
      _todaysPrayers.where((p) => _loggedPrayerIds.contains(p.id)).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n(context).actionBack,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(l10n(context).prayToday),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: context.primaryText,
      ),
      body: _isLoading
          ? const ListTileSkeletonList(count: 5, hasLeading: false)
          : _todaysPrayers.isEmpty
              ? _buildEmptyState()
              : _allPrayersLogged
                  ? PrayTodayCompletion(
                      totalPrayers: _todaysPrayers.length,
                      onReviewLogs: () {
                        // Could navigate to log history
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n(context).prayerLogsSaved),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      onAddReflection: () async {
                        final controller = TextEditingController();
                        try {
                          await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Today\'s Reflection'),
                              content: TextField(
                                controller: controller,
                                maxLines: 5,
                                decoration: InputDecoration(
                                  hintText:
                                      l10n(context).whatStoodOutDuringPrayerToday,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide:
                                        BorderSide(color: context.hairline),
                                  ),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  child: Text(l10n(context).actionCancel),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text(l10n(context).reflectionSaved),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  child: Text(l10n(context).actionSave),
                                ),
                              ],
                            ),
                          );
                        } finally {
                          controller.dispose();
                        }
                      },
                      onExit: () => context.pop(),
                    )
                  : _buildPrayerList(),
    );
  }


  /// Marks a prayer answered or archives it, without leaving the session.
  Future<void> _setStatus(PrayerModel prayer, {required bool answered}) async {
    final strings = l10n(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(prayerRepositoryProvider);
    try {
      if (answered) {
        await repo.markAsAnswered(prayer.id);
      } else {
        await repo.archivePrayer(prayer.id);
      }
      if (!mounted) return;
      setState(() {
        _todaysPrayers.removeWhere((p) => p.id == prayer.id);
        _cardKeys.remove(prayer.id);
      });
      messenger.showSnackBar(SnackBar(
        content: Text(answered
            ? strings.prayerMarkedAnswered
            : strings.prayerArchived),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(UserFacingError.message(e,
            action: answered ? 'mark this prayer answered' : 'archive this prayer')),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.errorSurface,
      ));
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.brandBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 40,
                color: AppTheme.brandBlue,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n(context).noPrayersForToday,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n(context).addPrayersWithDailyOrRecurringFrequencyToSee,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrayerList() {
    return Column(
      children: [
        // Header with progress
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getFormattedDate(),
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$_loggedCount / ${_todaysPrayers.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.brandBlue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _todaysPrayers.isEmpty
                      ? 0
                      : _loggedCount / _todaysPrayers.length,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.teal),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),

        // Prayer cards
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            // No horizontal inset: PrayTodayCard carries cardMargin itself,
            // as every other card in the app does.
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: _todaysPrayers.length,
            itemBuilder: (context, index) {
              final prayer = _todaysPrayers[index];
              return PrayTodayCard(
                key: _cardKeys[prayer.id],
                prayer: prayer,
                isLogged: _loggedPrayerIds.contains(prayer.id),
                onLogPress: () => _logPrayer(prayer.id),
                onTap: () => context.push('/prayers/${prayer.id}'),
                // Answering a prayer usually happens *while* praying it, so
                // the session is exactly where the state change belongs. It
                // previously meant leaving, opening the prayer, and coming
                // back.
                onMarkAnswered: () => _setStatus(prayer, answered: true),
                onArchive: () => _setStatus(prayer, answered: false),
              );
            },
          ),
        ),
      ],
    );
  }

  String _getFormattedDate() {
    return formatWeekdayAndLongDate(DateTime.now());
  }
}
