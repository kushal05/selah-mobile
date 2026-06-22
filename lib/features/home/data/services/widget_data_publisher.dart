import 'dart:async';
import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../../../../core/sync/models/note_block_model.dart';
import '../../../../core/sync/models/note_model.dart';
import '../../../../core/sync/models/prayer_model.dart';
import '../../../../core/sync/repositories/note_block_repository.dart';
import '../../../../core/sync/repositories/note_repository.dart';
import '../../../../core/sync/repositories/prayer_repository.dart';
import '../../../../core/sync/utils/sync_logger.dart';
import '../../../bible/domain/models/bible_reference.dart';
import '../../../prayers/domain/services/pray_today_service.dart';

/// Computes the data that the native home-screen widgets render and pushes it
/// to the shared storage the `home_widget` plugin manages (Android: a private
/// SharedPreferences file per `applicationId`; iOS: the App Group's
/// `UserDefaults`).
///
/// Writes three keys:
///  - [keyTodayPrayers]: today's due prayers `[{id,title}]` → PrayTodayWidget.
///  - [keyNotesIndex]:  recent notes `[{id,title,preview}]` → NotePin config
///    picker + the pinned-note widget's freshness lookup.
///  - [keyPrayersIndex]: recent prayers `[{id,title,content}]` → PrayerPin
///    config picker + the pinned-prayer widget's freshness lookup.
///
/// Best-effort: every failure is swallowed and logged. Widget refresh must
/// never block auth, sync, or the UI.
class WidgetDataPublisher {
  WidgetDataPublisher({
    required NoteRepository noteRepo,
    required NoteBlockRepository noteBlockRepo,
    required PrayerRepository prayerRepo,
    required PrayTodayService prayTodayService,
  })  : _noteRepo = noteRepo,
        _noteBlockRepo = noteBlockRepo,
        _prayerRepo = prayerRepo,
        _prayTodayService = prayTodayService;

  final NoteRepository _noteRepo;
  final NoteBlockRepository _noteBlockRepo;
  final PrayerRepository _prayerRepo;
  final PrayTodayService _prayTodayService;

  static const keyTodayPrayers = 'today_prayers';
  static const keyNotesIndex = 'notes_index';
  static const keyPrayersIndex = 'prayers_index';
  static const keyUpdatedAt = 'widget_updated_at';

  /// True while logged out — tells the pinned widgets to blank their snapshot
  /// instead of showing the previous user's note/prayer.
  static const keySignedOut = 'widget_signed_out';

  /// Cap on how many notes/prayers are published to the picker index. Keeps the
  /// shared-prefs blob small; older items simply aren't offered by the picker
  /// (a pinned widget keeps the snapshot captured at config time).
  static const _indexLimit = 50;
  static const _previewMaxLen = 320;

  /// Android providers whose rendering depends on published data. Action
  /// widgets (create-note/prayer, songs) are static and never need refreshing.
  static const _androidDisplayProviders = <String>[
    'com.example.notify.widgets.NotePinWidgetProvider',
    'com.example.notify.widgets.PrayerPinWidgetProvider',
    'com.example.notify.widgets.PrayTodayWidgetProvider',
  ];

  /// iOS WidgetKit kinds, index-aligned with [_androidDisplayProviders].
  static const _iosDisplayKinds = <String>[
    'NotePinWidget',
    'PrayerPinWidget',
    'PrayTodayWidget',
  ];

  /// Recompute every payload and push it to the widgets. On logout, clears the
  /// widgets so they don't keep showing the previous user's data.
  Future<void> publishAll({required String userId}) async {
    if (userId.isEmpty || userId == 'default-user-id') {
      await _clear();
      return;
    }
    try {
      final results = await Future.wait([
        _prayTodayService.todaysPrayers(userId),
        _noteRepo.getRecentNotes(userId, limit: _indexLimit),
        _prayerRepo.getAllPrayers(userId),
      ]);
      final todays = results[0] as List<PrayerModel>;
      final notes = results[1] as List<NoteModel>;
      final prayers = results[2] as List<PrayerModel>;

      final todayJson = jsonEncode([
        for (final p in todays) {'id': p.id, 'title': p.title},
      ]);
      final notesJson = await _buildNotesIndex(notes);
      final prayersJson = jsonEncode([
        for (final p in prayers.take(_indexLimit))
          {
            'id': p.id,
            'title': p.title,
            'content': _truncate(p.content, _previewMaxLen),
          },
      ]);

      await Future.wait([
        HomeWidget.saveWidgetData<String>(keyTodayPrayers, todayJson),
        HomeWidget.saveWidgetData<String>(keyNotesIndex, notesJson),
        HomeWidget.saveWidgetData<String>(keyPrayersIndex, prayersJson),
        HomeWidget.saveWidgetData<int>(
          keyUpdatedAt,
          DateTime.now().millisecondsSinceEpoch,
        ),
        HomeWidget.saveWidgetData<bool>(keySignedOut, false),
      ]);

      SyncLogger.info(
        'Widget publish: today=${todays.length} notes=${notes.length} '
        'prayers=${prayers.length}',
      );

      await _updateWidgets();
    } catch (e, st) {
      SyncLogger.warning('Widget publish failed: $e\n$st');
    }
  }

  /// Blanks all published widget data (logout). Writes empty indexes and sets
  /// the signed-out flag so the pinned widgets drop their snapshot.
  Future<void> _clear() async {
    try {
      await Future.wait([
        HomeWidget.saveWidgetData<String>(keyTodayPrayers, '[]'),
        HomeWidget.saveWidgetData<String>(keyNotesIndex, '[]'),
        HomeWidget.saveWidgetData<String>(keyPrayersIndex, '[]'),
        HomeWidget.saveWidgetData<bool>(keySignedOut, true),
      ]);
      await _updateWidgets();
    } catch (e, st) {
      SyncLogger.warning('Widget clear failed: $e\n$st');
    }
  }

  Future<void> _updateWidgets() async {
    for (var i = 0; i < _androidDisplayProviders.length; i++) {
      try {
        await HomeWidget.updateWidget(
          qualifiedAndroidName: _androidDisplayProviders[i],
          iOSName: _iosDisplayKinds[i],
        );
      } catch (_) {
        // Plugin unavailable (e.g. unit tests) or widget not added — ignore.
      }
    }
  }

  /// First non-empty text block of the note, mirroring `_getNotePreview` in
  /// `notes_home_screen.dart`. Reads the cached [NoteModel.documentJson]
  /// snapshot so no block join is needed.
  /// Builds the recent-notes index JSON. Each note's preview comes from its
  /// documentJson snapshot, falling back to the authoritative blocks table when
  /// the snapshot is absent (older notes never re-saved since the snapshot
  /// field was added would otherwise show no content).
  Future<String> _buildNotesIndex(List<NoteModel> notes) async {
    final entries = await Future.wait(notes.map((note) async {
      var preview = _previewFromDocJson(note.documentJson);
      // Fall back to the blocks table whenever the snapshot yields nothing —
      // it may be absent, corrupt, or an incompatible older format. With the
      // snapshot decoded correctly this is a no-op for the common case.
      if (preview.isEmpty) {
        try {
          final blocks = await _noteBlockRepo.getBlocksForNote(note.id);
          preview = _previewFromBlocks(blocks);
        } catch (_) {
          // Best-effort — leave the preview empty on failure.
        }
      }
      return <String, dynamic>{
        'id': note.id,
        'title': note.title,
        'preview': preview,
      };
    }));
    return jsonEncode(entries);
  }

  /// Preview from the documentJson snapshot. The snapshot is a list of
  /// NoteBlockModel JSON (NOT EditorBlock JSON — block text lives in
  /// `content['text']`), so decode it exactly like the in-app reader does and
  /// reuse the shared block-preview rule.
  String _previewFromDocJson(String? doc) {
    if (doc == null || doc.isEmpty) return '';
    try {
      final list = jsonDecode(doc) as List<dynamic>;
      final blocks = list
          .map((e) => NoteBlockModel.fromJson(e as Map<String, dynamic>))
          .toList();
      return _previewFromBlocks(blocks);
    } catch (_) {
      // Corrupted/incompatible snapshot — caller falls back to the table.
      return '';
    }
  }

  /// First non-empty main-section block's text (or a bible reference for
  /// reference blocks). Block text lives in `content['text']`.
  String _previewFromBlocks(List<NoteBlockModel> blocks) {
    final main = blocks
        .where((b) => !b.isDeleted && b.section == 'main')
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    // Concatenate the leading main-section blocks (one per line) up to the cap,
    // so the widget shows more than just the first line.
    final parts = <String>[];
    var total = 0;
    for (final block in main) {
      final raw = (block.content['text'] as String?)?.trim() ?? '';
      if (raw.isEmpty) continue;
      final String text;
      if (block.blockType.name == 'bibleReference') {
        final label = _bibleRefLabel(raw);
        if (label == null) continue;
        text = label;
      } else {
        text = raw;
      }
      parts.add(text);
      total += text.length + 1;
      if (total >= _previewMaxLen) break;
    }
    if (parts.isEmpty) return '';
    return _truncate(parts.join('\n'), _previewMaxLen);
  }

  /// Formats a bible-reference block's content JSON as "Book chapter:verse"
  /// (drops the trailing translation suffix for a compact widget label).
  String? _bibleRefLabel(String content) {
    try {
      final ref = BibleReference.fromJson(
        jsonDecode(content) as Map<String, dynamic>,
      );
      return ref.displayReference.replaceAll(RegExp(r'\s*\([^)]*\)\s*$'), '');
    } catch (_) {
      return null;
    }
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max).trimRight()}…';
}
