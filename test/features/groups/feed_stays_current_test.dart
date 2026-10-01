// Anything that changes a group's content must refresh the feed.
//
// The feed is a second view of the same announcements and shared prayers. Four
// of the six mutations never invalidated it, so sharing a prayer, posting an
// announcement, editing one, or pinning one left the Feed tab showing the old
// state until someone pulled to refresh.
//
// It matters more than it did: the feed used to carry its own edit and delete
// buttons, and now it deliberately carries none — people act on a tab and then
// look at the feed, which is exactly the path that showed stale rows.
//
// Asserted as a rule over the source rather than per-mutation, because the
// failure is one of omission: the next person to add a mutation is the one
// this needs to catch, and a test enumerating today's six would not.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The API calls that change what the feed shows. Group-level edits
/// (`updateGroup`, `deleteGroup`) are deliberately absent: the feed lists
/// content, not the group's own name, and deleting the group leaves the screen.
const _contentMutations = {
  'addGroupPrayer',
  'removeGroupPrayer',
  'createAnnouncement',
  'updateAnnouncement',
  'deleteAnnouncement',
};

void main() {
  test('every group-content mutation invalidates the feed', () {
    final src = File(
      'lib/features/groups/presentation/screens/group_detail_screen.dart',
    ).readAsLinesSync()
        .map((l) => l.replaceFirst(RegExp(r'\s*//.*$'), ''))
        .join('\n');

    final lines = src.split('\n');
    final offenders = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final signature =
          RegExp(r'(?:Future<void>|void)\s+([_a-zA-Z]+)\(').firstMatch(lines[i]);
      if (signature == null) continue;

      // Take the function body by brace balance.
      var depth = 0;
      var started = false;
      var end = i;
      for (var k = i; k < lines.length; k++) {
        depth += '{'.allMatches(lines[k]).length;
        depth -= '}'.allMatches(lines[k]).length;
        if (lines[k].contains('{')) started = true;
        if (started && depth == 0) {
          end = k;
          break;
        }
      }
      final body = lines.sublist(i, end + 1).join('\n');

      final mutates =
          _contentMutations.any((m) => body.contains('api.$m('));
      if (!mutates) continue;

      if (!body.contains('groupFeedProvider')) {
        offenders.add(signature.group(1)!);
      }
    }

    expect(offenders, isEmpty,
        reason: 'these change what the feed shows but never invalidate it, so '
            'the Feed tab keeps the old rows: $offenders');
  });
}
