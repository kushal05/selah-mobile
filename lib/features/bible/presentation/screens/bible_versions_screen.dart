import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/bible_version_info.dart';
import '../providers/bible_download_manager.dart';
import '../providers/bible_providers.dart';
import '../../../../core/services/user_facing_error.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';

/// [versions] ordered by display name, ignoring case.
@visibleForTesting
List<BibleVersionInfo> sortedByName(Iterable<BibleVersionInfo> versions) =>
    versions.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Screen for managing downloadable Bible translations.
///
/// Lists the versions from the local registry (synced from server) in two
/// sections, Downloaded and Available, each by name. Tapping a downloaded
/// version makes it the default, which the Bible reader, notes and search use.
/// The row's menu only removes a version.
class BibleVersionsScreen extends ConsumerStatefulWidget {
  const BibleVersionsScreen({super.key});

  @override
  ConsumerState<BibleVersionsScreen> createState() =>
      _BibleVersionsScreenState();
}

class _BibleVersionsScreenState extends ConsumerState<BibleVersionsScreen> {
  @override
  void initState() {
    super.initState();
    _refreshVersions();
  }

  Future<void> _refreshVersions() async {
    try {
      final repo = ref.read(bibleVersionStateRepositoryProvider);
      // Skip the network call if the cache is less than 1 hour old.
      if (await repo.isCacheFresh()) return;
      final versions = await ref.read(bibleVersionApiServiceProvider).getVersions();
      await repo.upsertFromServer(versions);
    } catch (_) {
      // Non-fatal — the cached list is still shown.
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(bibleVersionStatesProvider);
    final downloads = ref.watch(bibleDownloadManagerProvider);

    return Scaffold(
      backgroundColor: context.pageGround,
      appBar: AppBar(
        title: Text(l10n(context).bibleVersions),
        backgroundColor: context.pageGround,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: versionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(UserFacingError.forLoad(e))),
        data: (versions) => versions.isEmpty
            ? Center(child: Text(l10n(context).noVersionsAvailable))
            : _buildList(context, versions, downloads),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<BibleVersionInfo> versions,
    Map<String, BibleDownloadState> downloads,
  ) {
    // Two sections, each by name. A version still downloading is not
    // downloaded yet, so it stays under Available until it lands.
    final downloaded = sortedByName(versions.where((v) => v.isDownloaded));
    final available = sortedByName(versions.where((v) => !v.isDownloaded));

    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacing16),
      children: [
        Padding(
          padding: const EdgeInsets.only(
              bottom: AppTheme.spacing16, left: AppTheme.spacing4),
          child: Text(
            l10n(context).bibleVersionsIntro,
            style:
                AppTheme.caption.copyWith(color: context.mutedText),
          ),
        ),
        if (downloaded.isNotEmpty)
          _buildSection(
              context, l10n(context).bibleVersionsDownloaded, downloaded, downloads),
        if (downloaded.isNotEmpty && available.isNotEmpty)
          const SizedBox(height: AppTheme.spacing16),
        if (available.isNotEmpty)
          _buildSection(
              context, l10n(context).bibleVersionsAvailable, available, downloads),
        const SizedBox(height: AppTheme.spacing16),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
          child: Text(
            l10n(context).bibleVersionRemovalNote,
            style:
                AppTheme.caption.copyWith(color: context.mutedText),
          ),
        ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<BibleVersionInfo> items,
    Map<String, BibleDownloadState> downloads,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
              bottom: AppTheme.spacing8, left: AppTheme.spacing4),
          child: Text(
            title,
            style: AppTheme.caption.copyWith(
              color: context.mutedText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.cardSurface,
            borderRadius: AppTheme.borderRadius3XL,
            border: Border.all(color: context.hairline),
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
                for (int i = 0; i < items.length; i++) ...[
                  _VersionTile(
                    info: items[i],
                    download: downloads[items[i].code],
                    onDownload: () => ref
                        .read(bibleDownloadManagerProvider.notifier)
                        .start(items[i]),
                    onCancel: () => ref
                        .read(bibleDownloadManagerProvider.notifier)
                        .cancel(items[i].code),
                    onDelete: () => _confirmDelete(context, items[i]),
                    onSetDefault: () => _setDefault(items[i].code),
                  ),
                  if (i < items.length - 1)
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
        ),
      ],
    );
  }

  Future<void> _setDefault(String code) async {
    await ref.read(bibleVersionStateRepositoryProvider).setDefault(code);
    if (!mounted) return;
    final name = ref
            .read(bibleVersionStatesProvider)
            .valueOrNull
            ?.firstWhereOrNull((v) => v.code == code)
            ?.name ??
        code;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$name set as default.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _confirmDelete(
      BuildContext context, BibleVersionInfo info) async {
    final messenger = ScaffoldMessenger.of(context);
    // Resolved before the await: every read of context after the dialog is a
    // use across an async gap.
    final failureMessage = l10n(context).couldNotRemoveVersion(info.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n(context).removeVersionQuestion(info.name)),
        content: Text(
          'This will free up ~${info.approximateSizeMb} MB. '
          'Notes referencing ${info.code} verses will still show the '
          'reference but verse text will not load until you re-download it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n(context).actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n(context).remove,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(bibleDatabaseServiceProvider).deleteVersion(info.code);
      // If the deleted version was the default, pick the next downloaded one.
      final repo = ref.read(bibleVersionStateRepositoryProvider);
      if (await repo.getDefaultCode() == info.code) {
        final downloadedCodes = ref
            .read(bibleTranslationsProvider)
            .map((c) => c.toUpperCase())
            .toSet();
        final all = await repo.getAll();
        final next =
            all.where((v) => downloadedCodes.contains(v.code)).firstOrNull;
        if (next != null) await repo.setDefault(next.code);
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(failureMessage),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ─── Version Tile ─────────────────────────────────────────────────────────────

class _VersionTile extends StatelessWidget {
  final BibleVersionInfo info;
  final BibleDownloadState? download;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _VersionTile({
    required this.info,
    required this.download,
    required this.onDownload,
    required this.onCancel,
    required this.onDelete,
    required this.onSetDefault,
  });

  static const _green = AppTheme.emerald;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloading = download?.isActive ?? false;
    final isFailed = download?.status == BibleDownloadStatus.failed;
    final downloadProgress = download?.progress ?? 0.0;

    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing16,
        vertical: AppTheme.spacing12,
      ),
      child: Row(
        children: [
          Icon(
            info.isDownloaded
                ? Icons.menu_book_rounded
                : Icons.menu_book_outlined,
            size: AppTheme.iconLG,
            color: info.isDownloaded ? _green : context.hintText,
          ),
          const SizedBox(width: AppTheme.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        info.name,
                        style: AppTheme.headingSmall.copyWith(
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (info.isDefault)
                      Container(
                        margin: const EdgeInsets.only(left: AppTheme.spacing8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spacing6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n(context).defaultLabel,
                          style: AppTheme.caption.copyWith(
                            color: _green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (isDownloading) ...[
                  const SizedBox(height: AppTheme.spacing4),
                  LinearProgressIndicator(
                    value: downloadProgress > 0 ? downloadProgress : null,
                    backgroundColor: _green.withValues(alpha: 0.12),
                    color: _green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Text(
                    downloadProgress > 0
                        ? '${(downloadProgress * 100).toStringAsFixed(0)}%'
                        : 'Starting…',
                    style: AppTheme.caption
                        .copyWith(color: context.mutedText),
                  ),
                ] else if (isFailed && !info.isDownloaded)
                  Text(
                    l10n(context).bibleDownloadFailed,
                    style: AppTheme.caption.copyWith(color: context.dangerText),
                  )
                else
                  Text(
                    '~${info.approximateSizeMb} MB',
                    style: AppTheme.caption
                        .copyWith(color: context.mutedText),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing8),
          if (isDownloading)
            IconButton(
              tooltip: l10n(context).actionCancel,
              onPressed: onCancel,
              icon: const Icon(Icons.close),
              iconSize: 20,
              color: context.mutedText,
            )
          else if (!info.isDownloaded)
            OutlinedButton(
              onPressed: onDownload,
              style: OutlinedButton.styleFrom(
                foregroundColor: _green,
                side: const BorderSide(color: _green),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing12,
                    vertical: AppTheme.spacing6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle:
                    AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              child: Text(l10n(context).download),
            )
          else
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  onPressed: onDelete,
                  leadingIcon: Icon(Icons.delete_outline,
                      size: 18, color: theme.colorScheme.error),
                  child: Text(l10n(context).remove,
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
              builder: (context, controller, child) => IconButton(
                tooltip: l10n(context).moreOptions,
                onPressed: () => controller.isOpen
                    ? controller.close()
                    : controller.open(),
                icon: const Icon(Icons.more_vert),
                iconSize: 20,
                color: context.mutedText,
              ),
            ),
        ],
      ),
    );

    // Tapping a downloaded version selects it as the default.
    if (!info.isDownloaded) return row;
    return InkWell(onTap: info.isDefault ? null : onSetDefault, child: row);
  }
}
