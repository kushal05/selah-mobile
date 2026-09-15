import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/config/remote/remote_config_keys.dart';
import '../../../../core/config/remote/remote_config_providers.dart';
import '../../../../core/navigation/routes.dart';
import '../../../../core/providers/app_info_providers.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/sync/engine/sync_state_machine.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/dialogs/reading_text_size_sheet.dart';
import '../../../../shared/widgets/dialogs/theme_mode_sheet.dart';
import '../../../../core/tutorial/tutorial_providers.dart';
import '../../../../shared/widgets/dialogs/build_selection_dialog.dart';
import '../../../../shared/widgets/dialogs/update_dialog.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/section_label.dart';

/// Settings screen with account, sync, data, and about sections
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.pageGround,
      appBar: AppBar(
        title: Text(l10n(context).settings),
        backgroundColor: context.pageGround,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          // ── Account ───────────────────────────────────────────────
          // Friends and Groups used to be listed here as well as in the Social
          // tab — via the deprecated pre-v21 routes, so the same screens were
          // reachable by two paths with two different back stacks. The Social
          // tab owns them now; only the profile, which is genuinely a setting,
          // stays.
          _SettingsSection(
            id: 'account',
            title: l10n(context).account,
            tiles: [
              _SettingsTile(
                icon: Icons.badge_outlined,
                title: l10n(context).myProfile,
                subtitle: l10n(context).setYourUsernameAndDisplayName,
                onTap: () => context.push(Routes.socialProfileSettings),
              ),
            ],
          ),

          // ── Notifications ─────────────────────────────────────────
          _SettingsSection(
            id: 'notifications',
            title: l10n(context).notifications2,
            tiles: [
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: l10n(context).notificationSettings,
                subtitle: l10n(context).remindersSocialAlertsAndHabits,
                onTap: () => context.push(Routes.notificationSettings),
              ),
            ],
          ),

          // ── Display ──────────────────────────────────────────────
          _SettingsSection(
            id: 'display',
            title: l10n(context).display,
            tiles: [
              _SettingsTile(
                icon: Icons.format_size_rounded,
                title: l10n(context).textSize2,
                subtitle: l10n(context).makeBiblePassagesNotesAndLyricsBigger,
                onTap: () => showReadingTextSizeSheet(context),
                showChevron: false,
              ),
              _SettingsTile(
                icon: Icons.brightness_6_outlined,
                title: l10n(context).settingsAppearance,
                subtitle: l10n(context).lightDarkOrMatchYourPhone,
                onTap: () => showThemeModeSheet(context),
                showChevron: false,
              ),
            ],
          ),

          // ── Bible ────────────────────────────────────────────────
          _SettingsSection(
            id: 'bible',
            title: l10n(context).bible,
            tiles: [
              _SettingsTile(
                icon: Icons.menu_book_outlined,
                title: l10n(context).bibleVersions,
                subtitle: l10n(context).downloadOrRemoveBibleTranslations,
                onTap: () => context.push(Routes.bibleVersions),
              ),
            ],
          ),

          // ── Support ───────────────────────────────────────────────
          _SettingsSection(
            id: 'support',
            title: l10n(context).support2,
            tiles: [
              _SettingsTile(
                icon: Icons.feedback_outlined,
                title: l10n(context).sendFeedback,
                subtitle: l10n(context).reportBugsRequestFeatures,
                onTap: () => context.push(Routes.feedback),
              ),
            ],
          ),

          // ── Sync ──────────────────────────────────────────────────
          _SettingsSection(
            id: 'sync',
            title: l10n(context).sync,
            tiles: [
              _SettingsTile(
                icon: Icons.cloud_sync_outlined,
                title: l10n(context).checkSync,
                subtitle: l10n(context).seeWhetherYourDataIsUpToDate,
                onTap: () => context.push(Routes.syncStatus),
              ),
            ],
          ),

          // ── Data ──────────────────────────────────────────────────
          _SettingsSection(
            id: 'data',
            title: l10n(context).data2,
            tiles: [
              _SettingsTile(
                icon: Icons.label_outline,
                title: l10n(context).tags,
                subtitle: l10n(context).renameMergeOrDeleteTags,
                onTap: () => context.push(Routes.tagManagement),
              ),
              _SettingsTile(
                icon: Icons.delete_outline,
                title: l10n(context).trash,
                subtitle: l10n(context).viewAndRestoreDeletedItems,
                onTap: () => context.push(Routes.trash),
              ),
              _SettingsTile(
                icon: Icons.file_download_outlined,
                title: l10n(context).backUpMyData,
                subtitle: l10n(context).saveACopyOfEverythingToYourDevice,
                onTap: () => _handleJsonExport(context, ref),
                showChevron: false,
              ),
              _SettingsTile(
                icon: Icons.picture_as_pdf_outlined,
                title: l10n(context).savePrayersAsAPdf,
                subtitle: l10n(context).aPrintableCopyOfYourActivePrayers,
                onTap: () => _handlePrayersPdfExport(context, ref),
                showChevron: false,
              ),
              _SettingsTile(
                icon: Icons.cloud_upload_outlined,
                title: l10n(context).reUploadEverything,
                subtitle: l10n(context).advancedOnlyNeededIfSupportAsksYouTo,
                onTap: () => _handleForcePush(context, ref),
                showChevron: false,
              ),
            ],
          ),

          // ── Usage ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
                AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
            child: const SectionLabel('USAGE'),
          ),
          Consumer(
            builder: (context, ref, _) {
              final statsAsync = ref.watch(userStatsProvider);
              return _SettingsGroup(
                tiles: statsAsync.when(
                  loading: () => [
                    _SettingsTile(
                      icon: Icons.hourglass_empty,
                      title: l10n(context).loadingStats,
                      showChevron: false,
                    ),
                  ],
                  error: (_, _) => [
                    _SettingsTile(
                      icon: Icons.error_outline,
                      iconColor: context.hintText,
                      title: l10n(context).unableToLoadStats,
                      subtitle: l10n(context).tapToRetry,
                      onTap: () => ref.invalidate(userStatsProvider),
                      showChevron: false,
                    ),
                  ],
                  data: (stats) => [
                    _SettingsTile(
                      icon: Icons.storage_outlined,
                      title: l10n(context).storageUsed,
                      showChevron: false,
                      trailing: Text(
                        stats.formattedStorage,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.note_outlined,
                      title: l10n(context).totalNotes,
                      showChevron: false,
                      trailing: Text(
                        '${stats.noteCount}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.favorite_outline,
                      title: l10n(context).totalPrayers2,
                      showChevron: false,
                      trailing: Text(
                        '${stats.prayerCount}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // ── About ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
                AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
            child: const SectionLabel('ABOUT'),
          ),
          Consumer(
            builder: (context, ref, _) {
              final pkgAsync = ref.watch(packageInfoProvider);
              final version = pkgAsync.valueOrNull?.version ?? '—';
              return _SettingsGroup(
                tiles: [
                  _SettingsTile(
                    icon: Icons.history_outlined,
                    title: "What's New",
                    subtitle: l10n(context).viewRecentChangesAndUpdates,
                    onTap: () => context.push(Routes.changelog),
                  ),
                  _SettingsTile(
                    icon: Icons.map_outlined,
                    title: l10n(context).replayAppTour,
                    subtitle: l10n(context).reRunTheFeatureWalkthrough,
                    showChevron: false,
                    onTap: () async {
                      await ref.read(tutorialServiceProvider).resetForReplay();
                      ref.read(tutorialReplayRequestedProvider.notifier).state = true;
                      if (context.mounted) {
                        context.go(Routes.home);
                      }
                    },
                  ),
                  _SettingsTile(
                    icon: Icons.system_update_alt_outlined,
                    title: l10n(context).checkForUpdates,
                    subtitle: 'Version $version',
                    showChevron: false,
                    onTap: () => _handleCheckForUpdates(context, ref),
                  ),
                  _SettingsTile(
                    icon: Icons.info_outline,
                    title: l10n(context).aboutSelah,
                    subtitle: 'Version $version',
                    showChevron: false,
                    onTap: () {
                      showAboutDialog(
                        context: context,
                        applicationName: 'Selah',
                        applicationVersion: version,
                        applicationIcon: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/app_icon.png',
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        children: [
                          Text(
                            ref
                                .read(remoteConfigProvider)
                                .getString(RcKeys.aboutDescription),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),

          // ── Sign Out ────────────────────────────────────────────────
          const SizedBox(height: 8),
          _SettingsGroup(
            dangerTint: true,
            tiles: [
              _SettingsTile(
                icon: Icons.logout_rounded,
                title: l10n(context).signOut,
                iconColor: context.dangerText,
                titleColor: context.dangerText,
                onTap: () => _handleSignOut(context, ref),
                showChevron: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleJsonExport(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n(context).preparingExport),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
    try {
      await ref.read(exportServiceProvider).exportAllDataAsJson();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'export your data')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleForcePush(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).forcePushData),
        content: Text(
          l10n(context).thisWillPushAllLocalDataToTheRemoteDatabaseT,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n(context).push),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _ForcePushProgressDialog(ref: ref),
    );
  }

  Future<void> _handlePrayersPdfExport(
    BuildContext context,
    WidgetRef ref,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n(context).generatingPdf),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 1),
      ),
    );
    try {
      await ref.read(pdfExportServiceProvider).exportPrayersToPdf();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(UserFacingError.message(e, action: 'create the PDF')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleCheckForUpdates(
    BuildContext context,
    WidgetRef ref,
  ) async {
    // QA users get a build picker so they can install any of the recent
    // builds (different build numbers under the same version included).
    // Prod users get a silent download of the latest available build.
    if (AppConfig.isQA) {
      await _handleCheckForUpdatesQa(context, ref);
    } else {
      await _handleCheckForUpdatesProd(context, ref);
    }
  }

  Future<void> _handleCheckForUpdatesQa(
    BuildContext context,
    WidgetRef ref,
  ) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n(context).loadingAvailableBuilds),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    final service = ref.read(appUpdateServiceProvider);
    final builds = await service.fetchAvailableBuilds();
    final pkgInfo = await ref.read(packageInfoProvider.future);
    final currentBuild = int.tryParse(pkgInfo.buildNumber);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (builds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n(context).noBuildsAvailableRightNow),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picked = await BuildSelectionDialog.show(
      context,
      builds,
      currentBuildNumber: currentBuild,
    );
    if (picked == null || !context.mounted) return;
    await UpdateDialog.show(context, service.resultForBuild(picked), service);
  }

  /// Prod silent path: on Android, downloads the latest build (matched by
  /// buildNumber, not version) and hands it to the system installer with no
  /// release notes / chooser / "Update Available" prompt — just a small
  /// progress dialog. On iOS, where direct APK install is impossible, falls
  /// back to the regular [UpdateDialog] so the user can still be sent to the
  /// App Store via `storeUrl`.
  Future<void> _handleCheckForUpdatesProd(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = ref.read(appUpdateServiceProvider);

    if (!Platform.isAndroid) {
      final result = await service.checkForUpdate();
      if (!context.mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You\'re up to date!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await UpdateDialog.show(context, result, service);
      return;
    }

    // Prefer the manifest (lets us update even when version is unchanged but
    // buildNumber differs); fall back to metadata.json if the manifest is
    // missing for any reason.
    final builds = await service.fetchAvailableBuilds();
    AppUpdateResult? result;
    if (builds.isNotEmpty) {
      result = service.resultForBuild(builds.first);
    } else {
      result = await service.checkForUpdate();
    }

    if (!context.mounted) return;

    if (result == null || !result.canInstallDirectly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'re up to date!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final pkgInfo = await ref.read(packageInfoProvider.future);
    final currentBuild = int.tryParse(pkgInfo.buildNumber) ?? 0;
    if (result.latestBuildNumber > 0 &&
        currentBuild >= result.latestBuildNumber) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You\'re up to date!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SilentUpdateDialog(service: service, apkUrl: result!.apkUrl),
    );
  }

  Future<void> _handleSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n(context).signOut),
        content: Text(l10n(context).areYouSureYouWantToSignOut),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              l10n(context).signOut,
              style: TextStyle(color: context.dangerText),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(authNotifierProvider.notifier).logout();
    }
  }
}

// ─── Section Label ────────────────────────────────────────────────────────────


// ─── Settings Group (Card) ────────────────────────────────────────────────────

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsTile> tiles;
  final bool dangerTint;

  const _SettingsGroup({required this.tiles, this.dangerTint = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing16,
        vertical: AppTheme.spacing2,
      ),
      decoration: BoxDecoration(
        // Was Colors.white, which stayed white in dark mode; and red.shade50,
        // which is a light-theme swatch with no dark counterpart.
        color: dangerTint
            ? AppTheme.error.withValues(alpha: 0.08)
            : context.cardSurface,
        borderRadius: AppTheme.borderRadius3XL,
        border: Border.all(
          color: dangerTint
              ? AppTheme.error.withValues(alpha: 0.25)
              : context.hairline,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppTheme.borderRadius3XL,
        child: Column(
          children: [
            for (int i = 0; i < tiles.length; i++) ...[
              tiles[i],
              if (i < tiles.length - 1)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 56,
                  color: context.pageGround,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Settings Section (label + group, remote-config hideable) ─────────────────

/// A settings section (label + card) that the backend can hide via the
/// `settings.sections` override map (keyed by [id]). Defaults to visible, so an
/// absent/failed config shows the section. Used only for the static navigation
/// sections — the dynamic USAGE/ABOUT sections and Sign Out are never hideable.
class _SettingsSection extends ConsumerWidget {
  final String id;
  final String title;
  final List<_SettingsTile> tiles;

  const _SettingsSection({
    required this.id,
    required this.title,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ov =
        ref.watch(remoteConfigProvider).getJson(RcKeys.settingsSections)[id];
    if (ov is Map && ov['visible'] == false) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Aligned with the card it introduces: _SettingsGroup carries a 16pt
        // side margin and the label had none, so every heading sat 16pt
        // further left than the card beneath it. The vertical padding gives
        // each section air instead of the heading touching the card above.
        Padding(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing16,
              AppTheme.spacing20, AppTheme.spacing16, AppTheme.spacing8),
          child: SectionLabel(title),
        ),
        _SettingsGroup(tiles: tiles),
      ],
    );
  }
}

// ─── Settings Tile ────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? titleColor;
  final VoidCallback? onTap;
  final bool showChevron;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.titleColor,
    this.onTap,
    this.showChevron = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final iconFg = iconColor ?? context.mutedText;
    final titleFg = titleColor ?? context.primaryText;

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconFg, size: AppTheme.iconLG),
      title: Text(
        title,
        style: AppTheme.headingSmall.copyWith(
          fontWeight: FontWeight.w500,
          color: titleFg,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: AppTheme.caption.copyWith(color: context.mutedText),
            )
          : null,
      trailing:
          trailing ??
          (showChevron
              ? Icon(
                  Icons.chevron_right_rounded,
                  color: context.decorativeInk,
                  size: AppTheme.iconBase,
                )
              : null),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing16,
        vertical: AppTheme.spacing2,
      ),
      minLeadingWidth: AppTheme.spacing24,
    );
  }
}

// ─── Force Push Progress Dialog ───────────────────────────────────────────────

class _ForcePushProgressDialog extends StatefulWidget {
  final WidgetRef ref;
  const _ForcePushProgressDialog({required this.ref});

  @override
  State<_ForcePushProgressDialog> createState() =>
      _ForcePushProgressDialogState();
}

class _ForcePushProgressDialogState extends State<_ForcePushProgressDialog> {
  String _status = 'Preparing...';
  double _progress = 0;
  bool _done = false;
  String? _error;
  StreamSubscription<SyncProgress>? _syncSub;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      // Phase 1: Create oplog entries
      final forcePushService = widget.ref.read(forcePushServiceProvider);
      final count = await forcePushService.createForcePushOplogs(
        onProgress: (tableName, index, total) {
          if (!mounted) return;
          setState(() {
            _status = 'Queuing $tableName...';
            _progress = index / total * 0.5; // first half of progress
          });
        },
      );

      if (count == 0) {
        if (!mounted) return;
        setState(() {
          _status = 'No data to push';
          _progress = 1;
          _done = true;
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _status = 'Pushing $count operations...';
        _progress = 0.5;
      });

      // Phase 2: Push via sync engine and listen for progress
      final syncService = await widget.ref.read(syncServiceProvider.future);

      final resultCompleter = Completer<void>();

      _syncSub = syncService.progressStream.listen((progress) {
        if (!mounted) return;
        setState(() {
          switch (progress.state) {
            case SyncEngineState.pushing:
              final pushProgress = progress.totalOps > 0
                  ? (progress.totalOps - progress.pendingOps) /
                        progress.totalOps
                  : 0.0;
              _progress = 0.5 + pushProgress * 0.5;
              _status =
                  'Pushing... ${progress.totalOps - progress.pendingOps}/${progress.totalOps}';
            case SyncEngineState.idle:
              _progress = 1;
              _status = 'Done! $count operations pushed';
              _done = true;
              resultCompleter.complete();
            case SyncEngineState.error:
              _error = 'Sync error occurred';
              _done = true;
              resultCompleter.complete();
            default:
              break;
          }
        });
      });

      syncService.syncNow();

      // Wait for sync to finish (with a timeout so we don't hang forever)
      await resultCompleter.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          if (!mounted) return;
          setState(() {
            _status = 'Sync is still running in the background';
            _done = true;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _done = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n(context).forcePushData),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            _error ?? _status,
            style: AppTheme.bodyBase.copyWith(
              color: _error != null ? context.dangerText : null,
            ),
          ),
        ],
      ),
      actions: [
        if (_done)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n(context).close),
          ),
      ],
    );
  }
}

// ─── Silent Update Dialog (Production) ────────────────────────────────────────
//
// Minimal-UI replacement for [UpdateDialog] used by the Production
// "Check for Updates" path. There is no version chooser, no release notes, no
// Later button — just a progress indicator while the APK downloads, after
// which the system installer is invoked. Mirrors the install/permission
// retry flow from [UpdateDialog] so the user can still recover from the
// "Install unknown apps" permission prompt without re-downloading.

class _SilentUpdateDialog extends StatefulWidget {
  final AppUpdateService service;
  final String apkUrl;

  const _SilentUpdateDialog({required this.service, required this.apkUrl});

  @override
  State<_SilentUpdateDialog> createState() => _SilentUpdateDialogState();
}

class _SilentUpdateDialogState extends State<_SilentUpdateDialog> {
  StreamSubscription<DownloadProgress>? _sub;
  DownloadProgress? _progress;
  bool _downloading = false;
  String? _completedApkPath;
  bool _needsPermission = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startDownload() {
    setState(() {
      _downloading = true;
      _progress = null;
      _needsPermission = false;
      _completedApkPath = null;
      _error = null;
    });

    _sub = widget.service.downloadApk(widget.apkUrl).listen((progress) async {
      if (!mounted) return;
      setState(() => _progress = progress);

      if (progress.hasError) {
        _sub?.cancel();
        if (!mounted) return;
        setState(() {
          _downloading = false;
          _error = progress.error;
        });
        return;
      }

      if (progress.isDone) {
        _sub?.cancel();
        _completedApkPath = progress.completedPath;
        await _triggerInstall(progress.completedPath!);
      }
    });
  }

  Future<void> _triggerInstall(String path) async {
    try {
      await widget.service.installApk(path);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'INSTALL_PERMISSION_REQUIRED') {
        setState(() {
          _downloading = false;
          _needsPermission = true;
        });
      } else {
        setState(() {
          _downloading = false;
          _error = e.message ?? 'Installation failed';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _retryInstall() async {
    final path = _completedApkPath;
    if (path == null || !File(path).existsSync()) {
      _startDownload();
      return;
    }
    setState(() => _needsPermission = false);
    await _triggerInstall(path);
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    final pct = p == null || p.isIndeterminate ? null : p.fraction;

    String statusText;
    if (_error != null) {
      statusText = 'Update failed: $_error';
    } else if (_needsPermission) {
      statusText =
          'Enable "Install unknown apps" for Selah on the Settings page that just opened, then tap Retry Install.';
    } else if (p == null) {
      statusText = 'Starting download…';
    } else if (p.isDone) {
      statusText = 'Download complete. Opening installer…';
    } else if (p.isIndeterminate) {
      statusText = 'Downloading…';
    } else {
      statusText =
          '${(p.fraction * 100).toStringAsFixed(0)}%'
          ' (${_formatBytes(p.received)} / ${_formatBytes(p.total)})';
    }

    return PopScope(
      canPop: !_downloading,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n(context).updatingSelah,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_needsPermission && _error == null)
              LinearProgressIndicator(value: pct),
            if (!_needsPermission && _error == null)
              const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 14,
                color: _error != null
                    ? context.dangerText
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
        actions: [
          if (_error != null) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n(context).close),
            ),
            FilledButton.icon(
              onPressed: _startDownload,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n(context).retry),
              style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.orange,
                      foregroundColor: AppTheme.onAccent(AppTheme.orange)),
            ),
          ] else if (_needsPermission) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n(context).close),
            ),
            FilledButton.icon(
              onPressed: _retryInstall,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(l10n(context).retryInstall),
              style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.orange,
                      foregroundColor: AppTheme.onAccent(AppTheme.orange)),
            ),
          ] else if (p?.isDone == true)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n(context).close),
            )
          else
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n(context).actionCancel),
            ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
