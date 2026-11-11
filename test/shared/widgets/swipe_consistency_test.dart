// Swiping a row to trash it means the same thing in every list: the same glyph,
// the same word ("Trash", not "Move to trash" in some and "Trash" in others), the
// same colour and the same pane width. Notes and songs had one recipe, and
// prayers, promises and people each had another.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/app_localizations.dart';
import 'package:notify/shared/widgets/swipe_action.dart';

/// The list screens whose rows trash on swipe.
const _trashLists = {
  'notes': 'lib/features/notes/presentation/screens/notes_home_screen.dart',
  'songs': 'lib/features/songs/presentation/screens/songs_home_screen.dart',
  'prayers': 'lib/features/prayers/presentation/screens/prayer_list_screen.dart',
  'promises':
      'lib/features/promises/presentation/screens/promises_list_screen.dart',
  'people': 'lib/features/people/presentation/screens/people_list_screen.dart',
};

void main() {
  group('the shared Trash action', () {
    Future<void> pump(WidgetTester tester, VoidCallback onTrash,
        {double scale = 1.0, ThemeData? theme}) async {
      await tester.pumpWidget(MaterialApp(
        theme: theme ?? AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Slidable(
              endActionPane: ActionPane(
                motion: const DrawerMotion(),
                extentRatio: swipePaneExtent(1),
                children: [
                  buildTrashSwipeAction(context, onPressed: (_) => onTrash()),
                ],
              ),
              child: const ListTile(title: Text('A row')),
            ),
          ),
        ),
      ));
    }

    testWidgets('reads "Trash" with the rounded outline bin', (tester) async {
      await pump(tester, () {});

      await tester.drag(find.text('A row'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.text('Trash'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.text('Move to trash'), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing,
          reason: 'the filled bin is the old one');
    });

    testWidgets('tapping it trashes', (tester) async {
      var trashed = 0;
      await pump(tester, () => trashed++);

      await tester.drag(find.text('A row'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trash'));
      await tester.pumpAndSettle();

      expect(trashed, 1);
    });

    for (final entry in {
      'light': AppTheme.light(),
      'dark': AppTheme.dark(),
    }.entries) {
      testWidgets('lays out at 200% text in the ${entry.key} theme',
          (tester) async {
        await pump(tester, () {}, scale: 2.0, theme: entry.value);

        await tester.drag(find.text('A row'), const Offset(-300, 0));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Trash'), findsOneWidget);
      });
    }
  });

  group('every list that trashes on swipe uses it', () {
    for (final entry in _trashLists.entries) {
      test('${entry.key} uses the shared action and the shared width', () {
        final src = File(entry.value).readAsStringSync();

        expect(src.contains('buildTrashSwipeAction('), isTrue,
            reason: '${entry.key} must use the shared Trash action');
        // Only the swipe actions: the long-press menu and the confirmation
        // dialogs legitimately say "Move to trash".
        for (final call in RegExp(r'buildSwipeAction\(')
            .allMatches(src)
            .map((m) => src.substring(m.start, (m.start + 260).clamp(0, src.length)))) {
          expect(call.contains('moveToTrash'), isFalse,
              reason: 'the swipe word is "Trash" everywhere');
          expect(RegExp(r'icon:\s*Icons\.delete,').hasMatch(call), isFalse,
              reason: 'the swipe glyph is the rounded outline bin');
        }
        expect(src.contains('extentRatio: 0.2'), isFalse,
            reason: 'pane width comes from swipePaneExtent');
      });
    }
  });
}
