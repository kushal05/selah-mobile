// The link picker became a bottom sheet, and one of its two call sites was
// left on showDialog — where a sheet body has no Dialog or Material ancestor
// and throws at render. These pin both halves: it renders, and it returns
// what was chosen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notify/core/theme/app_theme.dart';
import 'package:notify/l10n/l10n.dart';
import 'package:notify/shared/widgets/dialogs/link_picker_dialog.dart';

class _Item {
  final String id;
  final String label;
  const _Item(this.id, this.label);
}

Future<List<String>?> _openPicker(
  WidgetTester tester, {
  List<_Item> items = const [_Item('a', 'Isaiah 41:10'), _Item('b', 'Psalm 23')],
  Set<String> linked = const {},
}) async {
  List<String>? result;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await LinkPicker.show<_Item>(
                context,
                title: 'Link promises',
                items: items,
                alreadyLinkedIds: linked,
                getId: (i) => i.id,
                getLabel: (i) => i.label,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('renders as a sheet with the available items', (tester) async {
    await _openPicker(tester);

    expect(find.text('Link promises'), findsOneWidget);
    expect(find.text('Isaiah 41:10'), findsOneWidget);
    expect(find.text('Psalm 23'), findsOneWidget);
    // Nothing chosen yet, so the primary action prompts rather than acts.
    expect(find.text('Select items to link'), findsOneWidget);
  });

  testWidgets('hides items that are already linked', (tester) async {
    await _openPicker(tester, linked: {'a'});

    expect(find.text('Isaiah 41:10'), findsNothing);
    expect(find.text('Psalm 23'), findsOneWidget);
  });

  testWidgets('returns the selected ids', (tester) async {
    List<String>? captured;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = await LinkPicker.show<_Item>(
                  context,
                  title: 'Link promises',
                  items: const [_Item('a', 'Isaiah 41:10')],
                  alreadyLinkedIds: const {},
                  getId: (i) => i.id,
                  getLabel: (i) => i.label,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Isaiah 41:10'));
    await tester.pumpAndSettle();
    expect(find.text('Link 1 item'), findsOneWidget);

    await tester.tap(find.text('Link 1 item'));
    await tester.pumpAndSettle();

    expect(captured, ['a']);
  });
}
