import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/bible_version_info.dart';
import '../providers/bible_providers.dart';

/// Screen for managing downloadable Bible translations.
///
/// Lists all available versions from the local registry (synced from server),
/// shows download/installed state, lets users download, remove, and set a
/// default translation.  The default is used in the Bible reader, notes, and
/// search.
class BibleVersionsScreen extends ConsumerStatefulWidget {
  const BibleVersionsScreen({super.key});

  @override
  ConsumerState<BibleVersionsScreen> createState() =>
      _BibleVersionsScreenState();
}

class _BibleVersionsScreenState extends ConsumerState<BibleVersionsScreen> {
  // code → download progress (0.0–1.0), null when not downloading
  final Map<String, double?> _downloadProgress = {};

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

    return Scaffold(
      backgroundColor: AppTheme.scaffoldGray,
      appBar: AppBar(
        title: const Text('Bible Versions'),
        backgroundColor: AppTheme.scaffoldGray,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: versionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (versions) => versions.isEmpty
            ? const Center(child: Text('No versions available.'))
            : _buildList(context, versions),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<BibleVersionInfo> versions) {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacing16),
      children: [
        Padding(
          padding: const EdgeInsets.only(
              bottom: AppTheme.spacing16, left: AppTheme.spacing4),
          child: Text(
            'NKJV is downloaded on first launch. Download additional '
            'translations to use them in Bible reading, notes, and search. '
            'Tap ••• to set a version as default or remove it.',
            style:
                AppTheme.caption.copyWith(color: AppTheme.unselectedColor),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppTheme.borderRadius3XL,
            border: Border.all(color: AppTheme.dividerColor),
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
                for (int i = 0; i < versions.length; i++) ...[
                  _VersionTile(
                    info: versions[i],
                    downloadProgress: _downloadProgress[versions[i].code],
                    onDownload: () => _startDownload(versions[i]),
                    onDelete: () => _confirmDelete(context, versions[i]),
                    onSetDefault: () => _setDefault(versions[i].code),
                  ),
                  if (i < versions.length - 1)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 56,
                      color: AppTheme.dividerColor,
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacing16),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.spacing4),
          child: Text(
            'Removing a version frees up ~8 MB. Notes referencing that '
            'translation will still show the reference but verse text will '
            'not load until you re-download it.',
            style:
                AppTheme.caption.copyWith(color: AppTheme.unselectedColor),
          ),
        ),
      ],
    );
  }

  Future<void> _startDownload(BibleVersionInfo info) async {
    if (_downloadProgress.containsKey(info.code)) return;
    setState(() => _downloadProgress[info.code] = 0.0);
    try {
      final dbService = ref.read(bibleDatabaseServiceProvider);
      if (!dbService.isOpen) {
        await dbService.download(
          info.downloadUrl,
          onProgress: (p) {
            if (mounted) setState(() => _downloadProgress[info.code] = p);
          },
        );
      } else {
        await dbService.downloadVersion(
          info.code,
          info.downloadUrl,
          onProgress: (p) {
            if (mounted) setState(() => _downloadProgress[info.code] = p);
          },
        );
      }
      final repo = ref.read(bibleVersionStateRepositoryProvider);
      if (await repo.getDefaultCode() == null) {
        await repo.setDefault(info.code);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Download failed: ${info.name}. Check your connection.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _downloadProgress.remove(info.code));
    }
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${info.name}?'),
        content: Text(
          'This will free up ~${info.approximateSizeMb} MB. '
          'Notes referencing ${info.code} verses will still show the '
          'reference but verse text will not load until you re-download it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove',
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
        content: Text('Failed to remove ${info.name}.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }
}

// ─── Version Tile ─────────────────────────────────────────────────────────────

class _VersionTile extends StatelessWidget {
  final BibleVersionInfo info;
  final double? downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _VersionTile({
    required this.info,
    required this.downloadProgress,
    required this.onDownload,
    required this.onDelete,
    required this.onSetDefault,
  });

  static const _green = AppTheme.emerald;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDownloading = downloadProgress != null;

    return Padding(
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
            color: info.isDownloaded ? _green : AppTheme.gray400,
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
                          color: AppTheme.textDark,
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
                          'Default',
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
                    value: downloadProgress! > 0 ? downloadProgress : null,
                    backgroundColor: _green.withValues(alpha: 0.12),
                    color: _green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: AppTheme.spacing2),
                  Text(
                    downloadProgress! > 0
                        ? '${(downloadProgress! * 100).toStringAsFixed(0)}%'
                        : 'Starting…',
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.unselectedColor),
                  ),
                ] else
                  Text(
                    '~${info.approximateSizeMb} MB',
                    style: AppTheme.caption
                        .copyWith(color: AppTheme.unselectedColor),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacing8),
          if (!info.isDownloaded && !isDownloading)
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
              child: const Text('Download'),
            )
          else if (info.isDownloaded && !isDownloading)
            MenuAnchor(
              menuChildren: [
                if (!info.isDefault)
                  MenuItemButton(
                    onPressed: onSetDefault,
                    leadingIcon: Icon(Icons.star_outline,
                        size: 18, color: _green),
                    child: Text('Set as default',
                        style: TextStyle(color: _green)),
                  ),
                MenuItemButton(
                  onPressed: onDelete,
                  leadingIcon: Icon(Icons.delete_outline,
                      size: 18, color: theme.colorScheme.error),
                  child: Text('Remove',
                      style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
              builder: (context, controller, child) => IconButton(
                onPressed: () => controller.isOpen
                    ? controller.close()
                    : controller.open(),
                icon: const Icon(Icons.more_vert),
                iconSize: 20,
                color: AppTheme.unselectedColor,
              ),
            ),
        ],
      ),
    );
  }
}
