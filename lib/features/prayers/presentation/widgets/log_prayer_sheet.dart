import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/drag_handle.dart';

/// Records that a prayer was prayed, with an optional note.
///
/// This was a bare [AlertDialog] — a title, an undecorated TextField and two
/// text buttons — on an action that is the emotional centre of the app. It is
/// a sheet now, matching quick capture: the prayer being logged is named, the
/// note field looks like a place to write, and the confirming action is a
/// filled button rather than one of two identical links.
///
/// Returns the note (possibly empty) when logged, or null if dismissed.
Future<String?> showLogPrayerSheet(
  BuildContext context, {
  required String prayerTitle,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    // Defaults to false, which would draw the top edge under the notch.
    useSafeArea: true,
    backgroundColor: context.cardSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LogPrayerSheet(prayerTitle: prayerTitle),
  );
}

class _LogPrayerSheet extends StatefulWidget {
  final String prayerTitle;
  const _LogPrayerSheet({required this.prayerTitle});

  @override
  State<_LogPrayerSheet> createState() => _LogPrayerSheetState();
}

class _LogPrayerSheetState extends State<_LogPrayerSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    // The dialog this replaces created a TextEditingController in a build
    // method and never disposed it.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = l10n(context);
    return Padding(
      // Sits above the keyboard: this sheet exists to type into.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: DragHandle()),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.brandBlue
                          .withValues(alpha: AppTheme.alphaMedium),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.check_rounded,
                        size: AppTheme.iconMD,
                        color: AppTheme.accentOnTintFor(
                            AppTheme.brandBlue, Theme.of(context).brightness)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.markThisTimeOfPrayer,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        // Naming the prayer removes the "which one is this?"
                        // question the bare dialog left open.
                        Text(
                          widget.prayerTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: context.mutedText),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Filled and bordered, so it reads as somewhere to write rather
              // than as a line under a label.
              TextField(
                controller: _controller,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontSize: 16, height: 1.4),
                decoration: InputDecoration(
                  hintText: strings.howDidItGoOptional,
                  hintStyle: TextStyle(color: context.hintText),
                  filled: true,
                  fillColor: context.subtleFill,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: AppTheme.borderRadiusLG,
                    borderSide: BorderSide(color: context.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppTheme.borderRadiusLG,
                    borderSide: BorderSide(color: context.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppTheme.borderRadiusLG,
                    borderSide:
                        const BorderSide(color: AppTheme.brandBlue, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        foregroundColor: context.mutedText,
                      ),
                      child: Text(strings.actionCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    // Filled: logging is the reason the sheet is open, and the
                    // two equal text links gave it no more weight than Cancel.
                    child: FilledButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_controller.text.trim()),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        backgroundColor: AppTheme.brandBlue,
                        foregroundColor: AppTheme.onAccent(AppTheme.brandBlue),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: Text(strings.logThisPrayer),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
