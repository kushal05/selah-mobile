import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/reading_preferences.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/drag_handle.dart';
import '../providers/bible_reader_preferences.dart';

/// How the chapter text looks: size, typeface, line spacing and verse numbers.
/// The text size is the app-wide reading size, shared with notes and lyrics.
Future<void> showReaderSettingsSheet(BuildContext context,
    {ThemeData? theme}) {
  return showModalBottomSheet<void>(
    useSafeArea: true,
    context: context,
    isScrollControlled: true,
    backgroundColor:
        (theme ?? Theme.of(context)).colorScheme.surfaceContainerHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => theme == null
        ? const _ReaderSettingsSheet()
        : Theme(data: theme, child: const _ReaderSettingsSheet()),
  );
}

class _ReaderSettingsSheet extends ConsumerWidget {
  const _ReaderSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = l10n(context);
    final theme = Theme.of(context);
    final size = ref.watch(readingTextSizeProvider);
    final typeface = ref.watch(readerTypefaceProvider);
    final spacing = ref.watch(readerLineSpacingProvider);
    final showNumbers = ref.watch(readerShowVerseNumbersProvider);
    final readerTheme = ref.watch(readerThemeProvider);

    Widget label(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const DragHandle(),
            Text(
              t.readingSettings,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            label(t.readerPageColor),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final rt in ReaderTheme.values)
                  _ThemeSwatch(
                    theme: rt,
                    label: switch (rt) {
                      ReaderTheme.auto => t.readerThemeAuto,
                      ReaderTheme.light => t.readerThemeLight,
                      ReaderTheme.sepia => t.readerThemeSepia,
                      ReaderTheme.slate => t.readerThemeSlate,
                      ReaderTheme.night => t.readerThemeNight,
                    },
                    selected: rt == readerTheme,
                    onTap: () =>
                        ref.read(readerThemeProvider.notifier).set(rt),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            label(t.textSize),
            Row(
              children: [
                const Text('A', style: TextStyle(fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: size.index.toDouble(),
                    min: 0,
                    max: (ReadingTextSize.values.length - 1).toDouble(),
                    divisions: ReadingTextSize.values.length - 1,
                    label: size.label,
                    semanticFormatterCallback: (v) =>
                        ReadingTextSize.values[v.round()].label,
                    onChanged: (v) => ref
                        .read(readingTextSizeProvider.notifier)
                        .set(ReadingTextSize.values[v.round()]),
                  ),
                ),
                const Text('A', style: TextStyle(fontSize: 24)),
              ],
            ),
            const SizedBox(height: 12),
            label(t.readerTypeface),
            SegmentedButton<ReaderTypeface>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: ReaderTypeface.serif,
                    label: Text(t.readerTypefaceSerif)),
                ButtonSegment(
                    value: ReaderTypeface.sans,
                    label: Text(t.readerTypefaceSans)),
              ],
              selected: {typeface},
              onSelectionChanged: (s) =>
                  ref.read(readerTypefaceProvider.notifier).set(s.single),
            ),
            const SizedBox(height: 20),
            label(t.readerLineSpacing),
            SegmentedButton<ReaderLineSpacing>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: ReaderLineSpacing.compact,
                    label: Text(t.readerLineSpacingCompact)),
                ButtonSegment(
                    value: ReaderLineSpacing.normal,
                    label: Text(t.readerLineSpacingNormal)),
                ButtonSegment(
                    value: ReaderLineSpacing.roomy,
                    label: Text(t.readerLineSpacingRoomy)),
              ],
              selected: {spacing},
              onSelectionChanged: (s) =>
                  ref.read(readerLineSpacingProvider.notifier).set(s.single),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t.readerShowVerseNumbers),
              value: showNumbers,
              onChanged: (v) =>
                  ref.read(readerShowVerseNumbersProvider.notifier).set(v),
            ),
          ],
        ),
      ),
    );
  }
}

/// One page colour to pick: a disc in the theme's own colours, named below.
class _ThemeSwatch extends StatelessWidget {
  final ReaderTheme theme;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeSwatch({
    required this.theme,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = theme.background ?? scheme.surfaceContainerHighest;
    final fg = theme.text ?? scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.primary : scheme.outlineVariant,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: theme == ReaderTheme.auto
                      ? Icon(Icons.brightness_auto_rounded, size: 22, color: fg)
                      : Text('Aa',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: fg)),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
