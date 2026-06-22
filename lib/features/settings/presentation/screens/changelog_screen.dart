import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/models/changelog_entry.dart';
import '../providers/changelog_provider.dart';

class ChangelogScreen extends ConsumerWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(changelogProvider);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldGray,
      appBar: AppBar(
        title: const Text("What's New"),
        backgroundColor: AppTheme.scaffoldGray,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load changelog',
                style: AppTheme.bodyBase.copyWith(color: AppTheme.gray600),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(changelogProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (entries) => entries.isEmpty
            ? Center(
                child: Text(
                  'No entries yet.',
                  style: AppTheme.bodyBase.copyWith(color: AppTheme.unselectedColor),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.spacing16,
                  AppTheme.spacing8,
                  AppTheme.spacing16,
                  40,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) =>
                    _VersionCard(entry: entries[index]),
              ),
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  final ChangelogEntry entry;
  const _VersionCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
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
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'v${entry.version}',
                    style: AppTheme.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.spacing8),
                Text(
                  entry.releaseDate,
                  style: AppTheme.caption
                      .copyWith(color: AppTheme.unselectedColor),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacing12),
            ...entry.changes.map((item) => _ChangeRow(item: item)),
          ],
        ),
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final ChangeItem item;
  const _ChangeRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.type) {
      'improvement' => (Icons.arrow_circle_up_outlined, const Color(0xFF0969DA)),
      'fix'         => (Icons.bug_report_outlined,       const Color(0xFFCF222E)),
      _             => (Icons.add_circle_outline_rounded, const Color(0xFF2DA44E)),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacing8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppTheme.spacing8),
          Expanded(
            child: Text(
              item.description,
              style: AppTheme.bodyBase.copyWith(color: AppTheme.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
