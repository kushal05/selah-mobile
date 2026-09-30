// A folder count that has not arrived is not zero, and is not a failure.
//
// The folder list reads two providers: folders, handled by a `when`, and notes,
// which were reduced to `valueOrNull`. Three things followed from that on every
// cold open, while the notes query was simply still running:
//
//   * "All notes" said "Count unavailable" — a failure announced and retracted;
//   * every folder said "0 notes", because the roll-up map is empty until the
//     notes land, which is the false zero this finding is about;
//   * neither was visible to any test, because the section starts collapsed.
//
// The `null` treatment had been applied to the aggregate row only. This pins
// all three states for both rows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:notify/core/sync/models/folder_model.dart';
import 'package:notify/core/sync/providers/sync_providers.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/features/notes/domain/models/note.dart' as domain;
import 'package:notify/features/notes/presentation/providers/database_provider.dart';
import 'package:notify/features/notes/presentation/widgets/folder_section.dart';

FolderModel _folder() => FolderModel(
      id: 'f1',
      name: 'Sermons',
      userId: 'u1',
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

/// Pumps the section with [notes] as the notes stream, and opens it — the
/// section starts collapsed, which is why none of this was visible before.
Future<List<String>> _texts(
  WidgetTester tester,
  Stream<List<domain.Note>> notes,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Folders resolve, notes may not: the ordering of a real cold open.
      foldersStreamProvider.overrideWith((ref) => Stream.value([_folder()])),
      notesStreamProvider.overrideWith((ref) => notes),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: FolderSection()),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.textContaining('FOLDERS').first);
  await tester.pump(const Duration(milliseconds: 600));

  return find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toList();
}

void main() {
  testWidgets('while the notes are loading, no row claims a count',
      (tester) async {
    final texts = await _texts(
      tester,
      Stream<List<domain.Note>>.fromFuture(
          Future.delayed(const Duration(seconds: 5), () => [])),
    );

    expect(texts.any((t) => t.contains('notes') && t.contains('0')), isFalse,
        reason: 'an unread folder must not report zero: $texts');
    expect(texts.any((t) => t.contains('Count unavailable')), isFalse,
        reason: 'loading is not a failure: $texts');
    // The rows themselves must still be there — a section that stopped
    // rendering would satisfy both assertions above.
    expect(texts, contains('Sermons'));

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('once they land, the counts appear', (tester) async {
    final texts = await _texts(tester, Stream.value([]));
    expect(texts.any((t) => t.contains('0 notes')), isTrue,
        reason: 'a folder genuinely holding none still says zero: $texts');
  });

  testWidgets('a failed read says so', (tester) async {
    final texts = await _texts(
        tester, Stream<List<domain.Note>>.error(Exception('no database')));
    expect(texts.any((t) => t.contains('Count unavailable')), isTrue,
        reason: 'a real failure must be stated: $texts');
  });
}
