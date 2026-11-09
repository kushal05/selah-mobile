import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../providers/bible_download_manager.dart';

/// Thin app-wide progress bar for Bible downloads, shown in the app shell so a
/// download started on one screen stays visible after leaving it. Also reports
/// completion and failure with a snackbar, since the screen that started the
/// download may be gone.
class BibleDownloadIndicator extends ConsumerWidget {
  const BibleDownloadIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<Map<String, BibleDownloadState>>(bibleDownloadManagerProvider,
        (prev, next) {
      for (final s in next.values) {
        final wasActive = prev?[s.code]?.isActive ?? false;
        if (!wasActive) continue;
        final String? message = switch (s.status) {
          BibleDownloadStatus.done => '${s.name} downloaded.',
          BibleDownloadStatus.failed => l10n(context).bibleDownloadFailed,
          _ => null,
        };
        if (message == null) continue;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ));
      }
    });

    final active = ref
        .watch(bibleDownloadManagerProvider)
        .values
        .where((s) => s.isActive)
        .toList();
    if (active.isEmpty) return const SizedBox.shrink();

    final progress = active.map((s) => s.progress).reduce((a, b) => a > b ? a : b);
    return Semantics(
      label: 'Downloading Bible version',
      child: LinearProgressIndicator(
        minHeight: 2,
        value: progress > 0 ? progress : null,
      ),
    );
  }
}
