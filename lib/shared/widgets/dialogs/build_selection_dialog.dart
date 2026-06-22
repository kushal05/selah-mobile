import 'package:flutter/material.dart';

import '../../../core/services/app_update_service.dart';

/// QA-only picker that shows the most recent builds from the S3 manifest.
///
/// Returns the [AppBuildEntry] the user tapped (or `null` if they dismissed
/// the dialog) so the caller can chain the next dialog using its own
/// known-good context — picking a build here only closes this dialog; it
/// does not push the install dialog itself.
class BuildSelectionDialog extends StatelessWidget {
  final List<AppBuildEntry> builds;
  final int? currentBuildNumber;

  const BuildSelectionDialog._({
    required this.builds,
    this.currentBuildNumber,
  });

  static Future<AppBuildEntry?> show(
    BuildContext context,
    List<AppBuildEntry> builds, {
    int? currentBuildNumber,
  }) {
    return showDialog<AppBuildEntry>(
      context: context,
      builder: (_) => BuildSelectionDialog._(
        builds: builds,
        currentBuildNumber: currentBuildNumber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Available builds',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Select a build to download and install.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: builds.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, thickness: 0.5),
                itemBuilder: (_, i) {
                  final b = builds[i];
                  final isCurrent = currentBuildNumber == b.buildNumber;
                  return _BuildTile(
                    entry: b,
                    isCurrent: isCurrent,
                    onTap: () => Navigator.of(context).pop(b),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _BuildTile extends StatelessWidget {
  final AppBuildEntry entry;
  final bool isCurrent;
  final VoidCallback onTap;

  const _BuildTile({
    required this.entry,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (entry.createdAt > 0) _formatDate(entry.createdAt),
      if (entry.releaseNotes.isNotEmpty) entry.releaseNotes,
    ];

    return ListTile(
      onTap: onTap,
      leading: const Icon(
        Icons.android_outlined,
        color: Color(0xFF6B7280),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.displayLabel,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Installed',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF075985),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
      trailing: const Icon(Icons.download, size: 18, color: Color(0xFF6B7280)),
    );
  }

  String _formatDate(int millis) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $hour12:$mm $ampm';
  }
}
