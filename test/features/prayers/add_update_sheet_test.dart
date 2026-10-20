// The "Add update" sheet on a prayer's page.
//
// It hard-coded light-theme colours: a #FBFAFA field and a #BDBDBD hint. In
// dark mode that was a white slab with the dark theme's light text barely
// visible on it — and the contrast audit, which only knew Colors.* names,
// never saw either. Now built on SelahSheet, with every colour from the theme.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/domain/enums/prayer_enums.dart';
import 'package:notify/core/sync/models/prayer_collaborator_model.dart';
import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/core/theme/theme_colors.dart';
import 'package:notify/features/prayers/presentation/widgets/add_update_sheet.dart';
import 'package:notify/l10n/l10n.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

PrayerCollaboratorModel _collaborator(String username) => PrayerCollaboratorModel(
      id: 'c-$username',
      prayerId: 'p1',
      sharedPrayerId: 's1',
      collaboratorUserId: 'u-$username',
      collaboratorUsername: username,
      role: CollaboratorRole.collaborator,
      addedByUserId: 'u1',
      userId: 'u1',
      updatedAt: 0,
      version: 1,
      deleted: 0,
      createdAt: 0,
    );

Future<({Object? Function() result, bool Function() done})> _open(
  WidgetTester tester, {
  ThemeData? theme,
  List<PrayerCollaboratorModel> collaborators = const [],
}) async {
  Object? result;
  var done = false;
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await showAddUpdateSheet(context,
                  prayerTitle: 'Healing for Mom', collaborators: collaborators);
              done = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (result: () => result, done: () => done);
}

final _add = find.widgetWithText(FilledButton, 'Add');
bool _enabled(WidgetTester t) => t.widget<FilledButton>(_add).onPressed != null;

void main() {
  for (final (name, theme, dark) in [
    ('light', AppTheme.light(), false),
    ('dark', AppTheme.dark(), true),
  ]) {
    testWidgets('the field takes its colours from the theme ($name)',
        (tester) async {
      await _open(tester, theme: theme);
      final context = tester.element(find.byType(TextField));
      final decoration =
          tester.widget<TextField>(find.byType(TextField)).decoration!;
      final fill = decoration.fillColor!;
      expect(fill, context.subtleFill);
      if (dark) {
        expect(fill.computeLuminance(), lessThan(0.1),
            reason: 'not the white slab it was in dark mode');
      }

      final typed = tester.widget<EditableText>(find.byType(EditableText)).style.color!;
      expect(_contrast(typed, fill), greaterThanOrEqualTo(4.5),
          reason: 'what you type can be read on the field');
      expect(_contrast(decoration.hintStyle!.color!, fill),
          greaterThanOrEqualTo(4.5),
          reason: 'the hint was #BDBDBD, 1.9:1');
    });
  }

  testWidgets('names the prayer and starts ready to type', (tester) async {
    await _open(tester);
    expect(find.text('Add update'), findsOneWidget);
    expect(find.text('Healing for Mom'), findsOneWidget);
    expect(
        tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
        isTrue);
  });

  testWidgets('Add is off until there is something to add', (tester) async {
    await _open(tester);
    expect(_enabled(tester), isFalse);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(_enabled(tester), isFalse, reason: 'whitespace is not an update');
    await tester.enterText(find.byType(TextField), 'Surgery went well');
    await tester.pump();
    expect(_enabled(tester), isTrue);
  });

  testWidgets('returns the update, trimmed', (tester) async {
    final r = await _open(tester);
    await tester.enterText(find.byType(TextField), '  Surgery went well \n');
    await tester.pump();
    await tester.tap(_add);
    await tester.pumpAndSettle();
    expect(r.result(), 'Surgery went well');
  });

  testWidgets('cancelling returns nothing', (tester) async {
    final r = await _open(tester);
    await tester.enterText(find.byType(TextField), 'Not yet');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(r.done(), isTrue);
    expect(r.result(), isNull);
  });

  testWidgets('a mention chip inserts the name at the cursor', (tester) async {
    await _open(tester, collaborators: [_collaborator('anna')]);
    final field = find.byType(TextField);
    await tester.enterText(field, 'Thanks for praying');
    final controller = tester.widget<TextField>(field).controller!;
    controller.selection = const TextSelection.collapsed(offset: 7); // "Thanks |"
    await tester.tap(find.text('@anna'));
    await tester.pump();
    expect(controller.text, 'Thanks @anna for praying');
    expect(controller.selection, const TextSelection.collapsed(offset: 13));
    expect(_enabled(tester), isTrue);
  });

  testWidgets('no mention row without collaborators', (tester) async {
    await _open(tester);
    expect(find.byIcon(Icons.alternate_email), findsNothing);
  });
}
