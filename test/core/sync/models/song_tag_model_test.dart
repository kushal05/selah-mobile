// SongTagModel.weight: what a pulled payload or a stored row may hold, and
// what it is read as. A wrong read here resets a weight to 2 without a trace.

import 'package:flutter_test/flutter_test.dart';
import 'package:notify/core/sync/models/song_tag_model.dart';

void main() {
  test('weights are held to 1-3, numbers of any kind count', () {
    expect(SongTagModel.clampWeight(3), 3);
    expect(SongTagModel.clampWeight(3.0), 3, reason: 'a JSON double is still 3');
    expect(SongTagModel.clampWeight(0), 1);
    expect(SongTagModel.clampWeight(9), 3);
    expect(SongTagModel.clampWeight(null), SongTagModel.defaultWeight);
    expect(SongTagModel.clampWeight('3'), SongTagModel.defaultWeight);
    expect(SongTagModel.clampWeight(double.nan), SongTagModel.defaultWeight,
        reason: 'round() throws on NaN; a throw would fail the sync apply');
    expect(SongTagModel.clampWeight(double.infinity), SongTagModel.defaultWeight);
  });

  test('a payload round-trips its weight and always carries trashedAt', () {
    final m = SongTagModel.create(id: 'l', songId: 's', tagId: 't', userId: 'u');
    final json = m.toJson();
    expect(json['weight'], 2);
    expect(json.containsKey('trashedAt'), isTrue);
    expect(SongTagModel.fromJson({...json, 'weight': 1}).weight, 1);
    expect(SongTagModel.fromJson({...json}..remove('weight')).weight, 2,
        reason: 'a payload from a build without weights');
  });

  test('every copy keeps the weight', () {
    final m = SongTagModel.fromJson({
      ...SongTagModel.create(id: 'l', songId: 's', tagId: 't', userId: 'u').toJson(),
      'weight': 3,
    });
    expect([
      m.softDelete().weight,
      m.moveToTrash().weight,
      m.restoreFromTrash().weight,
      m.softDelete().revive().weight,
    ], everyElement(3));
  });
}
