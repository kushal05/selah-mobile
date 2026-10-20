// Tagging a Bible reference from the note editor. Adding a tag starts from the
// card's ⋮ menu, the chips sit under the verse, and the tag belongs to the
// whole reference.
//
// The providers are faked rather than backed by a real database: drift's I/O
// cannot complete inside a widget test's fake-async zone, so a test that let
// the widget reach the database simply hung. Creation itself is covered where
// it belongs, against a real database, in note_tag_lifecycle_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:notify/shared/widgets/selectable_chip.dart';
import 'package:notify/core/sync/models/tag_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/sync/repositories/tag_repository.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/features/bible/domain/models/bible_reference.dart';
import 'package:notify/features/notes/presentation/widgets/editor/bible_reference_block_widget.dart';

const _userId = 'test-user';

TagModel tag(String id, String name) =>
    TagModel.create(id: id, userId: _userId, name: name);

/// Returns a canned tag and records what it was asked for.
class FakeTagRepo implements TagRepository {
  final List<String> requested = [];

  @override
  Future<TagModel> getOrCreateTag(String name, String userId) async {
    requested.add(name);
    // The real one lowercases; mirror that so the test cannot pass on a
    // behaviour the widget is relying on but not getting.
    return tag('new-tag', TagRepository.normaliseName(name));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

BibleReference refWith(List<String> tagIds) => BibleReference(
      reference: const BibleVerseReference(
        book: 'John',
        chapter: 3,
        verses: [16],
        version: 'nkjv',
      ),
      text: const [BibleVerseText(verse: 16, content: 'For God so loved...')],
      tagIds: tagIds,
    );

void main() {
  late FakeTagRepo repo;
  List<String>? changed;

  setUp(() {
    repo = FakeTagRepo();
    changed = null;
  });

  Future<void> pumpBlock(
    WidgetTester tester, {
    required BibleReference reference,
    List<TagModel> existingTags = const [],
    bool editable = true,
  }) async {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        tagRepositoryProvider.overrideWithValue(repo),
        tagsStreamProvider.overrideWith((ref) => Stream.value(existingTags)),
        currentUserIdProvider.overrideWith((ref) => _userId),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BibleReferenceBlockWidget(
              reference: reference,
              onTagsChanged: editable ? (ids) => changed = ids : null,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
  }

  /// Add tag, from the ⋮ menu.
  Future<void> startAddingTag(WidgetTester tester) async {
    await openMenu(tester);
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();
  }

  testWidgets('the menu offers a way to add a tag', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));
    await openMenu(tester);

    expect(find.text('Add tag'), findsOneWidget);
  });

  testWidgets('a read-only host gets no tag control', (tester) async {
    // The note detail screen renders this widget without a callback; it must
    // not offer an affordance that cannot do anything.
    await pumpBlock(tester, reference: refWith(const []), editable: false);
    await openMenu(tester);

    expect(find.text('Add tag'), findsNothing);
    expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
  });

  testWidgets('Add tag opens a field', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));
    await startAddingTag(tester);

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submitting a name hands the new tag back', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));

    await startAddingTag(tester);
    await tester.enterText(find.byType(TextField), 'Faith');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repo.requested, ['Faith']);
    expect(changed, ['new-tag']);
  });

  testWidgets('an empty name adds nothing', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));

    await startAddingTag(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repo.requested, isEmpty);
    expect(changed, isNull);
  });

  testWidgets('existing tags show as chips', (tester) async {
    await pumpBlock(
      tester,
      reference: refWith(['t1']),
      existingTags: [tag('t1', 'grace')],
    );
    await tester.pump();

    expect(find.text('grace'), findsOneWidget);
  });

  testWidgets('a tag whose name has not arrived is not shown as a raw id',
      (tester) async {
    await pumpBlock(tester, reference: refWith(['t-unknown']));
    await tester.pump();

    expect(find.text('t-unknown'), findsNothing);
  });

  testWidgets('tapping a chip removes that tag', (tester) async {
    await pumpBlock(
      tester,
      reference: refWith(['t1', 't2']),
      existingTags: [tag('t1', 'grace'), tag('t2', 'hope')],
    );
    // The chip row appears once the tag names arrive, and the card grows to
    // fit it; a tap during that growth lands outside the card.
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('grace'));
    await tester.pump();

    expect(changed, ['t2']);
  });

  testWidgets('long tag names on a narrow screen do not overflow',
      (tester) async {
    // The chip could not yield, so two ordinary tag names ran 306px off a
    // 320pt screen. Fixed in SelectableChip, which four tag inputs share;
    // this holds the line here.
    tester.view.physicalSize = const Size(320, 640) * 3;
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        tagRepositoryProvider.overrideWithValue(repo),
        tagsStreamProvider.overrideWith((ref) => Stream.value([
              tag('t1', 'thanksgiving-and-praise-and-more'),
              tag('t2', 'intercession-for-the-nations'),
            ])),
        currentUserIdProvider.overrideWith((ref) => _userId),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: BibleReferenceBlockWidget(
              reference: refWith(const ['t1', 't2']),
              onTagsChanged: (ids) => changed = ids,
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  group('where the tag control lives', () {
    testWidgets('in the ⋮ menu, not as a lone icon on the card',
        (tester) async {
      // It used to sit by itself at the bottom-right of the card.
      await pumpBlock(tester, reference: refWith(const []));
      expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
      await openMenu(tester);
      expect(find.text('Add tag'), findsOneWidget);
    });

    testWidgets('on a closed card it opens the card and the field',
        (tester) async {
      await pumpBlock(tester, reference: refWith(const []));
      await tester.tap(find.textContaining('John 3:16')); // close it
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('so loved'), findsNothing,
          reason: 'precondition: closed');

      await startAddingTag(tester);
      expect(find.textContaining('so loved'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('chips line up with the verse on the left', (tester) async {
      await pumpBlock(
        tester,
        reference: refWith(['t1']),
        existingTags: [tag('t1', 'grace')],
      );
      await tester.pump(const Duration(milliseconds: 300));
      final chip = find.ancestor(
          of: find.text('grace'), matching: find.byType(SelectableChip));
      expect(tester.getTopLeft(chip).dx,
          closeTo(tester.getTopLeft(find.textContaining('so loved')).dx, 0.5));
    });

    testWidgets('with no tags, no empty row is left under the verse',
        (tester) async {
      // Measured against the read-only card, which never has a tag row: with
      // no tags the editable one should end as close below the verse.
      double gapBelowVerse() =>
          tester.getRect(find.byType(AnimatedSize)).bottom -
          tester.getRect(find.textContaining('so loved')).bottom;
      // Both pumped into the same tree, so the card is updated in place and
      // its AnimatedSize grows to the new height over 200ms; measured at once
      // it still reports the old one, and the two would always agree.
      await pumpBlock(tester, reference: refWith(const []), editable: false);
      await tester.pump(const Duration(milliseconds: 300));
      final readOnly = gapBelowVerse();
      await pumpBlock(tester, reference: refWith(const []));
      await tester.pump(const Duration(milliseconds: 300));
      expect(gapBelowVerse(), closeTo(readOnly, 0.5));
    });
  });

  testWidgets('Add tag puts the cursor in the tag field, not back in the note',
      (tester) async {
    // In the editor a line of the note nearly always has the cursor. Closing
    // the menu hands focus back to it, and the tag field's autofocus only
    // takes focus when nothing has it — so the tag typed went into the note.
    final noteLine = FocusNode(debugLabel: 'note line');
    addTearDown(noteLine.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tagRepositoryProvider.overrideWithValue(repo),
        tagsStreamProvider.overrideWith((ref) => Stream.value(const [])),
        currentUserIdProvider.overrideWith((ref) => _userId),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [
              TextField(focusNode: noteLine),
              BibleReferenceBlockWidget(
                reference: refWith(const []),
                onTagsChanged: (ids) => changed = ids,
              ),
            ]),
          ),
        ),
      ),
    ));
    noteLine.requestFocus();
    await tester.pump();

    await startAddingTag(tester);
    final tagField = tester.widget<EditableText>(find.descendant(
        of: find.byType(TextField).last, matching: find.byType(EditableText)));
    expect(tagField.focusNode.hasFocus, isTrue);
    expect(noteLine.hasFocus, isFalse);
  });
}
