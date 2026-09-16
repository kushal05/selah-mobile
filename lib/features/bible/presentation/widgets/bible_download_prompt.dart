import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/error_state.dart';
import '../../domain/models/bible_version_info.dart';
import '../bible_download_action.dart';
import '../providers/bible_providers.dart';

/// Offers the Bible downloads inline, wherever a Bible is needed but none is
/// installed.
///
/// The reference picker used to open on the book grid regardless: you could
/// pick a book, a chapter and a verse, and only at the end — with nothing to
/// show and nothing to insert — find out there was no Bible on the device.
/// Three steps of work, then a dead end, and no hint of what to do about it.
///
/// Downloading here rather than sending people to Settings is what keeps the
/// task going: the providers below are driven by the Bible database's open
/// state, so the host rebuilds into its normal content the moment a download
/// lands, with the picker still open.
class BibleDownloadPrompt extends ConsumerStatefulWidget {
  /// Shown above the version list, to say why a Bible is needed here.
  final String message;

  const BibleDownloadPrompt({super.key, required this.message});

  @override
  ConsumerState<BibleDownloadPrompt> createState() =>
      _BibleDownloadPromptState();
}

class _BibleDownloadPromptState extends ConsumerState<BibleDownloadPrompt> {
  /// code → progress 0..1, absent when that version is not downloading.
  final Map<String, double> _progress = {};
  String? _failed;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final repo = ref.read(bibleVersionStateRepositoryProvider);
      if (await repo.isCacheFresh()) return;
      final versions =
          await ref.read(bibleVersionApiServiceProvider).getVersions();
      await repo.upsertFromServer(versions);
    } catch (_) {
      // Non-fatal: the cached registry still lists something to download.
    }
  }

  Future<void> _download(BibleVersionInfo info) async {
    if (_progress.containsKey(info.code)) return;
    setState(() {
      _progress[info.code] = 0.0;
      _failed = null;
    });
    try {
      await downloadBibleVersion(ref, info, onProgress: (p) {
        if (mounted) setState(() => _progress[info.code] = p);
      });
    } catch (_) {
      // Reported in place rather than as a snackbar: a snackbar from inside a
      // dialog is easy to miss behind it, and this is the one thing standing
      // between the user and the task they came here for.
      if (mounted) setState(() => _failed = info.code);
    } finally {
      if (mounted) setState(() => _progress.remove(info.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(bibleVersionStatesProvider);

    return versionsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        error: e,
        what: l10n(context).bibleVersions.toLowerCase(),
        onRetry: () => ref.invalidate(bibleVersionStatesProvider),
      ),
      data: (versions) {
        if (versions.isEmpty) {
          // The registry is cached locally and synced from the server, so an
          // empty list means that sync has not landed — a retry is the fix,
          // not a message saying there are no Bibles.
          return ErrorState(
            error: Exception('no connection'),
            what: l10n(context).bibleVersions.toLowerCase(),
            onRetry: () async {
              await _refresh();
              ref.invalidate(bibleVersionStatesProvider);
            },
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(AppTheme.spacing16, 0,
              AppTheme.spacing16, AppTheme.spacing16),
          children: [
            Icon(Icons.menu_book_outlined,
                size: 40, color: context.mutedText),
            const SizedBox(height: AppTheme.spacing12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: AppTheme.bodyBase.copyWith(color: context.primaryText),
            ),
            const SizedBox(height: AppTheme.spacing16),
            for (final v in versions) _versionTile(v),
            if (_failed != null) ...[
              const SizedBox(height: AppTheme.spacing12),
              Text(
                l10n(context).bibleDownloadFailed,
                textAlign: TextAlign.center,
                style: AppTheme.caption.copyWith(color: context.dangerText),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _versionTile(BibleVersionInfo info) {
    final progress = _progress[info.code];
    final downloading = progress != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacing12),
        decoration: BoxDecoration(
          color: context.subtleFill,
          borderRadius: AppTheme.borderRadiusMD,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.name,
                      style: AppTheme.bodyBase
                          .copyWith(color: context.primaryText)),
                  const SizedBox(height: 2),
                  Text(
                    '${info.code} · ${info.approximateSizeMb} MB',
                    style:
                        AppTheme.caption.copyWith(color: context.mutedText),
                  ),
                  if (downloading) ...[
                    const SizedBox(height: AppTheme.spacing8),
                    // Determinate: an 8 MB download over a slow connection is
                    // long enough that a spinner alone reads as a hang.
                    LinearProgressIndicator(value: progress),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacing8),
            if (info.isDownloaded)
              Icon(Icons.check_circle, color: context.successText)
            else if (downloading)
              Text('${(progress * 100).round()}%',
                  style: AppTheme.caption.copyWith(color: context.mutedText))
            else
              FilledButton(
                onPressed: () => _download(info),
                child: Text(l10n(context).download),
              ),
          ],
        ),
      ),
    );
  }
}
