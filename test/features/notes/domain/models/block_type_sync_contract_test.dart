import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/note_block_model.dart' as sync;
import 'package:notify/features/notes/domain/models/block_type.dart' as domain;

/// The editor's [domain.BlockType] and the sync layer's [sync.BlockType] are
/// bridged by NAME (`NoteBlockConverter._domainBlockTypeToSync` matches on
/// `.name`, falling back to `paragraph`). A domain type with no same-named sync
/// type would silently degrade to a paragraph on every save/load round-trip —
/// i.e. quietly lose the user's block type.
void main() {
  test('every domain BlockType has a same-named sync BlockType', () {
    final syncNames = sync.BlockType.values.map((e) => e.name).toSet();
    final missing = domain.BlockType.values
        .map((e) => e.name)
        .where((name) => !syncNames.contains(name))
        .toList();

    expect(
      missing,
      isEmpty,
      reason: 'Domain BlockType(s) $missing have no sync counterpart and would '
          'degrade to paragraph on persistence. Add them to the sync '
          'BlockType enum in core/sync/models/note_block_model.dart.',
    );
  });

  test('domain BlockType survives a name-based round-trip to sync and back',
      () {
    for (final d in domain.BlockType.values) {
      final s = sync.BlockType.fromDbValue(d.name);
      final back = domain.BlockType.values.firstWhere((x) => x.name == s.name);
      expect(back, d, reason: 'round-trip failed for ${d.name}');
    }
  });
}
