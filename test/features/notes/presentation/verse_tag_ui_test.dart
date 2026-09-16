// Tagging a Bible reference from the note editor. The control sits in the
// bottom-right of the expanded accordion and the tag belongs to the whole
// reference.
//
// The providers are faked rather than backed by a real database: drift's I/O
// cannot complete inside a widget test's fake-async zone, so a test that let
// the widget reach the database simply hung. Creation itself is covered where
// it belongs, against a real database, in note_tag_lifecycle_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  testWidgets('the expanded block offers a way to add a tag', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));

    expect(find.byIcon(Icons.local_offer_outlined), findsOneWidget);
  });

  testWidgets('a read-only host gets no tag control', (tester) async {
    // The note detail screen renders this widget without a callback; it must
    // not offer an affordance that cannot do anything.
    await pumpBlock(tester, reference: refWith(const []), editable: false);

    expect(find.byIcon(Icons.local_offer_outlined), findsNothing);
  });

  testWidgets('tapping the icon opens a field', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));

    await tester.tap(find.byIcon(Icons.local_offer_outlined));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('submitting a name hands the new tag back', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));

    await tester.tap(find.byIcon(Icons.local_offer_outlined));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Faith');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(repo.requested, ['Faith']);
    expect(changed, ['new-tag']);
  });

  testWidgets('an empty name adds nothing', (tester) async {
    await pumpBlock(tester, reference: refWith(const []));

    await tester.tap(find.byIcon(Icons.local_offer_outlined));
    await tester.pump();
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
    await tester.pump();

    await tester.tap(find.text('grace'));
    await tester.pump();

    expect(changed, ['t2']);
  });
}
