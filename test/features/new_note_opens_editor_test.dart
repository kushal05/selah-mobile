// A note you just created opens in the editor, not in a preview of itself.
//
// The template picker created the note and then pushed `/notes/{id}`, the
// read-only detail screen — a screen showing a note that contains nothing but
// the template's empty scaffolding, with one more tap before you could type.
//
// The route matters as much as the destination: this picker is reachable from
// the Home tab's quick actions as well as from the notes list, so the push has
// to behave the same either way. That is why it goes through the router rather
// than the nearest Navigator, which would differ depending on which tab the
// sheet was opened from.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:notify/core/navigation/routes.dart';
import 'package:notify/features/notes/presentation/screens/note_detail_screen.dart';
import 'package:notify/features/notes/presentation/screens/note_editor_screen.dart';

// Mutation testing found two links of this chain unpinned: the picker could go
// back to pushing `/notes/{id}` and the app's own router could lose the nested
// `edit` route, and all 712 tests still passed. The test below builds a
// miniature router, which proves the shape resolves but says nothing about what
// the app registers or what the picker asks for. The real router pulls in auth,
// preferences, FCM and four watchers, so it cannot be constructed here — those
// two links are pinned at the source instead, which is enough to catch a revert.

const _picker =
    'lib/features/notes/presentation/widgets/note_template_picker_sheet.dart';
const _router = 'lib/core/navigation/app_router.dart';

void main() {
  test('the picker asks for the editor, not the detail view', () {
    final src = File(_picker).readAsStringSync();

    expect(src.contains('Routes.noteEditFor('), isTrue,
        reason: 'the picker must push the edit route');
    expect(RegExp(r"push\(\s*'/notes/\$\{note\.id\}'").hasMatch(src), isFalse,
        reason: 'pushing the detail path is the behaviour this change removed');
  });

  test("the app's router registers the nested edit route", () {
    final src = File(_router).readAsStringSync();

    // The child route under `/notes/:noteId`, and the screen it builds. Both
    // halves matter: a route that resolves to the detail screen would satisfy
    // the miniature-router test below just as well.
    final edit = src.indexOf("path: 'edit'");
    expect(edit, isNot(-1), reason: 'the nested edit route is gone');
    final builder = src.substring(edit, edit + 400);
    expect(builder.contains('NoteEditorScreen('), isTrue,
        reason: "the edit route must build the editor");
    expect(builder.contains("state.pathParameters['noteId']"), isTrue,
        reason: 'the editor needs the id from the parent segment');
  });

  test('the edit route is built from the note id', () {
    expect(Routes.noteEditFor('abc-123'), '/notes/abc-123/edit');
    // The pattern the router registers, for anything matching on it.
    expect(Routes.noteEdit, '/notes/:noteId/edit');
  });

  testWidgets('/notes/{id}/edit resolves to the editor, not the detail view', (
    tester,
  ) async {
    // A miniature of the real tree: the detail route with the editor nested
    // under it, which is the arrangement that has to keep `:noteId` from
    // swallowing the `edit` segment.
    final router = GoRouter(
      initialLocation: '/notes/abc-123/edit',
      routes: [
        GoRoute(
          path: '/notes/:noteId',
          builder: (context, state) =>
              NoteDetailScreen(noteId: state.pathParameters['noteId']!),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (context, state) =>
                  NoteEditorScreen(noteId: state.pathParameters['noteId']!),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    // Resolving the location is the assertion; building the screen would need
    // the whole provider graph and would be testing something else.
    final match = router.configuration.findMatch(
      Uri.parse('/notes/abc-123/edit'),
    );

    expect(match.uri.path, '/notes/abc-123/edit');
    expect(match.pathParameters['noteId'], 'abc-123',
        reason: 'the id must survive the nested segment');
    expect(match.routes.last, isA<GoRoute>());
    expect((match.routes.last as GoRoute).path, 'edit',
        reason: 'the last matched route must be the editor, not :noteId');
  });
}
