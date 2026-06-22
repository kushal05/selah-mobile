import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/memory_verse.dart';

/// Persists [MemoryVerse]s as JSON in SharedPreferences. Single-device
/// only — when the backend can sync this, promote to a Drift table.
class MemoryVerseRepository {
  static const _key = 'memory_verses_v1';

  final SharedPreferences _prefs;
  final StreamController<List<MemoryVerse>> _controller =
      StreamController<List<MemoryVerse>>.broadcast();

  MemoryVerseRepository(this._prefs);

  Stream<List<MemoryVerse>> watchAll() async* {
    yield await getAll();
    yield* _controller.stream;
  }

  Future<List<MemoryVerse>> getAll() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => MemoryVerse.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Corrupt blob — drop it rather than crash the screen.
      await _prefs.remove(_key);
      return const [];
    }
  }

  Future<List<MemoryVerse>> getDue() async {
    final all = await getAll();
    final now = DateTime.now().millisecondsSinceEpoch;
    return all.where((v) => v.dueAt <= now).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  }

  Future<void> upsert(MemoryVerse verse) async {
    final all = await getAll();
    final idx = all.indexWhere((v) => v.id == verse.id);
    if (idx == -1) {
      all.add(verse);
    } else {
      all[idx] = verse;
    }
    await _save(all);
  }

  Future<void> remove(String id) async {
    final all = await getAll();
    all.removeWhere((v) => v.id == id);
    await _save(all);
  }

  Future<void> _save(List<MemoryVerse> all) async {
    final json = jsonEncode(all.map((v) => v.toJson()).toList());
    await _prefs.setString(_key, json);
    _controller.add(all);
  }

  void dispose() {
    _controller.close();
  }
}
