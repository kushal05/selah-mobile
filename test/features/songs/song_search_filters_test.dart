// Song search: the field is in the songs colours, and the filters are a dialog.
//
// Two complaints, two fixes.
//
// The field was blue. Nobody chose that: it set only `border`, which the
// theme's `enabledBorder` and `focusedBorder` outrank, so the app-wide brandBlue
// focus ring drew around it — at once, since the field autofocuses — along with
// a blue cursor. It now uses the songs orange in every state.
//
// The filters were three chips under the field, each opening its own bottom
// sheet. They are one dialog behind a button in the field. The tag sheet also
// had a real bug: it changed the screen's selection as you ticked but searched
// only on Apply, so swiping it away left "Tags (2)" over unfiltered results.
// The dialog works on a draft, so leaving it any way but Apply changes nothing.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/sync/models/folder_model.dart';
import 'package:notify/core/sync/models/song_model.dart';
import 'package:notify/core/sync/models/tag_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/repositories/folder_repository.dart';
import 'package:notify/core/sync/repositories/song_repository.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/core/theme/theme_colors.dart';
import 'package:notify/features/songs/presentation/screens/song_search_screen.dart';
import 'package:notify/features/songs/presentation/widgets/song_filter_dialog.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/shared/widgets/filter_pill.dart';

// ── fakes ────────────────────────────────────────────────────────────────────

/// One call to searchSongsFiltered, as the screen made it.
typedef _Search = ({
  String? text,
  String? scale,
  String? folderId,
  List<String>? folderIds,
  List<String>? tagIds,
  String? language,
});

class _RecordingSongRepo implements SongRepository {
  final calls = <_Search>[];

  /// How each call is answered, by its position. Unset: at once, with nothing.
  Future<List<SongModel>> Function(int index)? respond;

  @override
  Future<List<SongModel>> searchSongsFiltered({
    required String userId,
    String? textQuery,
    List<String>? tagIds,
    String? scale,
    String? folderId,
    List<String>? folderIds,
    String? language,
  }) async {
    calls.add((
      text: textQuery,
      scale: scale,
      folderId: folderId,
      folderIds: folderIds,
      tagIds: tagIds,
      language: language,
    ));
    return respond?.call(calls.length - 1) ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FolderRepo implements FolderRepository {
  /// What getAllDescendants answers, by folder id.
  final Map<String, List<FolderModel>> children;
  _FolderRepo([this.children = const {}]);

  @override
  Future<List<FolderModel>> getAllDescendants(String folderId) async =>
      children[folderId] ?? const [];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

SongModel _song(String id, String title) => SongModel(
  id: id,
  userId: 'u1',
  title: title,
  lyrics: '',
  chords: '',
  language: 'en',
  preview: '',
  tags: '',
  hasChords: false,
  isFavorite: false,
  updatedAt: 0,
  version: 1,
  deleted: 0,
  createdAt: 0,
);

TagModel _tag(String id, String name) => TagModel(
  id: id,
  userId: 'u1',
  name: name,
  updatedAt: 0,
  version: 1,
  deleted: 0,
  createdAt: 0,
);

FolderModel _book(String id, String name) => FolderModel(
  id: id,
  userId: 'u1',
  name: name,
  type: 'song',
  updatedAt: 0,
  version: 1,
  deleted: 0,
  createdAt: 0,
);

// ── harness ──────────────────────────────────────────────────────────────────

Future<_RecordingSongRepo> _pumpScreen(
  WidgetTester tester, {
  ThemeData? theme,
  List<TagModel>? tags,
  List<FolderModel>? songbooks,
  _FolderRepo? folders,
  Duration tagDelay = Duration.zero,
  List<String> songScales = const ['C#m'],
  _RecordingSongRepo? songs,
  List<String> Function()? languages,
}) async {
  final repo = songs ?? _RecordingSongRepo();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        songRepositoryProvider.overrideWithValue(repo),
        folderRepositoryProvider.overrideWithValue(folders ?? _FolderRepo()),
        currentUserIdProvider.overrideWith((ref) => 'u1'),
        songScalesProvider.overrideWith((ref) async => songScales),
        // A function, not a list, so a test can change the answer between
        // opens and see whether the dialog asks again.
        songLanguagesProvider.overrideWith(
            (ref) async => languages?.call() ?? const ['English', 'Telugu']),
        songTagsProvider.overrideWith((ref) async {
          if (tagDelay > Duration.zero) await Future<void>.delayed(tagDelay);
          return tags ?? [_tag('t1', 'Worship'), _tag('t2', 'Hymn')];
        }),
        songFoldersStreamProvider.overrideWith(
          (ref) => Stream.value(songbooks ?? [_book('b1', 'Hillsong')]),
        ),
        // What a result card watches for its tag chips.
        tagsForSongStreamProvider
            .overrideWith((ref, id) => Stream.value(const <String>[])),
        tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SongSearchScreen(),
      ),
    ),
  );
  // The screen searches once on open, from a post-frame callback.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return repo;
}

final _filterButton = find.byTooltip('Filter songs');

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(_filterButton);
  // The dialog awaits three local loads before it opens, then animates in.
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
  expect(find.byType(SongFilterDialog), findsOneWidget,
      reason: 'the filter dialog did not open');
}

/// The four kinds of filter, each a button in the dialog.
enum _Cat { key, tags, songbook, language }

/// Found by icon, not label: a button's label changes to what is chosen
/// ("Key: G", "Telugu"), its icon does not.
const _catIcon = {
  _Cat.key: Icons.music_note_rounded,
  _Cat.tags: Icons.label_outlined,
  _Cat.songbook: Icons.library_books_outlined,
  _Cat.language: Icons.translate_rounded,
};

/// A kind's button. Buttons carry a chevron; the choices under them do not,
/// which is what keeps "Telugu" the button apart from "Telugu" the choice.
Finder _button(_Cat c) => find.descendant(
      of: find.byType(SongFilterDialog),
      matching: find.byWidgetPredicate((w) =>
          w is FilterPill && w.trailingIcon != null && w.icon == _catIcon[c]),
    );

/// A choice, by its label, among those showing.
Finder _option(String label) => find.descendant(
      of: find.byType(SongFilterDialog),
      matching: find.byWidgetPredicate((w) =>
          w is FilterPill && w.trailingIcon == null && w.label == label),
    );

/// The labels of every choice showing, in order.
List<String> _options(WidgetTester tester) => tester
    .widgetList<FilterPill>(find.descendant(
      of: find.byType(SongFilterDialog),
      matching: find.byWidgetPredicate(
          (w) => w is FilterPill && w.trailingIcon == null),
    ))
    .map((p) => p.label)
    .toList();

/// Opens [c]'s choices if they are not already open. Fixed pumps rather than
/// settling, so it also works while the screen behind shows an animated skeleton.
Future<void> _openCategory(WidgetTester tester, _Cat c) async {
  if (tester.widget<FilterPill>(_button(c)).expanded == true) return;
  await tester.tap(_button(c));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Opens [c] and taps the choice labelled [label].
Future<void> _choose(WidgetTester tester, _Cat c, String label) async {
  await _openCategory(tester, c);
  await tester.ensureVisible(_option(label));
  await tester.pump();
  await tester.tap(_option(label));
  await tester.pump();
}

Future<void> _apply(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
  await tester.pumpAndSettle();
}

// ── contrast ─────────────────────────────────────────────────────────────────

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);
double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  // ── the field ──────────────────────────────────────────────────────────────
  for (final theme in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
    group('on ${theme.key}, the search field', () {
      testWidgets('is ringed in orange when focused, not the app blue',
          (tester) async {
        await _pumpScreen(tester, theme: theme.value);
        final ctx = tester.element(find.byType(TextField));
        final ink = ctx.accentInk(AppTheme.orange);

        final field = tester.widget<TextField>(find.byType(TextField));
        final focused = field.decoration!.focusedBorder! as OutlineInputBorder;

        expect(focused.borderSide.color, ink);
        // The value the theme's own focusedBorder would have drawn: brandBlue in
        // light, brandBlueOnDark in dark. Read from the theme rather than named,
        // so the assertion follows the theme if its primary ever changes.
        expect(focused.borderSide.color,
            isNot(Theme.of(ctx).colorScheme.primary));
      });

      testWidgets('sets its resting border itself, so the theme cannot',
          (tester) async {
        // The blue got in because only `border` was set. enabledBorder is the
        // one the theme would otherwise supply.
        await _pumpScreen(tester, theme: theme.value);
        final field = tester.widget<TextField>(find.byType(TextField));

        expect(field.decoration!.enabledBorder, isNotNull);
        expect(field.decoration!.focusedBorder, isNotNull);
      });

      testWidgets('has an orange cursor and selection handles', (tester) async {
        await _pumpScreen(tester, theme: theme.value);
        final ink = tester
            .element(find.byType(TextField))
            .accentInk(AppTheme.orange);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.cursorColor, ink);

        final selection = tester
            .widget<TextSelectionTheme>(
              find.ancestor(
                of: find.byType(TextField),
                matching: find.byType(TextSelectionTheme),
              ).first,
            )
            .data;
        expect(selection.cursorColor, ink);
        expect(selection.selectionHandleColor, ink);
      });

      testWidgets('keeps its ring visible and its text readable on the tint',
          (tester) async {
        // Turning the field orange is only worth it if it still works: a ring
        // that disappears into the fill, or text that loses contrast on it,
        // would trade one complaint for another.
        await _pumpScreen(tester, theme: theme.value);
        final ctx = tester.element(find.byType(TextField));
        final field = tester.widget<TextField>(find.byType(TextField));
        final ground = theme.value.scaffoldBackgroundColor;
        final fill = Color.alphaBlend(field.decoration!.fillColor!, ground);
        final ring = (field.decoration!.focusedBorder! as OutlineInputBorder)
            .borderSide
            .color;

        expect(_ratio(ring, fill), greaterThanOrEqualTo(3.0),
            reason: 'a focus ring is graphical: 3:1 against what it surrounds');
        expect(_ratio(ctx.primaryText, fill), greaterThanOrEqualTo(4.5),
            reason: 'what you type must still read on the tinted field');
      });
    });
  }

  // ── the filters ────────────────────────────────────────────────────────────
  group('the filters', () {
    testWidgets('are no longer chips under the field', (tester) async {
      await _pumpScreen(tester);

      expect(find.byType(FilterPill), findsNothing,
          reason: 'the chips live in the dialog now');
      expect(find.text('Key'), findsNothing);
      expect(find.text('Songbook'), findsNothing);
    });

    testWidgets('open from a button at the right end of the field',
        (tester) async {
      await _pumpScreen(tester);

      expect(_filterButton, findsOneWidget);
      // Inside the field, not beside it.
      expect(
        find.descendant(of: find.byType(TextField), matching: _filterButton),
        findsOneWidget,
      );
      final field = tester.getRect(find.byType(TextField));
      final button = tester.getRect(_filterButton);
      expect(button.right, closeTo(field.right, 12),
          reason: 'the button belongs at the trailing end');
      expect(button.center.dx, greaterThan(field.center.dx));
    });

    testWidgets('offer key, tags, songbook and language as buttons',
        (tester) async {
      await _pumpScreen(tester);
      await _openDialog(tester);

      for (final c in _Cat.values) {
        expect(_button(c), findsOneWidget, reason: 'no ${c.name} button');
      }
      // Nothing open to begin with: the buttons say what is set.
      expect(_options(tester), isEmpty,
          reason: 'no choices should show until a button is tapped');
    });

    testWidgets("and each opens its own choices", (tester) async {
      await _pumpScreen(tester);
      await _openDialog(tester);

      // A standard key and the odd one a song carries; a tag; a songbook; a
      // language.
      for (final (c, choice) in [
        (_Cat.key, 'C'),
        (_Cat.key, 'C#m'),
        (_Cat.tags, 'Worship'),
        (_Cat.songbook, 'Hillsong'),
        (_Cat.language, 'Telugu'),
      ]) {
        await _openCategory(tester, c);
        expect(_option(choice), findsOneWidget,
            reason: 'no "$choice" under ${c.name}');
      }
    });

    testWidgets('are applied together, as one search', (tester) async {
      // The wiring end to end: what is chosen in the dialog is what reaches the
      // repository, in one call.
      final repo = await _pumpScreen(tester);
      final before = repo.calls.length;

      await _openDialog(tester);
      await _choose(tester, _Cat.key, 'G');
      await _choose(tester, _Cat.tags, 'Worship');
      await _choose(tester, _Cat.tags, 'Hymn');
      await _apply(tester);

      expect(repo.calls.length, before + 1, reason: 'Apply should search once');
      final call = repo.calls.last;
      expect(call.scale, 'G');
      expect(call.tagIds, unorderedEquals(['t1', 't2']));
      expect(call.folderId, isNull);
    });

    testWidgets('and the button then shows how many kinds are in force',
        (tester) async {
      await _pumpScreen(tester);
      await _openDialog(tester);
      await _choose(tester, _Cat.key, 'G');
      await _choose(tester, _Cat.tags, 'Worship');
      await _choose(tester, _Cat.tags, 'Hymn');
      await _apply(tester);

      // Key and tags: two kinds, however many tags.
      final badge = tester.widget<Badge>(
        find.descendant(of: _filterButton, matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isTrue);
      expect(
        find.descendant(of: _filterButton, matching: find.text('2')),
        findsOneWidget,
      );
    });

    testWidgets('a songbook searches its sub-folders too', (tester) async {
      // Kept from the old sheet: choosing a songbook includes everything filed
      // beneath it.
      final repo = await _pumpScreen(
        tester,
        folders: _FolderRepo({
          'b1': [_book('b1a', 'Hillsong — Live')],
        }),
      );

      await _openDialog(tester);
      await _choose(tester, _Cat.songbook, 'Hillsong');
      await _apply(tester);

      expect(repo.calls.last.folderId, 'b1');
      expect(repo.calls.last.folderIds, ['b1', 'b1a']);
    });

    testWidgets('Cancel changes nothing', (tester) async {
      final repo = await _pumpScreen(tester);
      final before = repo.calls.length;

      await _openDialog(tester);
      await _choose(tester, _Cat.tags, 'Worship');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.calls.length, before, reason: 'no search on Cancel');
      final badge = tester.widget<Badge>(
        find.descendant(of: _filterButton, matching: find.byType(Badge)),
      );
      expect(badge.isLabelVisible, isFalse,
          reason: 'a cancelled choice must not show as applied');
    });

    testWidgets('and neither does dismissing it from outside', (tester) async {
      // The old tag sheet's bug: it mutated the selection as you ticked, so
      // dismissing it any way but Apply left a selection nobody searched with.
      final repo = await _pumpScreen(tester);
      final before = repo.calls.length;

      await _openDialog(tester);
      await _choose(tester, _Cat.tags, 'Worship');
      await tester.tapAt(const Offset(4, 4)); // the barrier
      await tester.pumpAndSettle();

      expect(find.byType(SongFilterDialog), findsNothing);
      expect(repo.calls.length, before);

      // Reopening shows what is actually applied — nothing.
      await _openDialog(tester);
      expect(tester.widget<FilterPill>(_button(_Cat.tags)).selected, isFalse);
      await _openCategory(tester, _Cat.tags);
      expect(tester.widget<FilterPill>(_option('Worship')).selected, isFalse);
    });

    testWidgets('a slow typed search cannot overwrite applied filters',
        (tester) async {
      // Typing and applying filters both start a search, and nothing ordered
      // them. A typed search still running when filters were applied could
      // finish second and show its unfiltered results under a filter badge.
      //
      // The typed search is held on a Completer and released by hand, after
      // the filtered one has landed. A delay would not do: the first version of
      // this test used a 5s timer, and the pumpAndSettle inside choosing a key
      // ran the clock past it, so the slow search finished first — the harmless
      // order — and the test passed with the fix removed.
      final typed = Completer<List<SongModel>>();
      final songs = _RecordingSongRepo()
        ..respond = (i) =>
            i == 1 ? typed.future : Future.value(const <SongModel>[]);
      await _pumpScreen(tester, songs: songs);

      await tester.enterText(find.byType(TextField), 'grace');
      await tester.pump(const Duration(milliseconds: 300)); // past the debounce
      expect(songs.calls, hasLength(2), reason: 'the typed search should run');

      // Filters applied while the typed search is still out. Fixed pumps, not
      // pumpAndSettle: while a search is pending the results area shows an
      // animated skeleton, so the screen never settles.
      Future<void> frames() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(_filterButton);
      await frames();
      expect(find.byType(SongFilterDialog), findsOneWidget);
      await _choose(tester, _Cat.key, 'G');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(songs.calls, hasLength(3));
      expect(songs.calls.last.scale, 'G');
      expect(typed.isCompleted, isFalse,
          reason: 'the typed search must still be out, or nothing is tested');

      // Now the typed search lands, last.
      typed.complete([_song('s1', 'Amazing Grace')]);
      await tester.pump();
      await tester.pump();

      expect(find.text('Amazing Grace'), findsNothing,
          reason: 'the stale, unfiltered result must not replace the newer one');
    });

    testWidgets('though a result that is current does show', (tester) async {
      // The control for the test above: the same song, from the newest search,
      // is on screen. Without this, "findsNothing" could pass because result
      // cards never render at all.
      final songs = _RecordingSongRepo()
        ..respond = (_) => Future.value([_song('s1', 'Amazing Grace')]);
      await _pumpScreen(tester, songs: songs);

      expect(find.text('Amazing Grace'), findsOneWidget);
    });

    testWidgets('list keys in musical order, majors before minors',
        (tester) async {
      // Alphabetical order interleaved them — A, Ab, Abm, Am — so finding a
      // key meant reading the whole grid. A key a song uses that the standard
      // lists do not have still appears, at the end.
      await _pumpScreen(tester, songScales: const ['C#m', 'Dsus4']);
      await _openDialog(tester);
      await _openCategory(tester, _Cat.key);

      // Only the key choices show now, so the whole list is the answer.
      final keys = _options(tester);
      expect(keys.first, 'Any key');

      expect(keys.sublist(1), [
        'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
        'Cm', 'C#m', 'Dm', 'Ebm', 'Em', 'Fm', 'F#m', 'Gm', 'Abm', 'Am', 'Bbm',
        'Bm',
        'Dsus4',
      ]);
    });

    testWidgets('and lay them out as a grid, not a column', (tester) async {
      // The dialog-level half of the pill width fix: keys share rows.
      await _pumpScreen(tester);
      await _openDialog(tester);
      await _openCategory(tester, _Cat.key);

      Rect key(String k) => tester.getRect(_option(k));
      expect(key('C#').top, key('C').top,
          reason: 'neighbouring keys should share a line');
    });

    testWidgets('open once however fast the button is tapped',
        (tester) async {
      // The dialog waits for its data before it appears. A second tap in that
      // gap used to open a second dialog beneath the first, holding the old
      // filters, so Apply on it undid what had just been applied.
      await _pumpScreen(tester, tagDelay: const Duration(milliseconds: 300));

      await tester.tap(_filterButton);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(_filterButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.byType(SongFilterDialog), findsOneWidget);
    });

    testWidgets('and open again once the first is closed', (tester) async {
      // The guard must let go. One that stuck would leave the button dead.
      await _pumpScreen(tester);
      await _openDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await _openDialog(tester);
      expect(find.byType(SongFilterDialog), findsOneWidget);
    });

    testWidgets('a language reaches the search, and counts as a kind',
        (tester) async {
      final repo = await _pumpScreen(tester);
      await _openDialog(tester);
      await _choose(tester, _Cat.language, 'Telugu');
      await _choose(tester, _Cat.key, 'G');
      await _apply(tester);

      expect(repo.calls.last.language, 'Telugu');
      expect(repo.calls.last.scale, 'G');
      expect(
        find.descendant(of: _filterButton, matching: find.text('2')),
        findsOneWidget,
        reason: 'key and language: two kinds in force',
      );
    });

    testWidgets('the choices are read afresh each time the dialog opens',
        (tester) async {
      // Keys, tags and languages come from providers that load once and are
      // kept. Read as they were, a song added in a new language mid-session
      // never reached the filter until the app restarted.
      var langs = ['English', 'Telugu'];
      await _pumpScreen(tester, languages: () => langs);

      await _openDialog(tester);
      await _openCategory(tester, _Cat.language);
      expect(_option('Tamil'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      langs = ['English', 'Tamil', 'Telugu']; // a Tamil song was added

      await _openDialog(tester);
      await _openCategory(tester, _Cat.language);
      expect(_option('Tamil'), findsOneWidget,
          reason: 'the new language should be offered on the next open');
    });

    testWidgets('reopen showing what is applied', (tester) async {
      await _pumpScreen(tester);
      await _openDialog(tester);
      await _choose(tester, _Cat.tags, 'Hymn');
      await _apply(tester);

      await _openDialog(tester);
      // The button says so before anything is opened…
      expect(tester.widget<FilterPill>(_button(_Cat.tags)).count, 1);
      // …and the choice is ticked when it is.
      await _openCategory(tester, _Cat.tags);
      expect(tester.widget<FilterPill>(_option('Hymn')).selected, isTrue);
    });
  });

  // ── the dialog on its own ──────────────────────────────────────────────────
  group('the dialog', () {
    Future<SongSearchFilters?> pumpDialog(
      WidgetTester tester, {
      SongSearchFilters initial = SongSearchFilters.none,
      List<TagModel> tags = const [],
      List<FolderModel> songbooks = const [],
      List<String> languages = const [],
      ThemeData? theme,
      Future<void> Function()? interact,
    }) async {
      SongSearchFilters? result;
      var closed = false;
      await tester.pumpWidget(MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  result = await SongFilterDialog.show(
                    context,
                    initial: initial,
                    scales: const ['C', 'G', 'Am'],
                    tags: tags,
                    songbooks: songbooks,
                    languages: languages,
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      if (interact != null) await interact();
      return closed ? result : null;
    }

    testWidgets('tapping the chosen key again lets it go', (tester) async {
      await pumpDialog(tester, interact: () async {
        await _choose(tester, _Cat.key, 'G');
        await _choose(tester, _Cat.key, 'G');
      });
      expect(tester.widget<FilterPill>(_option('Any key')).selected, isTrue);
    });

    testWidgets('Clear all is off when there is nothing to clear',
        (tester) async {
      await pumpDialog(tester);
      final clear = tester.widget<TextButton>(
          find.widgetWithText(TextButton, 'Clear all'));
      expect(clear.onPressed, isNull);
    });

    testWidgets('and clears the draft without closing', (tester) async {
      await pumpDialog(
        tester,
        initial: const SongSearchFilters(scale: 'G'),
        interact: () async {
          await tester.tap(find.widgetWithText(TextButton, 'Clear all'));
          await tester.pump();
        },
      );
      expect(find.byType(SongFilterDialog), findsOneWidget,
          reason: 'clearing is still a choice you can Cancel');
      final key = tester.widget<FilterPill>(_button(_Cat.key));
      expect(key.label, 'Key');
      expect(key.selected, isFalse);
      await _openCategory(tester, _Cat.key);
      expect(tester.widget<FilterPill>(_option('Any key')).selected, isTrue);
    });

    testWidgets('has no songbook section when there are no songbooks',
        (tester) async {
      await pumpDialog(tester);
      expect(_button(_Cat.songbook), findsNothing);
      expect(find.text('All songbooks'), findsNothing);
    });

    testWidgets('says so when there are no tags', (tester) async {
      await pumpDialog(tester);
      await _openCategory(tester, _Cat.tags);
      expect(find.text('No tags available'), findsOneWidget);
    });

    testWidgets('one kind is open at a time, and tapping it again closes it',
        (tester) async {
      await pumpDialog(tester, tags: [_tag('t1', 'Worship')]);

      await _openCategory(tester, _Cat.key);
      expect(_option('Any key'), findsOneWidget);

      await _openCategory(tester, _Cat.tags);
      expect(_option('Worship'), findsOneWidget);
      expect(_option('Any key'), findsNothing,
          reason: 'opening tags should close key');

      await tester.tap(_button(_Cat.tags));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_options(tester), isEmpty, reason: 'a second tap closes it');
    });

    testWidgets('and screen readers hear which one is open', (tester) async {
      // The chevron says it on screen; `expanded` says it to TalkBack and
      // VoiceOver, which cannot see the chevron.
      final handle = tester.ensureSemantics();
      await pumpDialog(tester);

      // The Semantics node inside the pill. Asking for the pill's own element
      // returns the nearest ancestor node instead — the whole button row.
      SemanticsNode node() => tester.getSemantics(find
          .descendant(of: _button(_Cat.key), matching: find.byType(Semantics))
          .first);

      expect(node(),
          isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
      await _openCategory(tester, _Cat.key);
      expect(node(),
          isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
      handle.dispose();
    });

    testWidgets('each button says what is chosen without being opened',
        (tester) async {
      await pumpDialog(
        tester,
        initial: const SongSearchFilters(
          scale: 'G',
          tagIds: {'t1', 't2'},
          folderId: 'b1',
          language: 'Telugu',
        ),
        tags: [_tag('t1', 'Worship'), _tag('t2', 'Hymn')],
        songbooks: [_book('b1', 'Hillsong')],
        languages: const ['English', 'Telugu'],
      );

      FilterPill b(_Cat c) => tester.widget<FilterPill>(_button(c));
      expect(b(_Cat.key).label, 'Key: G');
      expect(b(_Cat.tags).count, 2);
      expect(b(_Cat.songbook).label, 'Hillsong');
      expect(b(_Cat.language).label, 'Telugu');
      for (final c in _Cat.values) {
        expect(b(c).selected, isTrue, reason: '${c.name} has a value set');
      }
    });

    testWidgets("each section is headed with its button's name",
        (tester) async {
      // Songbook used to open under "Songbooks" while the other three matched
      // their buttons. Two of each name: the button, and the heading it opens.
      await pumpDialog(
        tester,
        tags: [_tag('t1', 'Worship')],
        songbooks: [_book('b1', 'Hillsong')],
        languages: const ['English', 'Telugu'],
      );
      for (final (c, name) in [
        (_Cat.key, 'Key'),
        (_Cat.tags, 'Tags'),
        (_Cat.songbook, 'Songbook'),
        (_Cat.language, 'Language'),
      ]) {
        await _openCategory(tester, c);
        expect(
          find.descendant(
              of: find.byType(SongFilterDialog), matching: find.text(name)),
          findsNWidgets(2),
          reason: '${c.name}: the button and its section heading',
        );
      }
    });

    testWidgets('language is offered only when there is a choice to make',
        (tester) async {
      // Every song in one language: a Language button would offer one answer.
      await pumpDialog(tester, languages: const ['English']);
      expect(_button(_Cat.language), findsNothing);
    });

    testWidgets('but stays while a language filter is set, so it can be removed',
        (tester) async {
      await pumpDialog(
        tester,
        initial: const SongSearchFilters(language: 'English'),
        languages: const ['English'],
      );
      expect(_button(_Cat.language), findsOneWidget);
    });

    testWidgets('an open kind whose button goes away takes its choices with it',
        (tester) async {
      // One language, filtered by it, its choices open. Clear all removes the
      // filter, so the button is no longer offered — its choices must not be
      // left hanging under a row without it.
      await pumpDialog(
        tester,
        initial: const SongSearchFilters(language: 'English'),
        languages: const ['English'],
        interact: () async {
          await _openCategory(tester, _Cat.language);
          expect(_option('Any language'), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, 'Clear all'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        },
      );
      expect(_button(_Cat.language), findsNothing);
      expect(_options(tester), isEmpty);
    });

    for (final theme
        in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
      testWidgets('Cancel and Clear all are not the app blue, '
          'and read on the dialog, on ${theme.key}', (tester) async {
        // Left to the theme they drew brandBlue, the colour this screen was
        // asked to drop. Orange text fails 4.5:1 on the light dialog surface
        // (4.33), so they are neutral; this pins both halves of that.
        await pumpDialog(tester,
            theme: theme.value,
            initial: const SongSearchFilters(scale: 'G')); // Clear all enabled

        final surfaceMaterial = tester.widget<Material>(find
            .descendant(of: find.byType(Dialog), matching: find.byType(Material))
            .first);
        final surface = Color.alphaBlend(
            surfaceMaterial.color!, theme.value.scaffoldBackgroundColor);

        for (final label in ['Cancel', 'Clear all']) {
          final button =
              tester.widget<TextButton>(find.widgetWithText(TextButton, label));
          final fg = button.style!.foregroundColor!.resolve({})!;
          expect(fg, isNot(theme.value.colorScheme.primary),
              reason: '$label must not fall through to the theme blue');
          expect(_ratio(fg, surface), greaterThanOrEqualTo(4.5),
              reason: '$label is text, so it needs 4.5:1');
        }
      });
    }

    for (final theme
        in {'light': AppTheme.light(), 'dark': AppTheme.dark()}.entries) {
      testWidgets('Apply is the songs orange with a readable label, '
          'on ${theme.key}', (tester) async {
        // The true orange, not the darkened orangeSurface: onAccent picks the
        // label that clears it. A label needs 4.5:1.
        await pumpDialog(tester, theme: theme.value);
        final apply =
            tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'));
        final bg = apply.style!.backgroundColor!.resolve({})!;
        final fg = apply.style!.foregroundColor!.resolve({})!;

        expect(bg, AppTheme.orange);
        expect(_ratio(fg, bg), greaterThanOrEqualTo(4.5));
      });
    }
  });

  // ── small screens, large text ──────────────────────────────────────────────
  group('on a small phone with text at its largest', () {
    // The app clamps text scaling at 2.0. At 320pt and 2.0 the old action bar —
    // Clear all on the left, Cancel and Apply grouped in a Row on the right —
    // overflowed by 23pt and clipped Apply, because a Row cannot wrap.
    Future<List<String>> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width * 3, 700 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError =
          (d) => errors.add(d.exceptionAsString().split('\n').first);
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: const Scaffold(
          body: SongFilterDialog(
            initial: SongSearchFilters(scale: 'G'),
            scales: ['C', 'G', 'Am'],
            tags: [],
            songbooks: [],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      FlutterError.onError = previous;
      return errors;
    }

    for (final width in [320.0, 360.0]) {
      testWidgets('nothing overflows at ${width.toInt()}pt', (tester) async {
        final errors = await pumpAt(tester, width);
        expect(errors, isEmpty);
      });

      testWidgets('and Apply is wholly inside the dialog at ${width.toInt()}pt',
          (tester) async {
        await pumpAt(tester, width);
        final dialog = tester.getRect(find.byType(Dialog));
        final apply = tester.getRect(find.widgetWithText(FilledButton, 'Apply'));

        expect(apply.left, greaterThanOrEqualTo(dialog.left));
        expect(apply.right, lessThanOrEqualTo(dialog.right),
            reason: 'Apply must not be pushed past the edge');
      });
    }

    testWidgets('at a normal size, Clear all sits beside the title',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SongFilterDialog(
            initial: SongSearchFilters.none,
            scales: ['C'],
            tags: [],
            songbooks: [],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final title = tester.getRect(find.text('Filter songs'));
      final clear =
          tester.getRect(find.widgetWithText(TextButton, 'Clear all'));
      expect(clear.center.dy, closeTo(title.center.dy, 4),
          reason: 'on one line when there is room');
      expect(clear.left, greaterThan(title.right));
    });
  });
}
