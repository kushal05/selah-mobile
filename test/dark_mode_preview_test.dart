// Renders the app's shared surfaces in both themes and writes PNGs, so dark
// mode can be inspected rather than reasoned about.
//
// Not an assertion test — it exists to produce images for review:
//   flutter test test/dark_mode_preview_test.dart
// writes to build/theme_preview/.
@Tags(['preview'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/shared/widgets/cards/note_row.dart';
import 'package:notify/shared/widgets/cards/overview_card.dart';
import 'package:notify/shared/widgets/cards/person_card.dart';
import 'package:notify/shared/widgets/cards/prayer_card.dart';
import 'package:notify/shared/widgets/cards/promise_card.dart';
import 'package:notify/shared/widgets/cards/song_card.dart';
import 'package:notify/shared/widgets/empty_state.dart';
import 'package:notify/shared/widgets/row_actions.dart';
import 'package:notify/shared/widgets/status_chip.dart';
import 'package:notify/shared/widgets/colored_badge.dart';
import 'package:notify/shared/widgets/feature_intro.dart';
import 'package:notify/shared/widgets/section_label.dart';
import 'package:notify/shared/widgets/filter_pill.dart';
import 'package:notify/shared/widgets/selectable_chip.dart';
import 'package:notify/shared/widgets/error_state.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _outDir = 'build/theme_preview';

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  // toImage/toByteData need the real event loop; inside the fake-async test
  // zone the second call never completes.
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(_outDir).createSync(recursive: true);
      File('$_outDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  required Widget child,
  Size size = const Size(420, 900),
  double textScale = 1.0,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: RepaintBoundary(
      key: const ValueKey('capture'),
      child: MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        // The widgets under test now read their copy from AppLocalizations,
        // so the harness has to provide it the same way the app does.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(
            textScaler: TextScaler.linear(textScale),
            // Device insets: a notch or Dynamic Island at the top, and a
            // gesture bar at the bottom.
            padding: padding,
            viewPadding: padding,
          ),
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            body: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
    ),
  );
  // Not pumpAndSettle: a focused TextField's blinking cursor is an
  // endless animation, so settle never returns.
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Builder(
        builder: (context) => Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );

Widget get _cardGallery => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Overview cards'),
        // Mirrors OverviewGrid's layout (IntrinsicHeight rows) without its
        // Riverpod/navigation dependencies.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: OverviewCard(
                          title: 'Active Prayers',
                          count: '12',
                          icon: Icons.favorite,
                          color: AppTheme.brandBlue),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: OverviewCard(
                          title: 'Recent Notes',
                          count: '34',
                          icon: Icons.description,
                          color: AppTheme.brandPurple),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: OverviewCard(
                          title: 'Promises',
                          count: '8',
                          icon: Icons.bookmark,
                          color: AppTheme.rosePink),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: OverviewCard(
                          title: 'People',
                          count: '17',
                          icon: Icons.people,
                          color: AppTheme.teal),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sectionLabel('List rows'),
        NoteRow(
          title: 'The Prodigal Son',
          preview: 'A father who runs. Grace that goes out to meet us.',
          preacherName: 'Pastor John',
          folderName: 'Luke series',
          noteDate: DateTime(2026, 3, 8),
          actions: [
            RowAction(icon: Icons.delete_outline, label: 'Trash', onSelected: () {}),
          ],
        ),
        const PrayerCard(
          title: 'Healing for Anitha',
          frequencyLabel: 'Daily',
          statusLabel: 'Active',
          statusColor: AppTheme.brandBlue,
          description: 'Recovery after surgery, and peace for the family.',
        ),
        const PromiseCard(
          reference: 'Isaiah 41:10',
          content: 'Fear not, for I am with you; be not dismayed, for I am '
              'your God.',
          conditionCount: 2,
        ),
        const PersonCard(name: 'Anitha Kumar', relation: 'Sister'),
        SongCard(
          title: 'Great Is Thy Faithfulness',
          language: 'English',
          scale: 'D',
          hasChords: true,
          isFavorite: true,
          preview: 'Morning by morning new mercies I see',
          onTap: () {},
        ),
      ],
    );

Widget get _formsGallery => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Inputs'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                    labelText: 'Title', hintText: 'Give this a name'),
              ),
              SizedBox(height: 14),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Focused', hintText: 'Focus ring should show'),
              ),
              SizedBox(height: 14),
              TextField(
                decoration: InputDecoration(
                  labelText: 'With error',
                  hintText: 'Something is wrong',
                  errorText: 'Please enter a title',
                ),
              ),
            ],
          ),
        ),
        _sectionLabel('Buttons and chips'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton(onPressed: () {}, child: const Text('Save')),
              OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
              TextButton(onPressed: () {}, child: const Text('Help')),
              const Chip(label: Text('Tag')),
              ChoiceChip(
                  label: const Text('Selected'), selected: true, onSelected: (_) {}),
            ],
          ),
        ),
        _sectionLabel('Empty state'),
        SizedBox(
          height: 340,
          child: EmptyState(
            icon: Icons.bookmark_outline_rounded,
            title: 'No promises yet',
            message: 'A promise is a verse you want to hold on to — something '
                'God has said that you want to come back to.',
            actionLabel: 'Add your first promise',
            onAction: () {},
            accent: AppTheme.rosePink,
          ),
        ),
      ],
    );

Widget get _componentsGallery => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Status chips'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              StatusChip(label: 'ACTIVE', textColor: AppTheme.statusOpen),
              StatusChip(label: 'ANSWERED', textColor: AppTheme.statusResolved),
              StatusChip(label: 'IN PROGRESS', textColor: AppTheme.statusInProgress),
              StatusChip(label: 'CLOSED', textColor: AppTheme.mutedGrey),
              StatusChip(label: 'ERROR', textColor: AppTheme.error),
            ],
          ),
        ),
        _sectionLabel('Coloured badges'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [
              ColoredBadge(label: 'sermon', color: AppTheme.brandPurple),
              ColoredBadge(label: '2 conditions', color: AppTheme.rosePink),
              ColoredBadge(label: 'daily', color: AppTheme.teal),
              ColoredBadge(label: 'answered', color: AppTheme.emerald),
            ],
          ),
        ),
        _sectionLabel('First-use intro'),
        // Wrapped the way real screens place it — the banner takes its
        // horizontal inset from the surrounding list, not from itself.
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: FeatureIntros.prayers,
        ),
        _sectionLabel('Overflow menu + empty trash'),
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RowOverflowButton(
              semanticLabel: 'Psalm 23',
              actions: [
                RowAction(
                    icon: Icons.delete_outline, label: 'Trash', onSelected: () {}),
              ],
            ),
          ),
        ),
        const SizedBox(height: 300, child: EmptyTrashState(itemsLabel: 'prayers')),
        // itemsLabel is optional, and the default now resolves through the
        // ARB rather than a literal — a path no screen exercises, so it is
        // only covered here.
        const SizedBox(height: 300, child: EmptyTrashState()),

        // The shared components promoted out of per-screen copies. They are
        // used across 20+ files now, so a change to one of them reaches most
        // of the app — which makes them the widgets that most need a visual
        // regression case, and they had none.
        _sectionLabel('Shared components'),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SectionLabel('Details'),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: FilterPill(
                    label: 'Active', count: 12, selected: true, onTap: () {}),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilterPill(
                    label: 'Answered', count: 8, selected: false, onTap: () {}),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilterPill(
                    label: 'Songs',
                    icon: Icons.music_note_rounded,
                    selected: false,
                    onTap: () {},
                    accent: AppTheme.orange),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SelectableChip(
                  label: 'family', isSelected: true, showDelete: true,
                  onTap: () {}),
              SelectableChip(label: 'healing', isSelected: false, onTap: () {}),
              SelectableChip(
                  label: 'Anitha', isSelected: true, icon: Icons.person,
                  onTap: () {}),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: ErrorState(
            error: Exception('no connection'),
            what: 'your prayers',
            onRetry: () {},
          ),
        ),
      ],
    );

void main() {
  // FeatureIntro reads the tutorial service, which reads SharedPreferences.
  SharedPreferences.setMockInitialValues({});

  final galleries = <String, Widget>{
    'cards': _cardGallery,
    'forms': _formsGallery,
    'components': _componentsGallery,
  };

  for (final entry in galleries.entries) {
    testWidgets('${entry.key} — light', (tester) async {
      await _pump(tester, theme: AppTheme.light(), child: entry.value);
      await _capture(tester, '${entry.key}_light');
    });

    testWidgets('${entry.key} — dark', (tester) async {
      await _pump(tester, theme: AppTheme.dark(), child: entry.value);
      await _capture(tester, '${entry.key}_dark');
    });

    // 200% is a common accommodation and the condition that made the old
    // fixed-aspect-ratio grid overflow.
    testWidgets('${entry.key} — light @200% text', (tester) async {
      await _pump(
        tester,
        theme: AppTheme.light(),
        child: entry.value,
        textScale: 2.0,
        size: const Size(420, 1600),
      );
      await _capture(tester, '${entry.key}_light_x2');
    });

    // Dark at 200% was never rendered: dark mode and large text were tested
    // separately, so a widget that only breaks with both was invisible.
    testWidgets('${entry.key} — dark @200% text', (tester) async {
      await _pump(
        tester,
        theme: AppTheme.dark(),
        child: entry.value,
        textScale: 2.0,
        size: const Size(420, 1600),
      );
      await _capture(tester, '${entry.key}_dark_x2');
    });

    // A phone with a cutout, on the cramped end: 59pt of Dynamic Island and
    // a 34pt gesture bar take 93pt out of an already short viewport, with
    // text at 160%.
    //
    // Note what this case can and cannot do. These galleries are cards and
    // chips — none of them reads MediaQuery padding or uses SafeArea — so
    // insets alone changed nothing, and the first version of this case
    // produced PNGs byte-identical to the plain light run. It earns its place
    // as a *space* stress, not as proof that anything insets correctly.
    // Inset behaviour is pinned by sheet_inset_test.dart instead.
    testWidgets('${entry.key} — cutout, cramped', (tester) async {
      await _pump(
        tester,
        theme: AppTheme.light(),
        child: entry.value,
        textScale: 1.6,
        size: const Size(360, 780),
        padding: const EdgeInsets.only(top: 59, bottom: 34),
      );
      await _capture(tester, '${entry.key}_cutout');
    });

    // The narrowest phone still sold. Fixed heights and Rows with unshrinkable
    // children fail here before they fail anywhere else.
    testWidgets('${entry.key} — narrow @150% text', (tester) async {
      await _pump(
        tester,
        theme: AppTheme.light(),
        child: entry.value,
        textScale: 1.5,
        size: const Size(320, 1400),
      );
      await _capture(tester, '${entry.key}_narrow');
    });
  }
}
