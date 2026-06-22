import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/services/chord_transposition.dart';
import '../../../../core/sync/models/song_model.dart';
import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Screen for adding or editing a song
/// Provides form fields for title, lyrics, structured chord lines, scale, language, and tags
class AddSongScreen extends ConsumerStatefulWidget {
  final String? songId;

  const AddSongScreen({super.key, this.songId});

  @override
  ConsumerState<AddSongScreen> createState() => _AddSongScreenState();
}

class _AddSongScreenState extends ConsumerState<AddSongScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _lyricsController = TextEditingController();
  final _chordsController = TextEditingController();
  final _bookController = TextEditingController();
  final _notesController = TextEditingController();
  final _tagController = TextEditingController();
  final _tagInputFocusNode = FocusNode();
  final _scrollController = ScrollController();

  late TabController _tabController;
  String _language = 'English';
  String _scale = '';
  String? _folderId;
  final List<String> _tagIds = []; // global tag IDs
  final Map<String, String> _tagNames = {}; // tagId → display name cache

  // Structured chord lines: one entry per lyric line that has chords
  final List<ChordLine> _chordLines = [];

  bool _isAddingTag = false;
  bool _isLoading = false;
  bool _isEditMode = false;
  bool _isKeyboardVisible = false;

  // Snapshot of original values for dirty-checking in edit mode
  String _origTitle = '';
  String _origLyrics = '';
  String _origChords = '';
  String _origBook = '';
  String _origNotes = '';
  String _origLanguage = 'English';
  String _origScale = '';
  String? _origFolderId;
  List<String> _origTags = [];
  List<ChordLine> _origChordLines = [];

  final List<String> _languages = [
    'English',
    'Telugu',
    'Hindi',
    'Malayalam',
    'Tamil',
    'Spanish',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    // Prune out-of-bounds chord lines when switching to the Chords tab
    _tabController.addListener(_onTabChanged);
    _isEditMode = widget.songId != null;
    if (_isEditMode) {
      _loadSong();
    }
  }

  void _onTabChanged() {
    if (_tabController.index == 1) {
      // Switching to Chords tab — prune chord lines whose lineIndex
      // is now out of bounds because lyrics were edited, and always
      // rebuild so the latest lyrics are reflected.
      final lineCount = _lyricsController.text.split('\n').length;
      setState(() {
        _chordLines.removeWhere((c) => c.lineIndex >= lineCount);
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = View.of(context).viewInsets.bottom;
    final newKeyboardVisible = bottomInset > 0;
    if (_isKeyboardVisible != newKeyboardVisible) {
      setState(() => _isKeyboardVisible = newKeyboardVisible);
    }
  }

  Future<void> _loadSong() async {
    setState(() => _isLoading = true);
    try {
      final repository = ref.read(songRepositoryProvider);
      final songTagRepo = ref.read(songTagRepositoryProvider);
      final tagRepo = ref.read(tagRepositoryProvider);
      final song = await repository.getSongById(widget.songId!);
      if (song != null && mounted) {
        // Load tag IDs from junction table and resolve names
        final ids = await songTagRepo.getTagIdsForSong(song.id);
        final names = <String, String>{};
        for (final id in ids) {
          final tag = await tagRepo.getTagById(id);
          if (tag != null) names[id] = tag.name;
        }

        if (!mounted) return;
        setState(() {
          _titleController.text = song.title;
          _lyricsController.text = song.lyrics;
          _chordsController.text = song.chords;
          _bookController.text = song.book ?? '';
          _notesController.text = song.notes;
          _language = song.language;
          _scale = song.scale;
          _folderId = song.folderId;
          _tagIds.addAll(ids);
          _tagNames.addAll(names);
          _chordLines.addAll(song.chordLinesList);

          // Snapshot originals for dirty-checking
          _origTitle = song.title;
          _origLyrics = song.lyrics;
          _origChords = song.chords;
          _origBook = song.book ?? '';
          _origNotes = song.notes;
          _origLanguage = song.language;
          _origScale = song.scale;
          _origFolderId = song.folderId;
          _origTags = List.of(ids);
          _origChordLines = List.of(song.chordLinesList);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.removeListener(_onTabChanged);
    _titleController.dispose();
    _lyricsController.dispose();
    _chordsController.dispose();
    _bookController.dispose();
    _notesController.dispose();
    _tagController.dispose();
    _tagInputFocusNode.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    ref.watch(songFoldersStreamProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _handleClose(context),
        ),
        title: Text(_isEditMode ? 'Edit Song' : 'New Song'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _handleSave,
            style: TextButton.styleFrom(foregroundColor: AppTheme.orange),
            child: const Text('Save'),
          ),
        ],
      ),
      body: _isLoading
          ? const SafeArea(child: SingleChildScrollView(child: FormSkeleton()))
          : SafeArea(
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: TabBar(
                        controller: _tabController,
                        labelColor: AppTheme.orange,
                        unselectedLabelColor: Colors.grey.shade600,
                        indicatorColor: AppTheme.orange,
                        tabs: const [
                          Tab(text: 'Lyrics'),
                          Tab(text: 'Chords'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildScrollableContent(isLyricsTab: true),
                          _buildScrollableContent(isLyricsTab: false),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildScrollableContent({required bool isLyricsTab}) {
    return SingleChildScrollView(
      controller: isLyricsTab ? _scrollController : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTitleField(),
          const SizedBox(height: 16),
          _buildMetadataRow(),
          const SizedBox(height: 16),
          if (isLyricsTab) _buildLyricsField() else _buildChordsField(),
          if (isLyricsTab) ...[
            const SizedBox(height: 16),
            _buildNotesField(),
          ],
          SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        ],
      ),
    );
  }

  Widget _buildNotesField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sticky_note_2_outlined,
                size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              'Notes',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(
            hintText:
                'Notes or references (author, source URL, performance notes...)',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppTheme.orange.withValues(alpha: 0.3),
                width: 1.0,
              ),
            ),
            hintStyle: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
              height: 1.5,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          maxLines: null,
          minLines: 3,
          style: const TextStyle(fontSize: 14, height: 1.5),
          textCapitalization: TextCapitalization.sentences,
          textAlignVertical: TextAlignVertical.top,
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        hintText: 'Song title',
        prefixIcon: Icon(Icons.music_note, color: Colors.grey.shade400),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppTheme.orange.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        hintStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade400,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Please enter a song title';
        }
        return null;
      },
    );
  }

  Widget _buildMetadataRow() {


    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Songbook chip (folder-based)
          _buildMetadataChip(
            icon: Icons.library_books_outlined,
            label: _selectedFolderName() ?? 'Songbook',
            isPlaceholder: _folderId == null,
            onTap: _showFolderPicker,
          ),
          const SizedBox(width: 8),

          // Scale/Key chip
          _buildMetadataChip(
            icon: Icons.piano,
            label: _scale.isEmpty ? 'Key' : 'Key: $_scale',
            isPlaceholder: _scale.isEmpty,
            onTap: _showScalePicker,
          ),
          const SizedBox(width: 8),

          // Language chip
          _buildMetadataChip(
            icon: Icons.language,
            label: _language,
            onTap: _showLanguagePicker,
          ),
          const SizedBox(width: 8),

          // Tags
          ..._tagIds.map((tagId) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _buildTagChip(tagId),
              )),

          // Add tag chip or input
          if (_isAddingTag)
            SizedBox(
              width: 150,
              child: TextField(
                controller: _tagController,
                focusNode: _tagInputFocusNode,
                decoration: InputDecoration(
                  hintText: 'Tag name...',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(color: AppTheme.orange),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, size: 18),
                    onPressed: () => _submitTag(_tagController.text),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: _submitTag,
              ),
            )
          else
            _buildAddTagChip(),
        ],
      ),
    );
  }

  Widget _buildMetadataChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isPlaceholder = false,
  }) {


    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isPlaceholder
                ? Colors.grey.shade100
                : AppTheme.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isPlaceholder
                  ? Colors.grey.shade300
                  : AppTheme.orange.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 16,
                  color: isPlaceholder
                      ? Colors.grey.shade500
                      : AppTheme.orange),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isPlaceholder
                      ? Colors.grey.shade500
                      : AppTheme.orange,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down,
                  size: 16,
                  color: isPlaceholder
                      ? Colors.grey.shade500
                      : AppTheme.orange),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagChip(String tagId) {

    final displayName = _tagNames[tagId] ?? tagId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.orange,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () {
              FocusScope.of(context).unfocus();
              setState(() {
                _tagIds.remove(tagId);
                _tagNames.remove(tagId);
              });
            },
            child: Icon(Icons.close,
                size: 16, color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildAddTagChip() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _isAddingTag = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tagInputFocusNode.requestFocus();
          });
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                'Add tag',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLyricsField() {
    return TextFormField(
      controller: _lyricsController,
      decoration: InputDecoration(
        hintText:
            'Verse 1:\nAmazing grace, how sweet the sound\nThat saved a wretch like me...',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: AppTheme.orange.withValues(alpha: 0.3),
            width: 1.0,
          ),
        ),
        hintStyle: TextStyle(
          fontSize: 15,
          color: Colors.grey.shade400,
          height: 1.6,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      maxLines: null,
      minLines: 15,
      style: const TextStyle(fontSize: 15, height: 1.6),
      textCapitalization: TextCapitalization.sentences,
      textAlignVertical: TextAlignVertical.top,
    );
  }

  Widget _buildChordsField() {

    final lyricLines = _lyricsController.text.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppTheme.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Enter chords for each lyric line. Use spaces to separate chords (e.g. "G  D  Em  C").',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Structured chord lines editor: one row per lyric line
        if (lyricLines.isNotEmpty && lyricLines.any((l) => l.trim().isNotEmpty))
          ...lyricLines.asMap().entries.map((entry) {
            final idx = entry.key;
            final lyricLine = entry.value;
            if (lyricLine.trim().isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade400)),
              );
            }
            final existing = _chordLines.where((c) => c.lineIndex == idx);
            final currentChords =
                existing.isNotEmpty ? existing.first.rawChords : '';

            return Padding(
              key: ValueKey('chord_line_${idx}_${lyricLine.hashCode}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chord input for this line
                  TextFormField(
                    key: ValueKey('chord_input_${idx}_${lyricLine.hashCode}'),
                    initialValue: currentChords,
                    decoration: InputDecoration(
                      hintText: 'Chords...',
                      isDense: true,
                      filled: true,
                      fillColor: AppTheme.orange.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                        fontFamily: 'monospace',
                      ),
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: AppTheme.orange,
                    ),
                    textCapitalization: TextCapitalization.words,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.deny(RegExp(r'\.')),
                    ],
                    onChanged: (value) => _updateChordLine(idx, value),
                  ),
                  // Lyric line preview
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 12, top: 2, bottom: 4),
                    child: Text(
                      lyricLine,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }),

        if (lyricLines.isEmpty || !lyricLines.any((l) => l.trim().isNotEmpty))
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Add lyrics first, then you can assign chords to each line.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),

        // Legacy inline chord field (for backward compatibility)
        Text(
          'Or use inline notation',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _chordsController,
          decoration: InputDecoration(
            hintText:
                '[G]Amazing [C]grace, how [G]sweet the sound\n[G]That saved a [D]wretch like [G]me...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: AppTheme.orange.withValues(alpha: 0.3),
                width: 1.0,
              ),
            ),
            hintStyle: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
              height: 1.6,
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
          maxLines: null,
          minLines: 8,
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            fontFamily: 'monospace',
          ),
          textAlignVertical: TextAlignVertical.top,
        ),
      ],
    );
  }

  void _updateChordLine(int lineIndex, String rawChords) {
    setState(() {
      _chordLines.removeWhere((c) => c.lineIndex == lineIndex);
      if (rawChords.trim().isNotEmpty) {
        _chordLines.add(
            ChordLine(lineIndex: lineIndex, rawChords: rawChords.trim()));
      }
    });
  }

  void _showScalePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Key',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // No key option
                    ListTile(
                      leading: Icon(
                        _scale.isEmpty
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: _scale.isEmpty
                            ? AppTheme.orange
                            : Colors.grey,
                      ),
                      title: const Text('No key set'),
                      onTap: () {
                        setState(() => _scale = '');
                        Navigator.pop(context);
                      },
                    ),
                    // Major keys header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Major',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          )),
                    ),
                    ...ChordTransposer.majorKeys.map((key) => ListTile(
                          leading: Icon(
                            _scale == key
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: _scale == key
                                ? AppTheme.orange
                                : Colors.grey,
                          ),
                          title: Text(key),
                          dense: true,
                          onTap: () {
                            setState(() => _scale = key);
                            Navigator.pop(context);
                          },
                        )),
                    // Minor keys header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Minor',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          )),
                    ),
                    ...ChordTransposer.minorKeys.map((key) => ListTile(
                          leading: Icon(
                            _scale == key
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: _scale == key
                                ? AppTheme.orange
                                : Colors.grey,
                          ),
                          title: Text(key),
                          dense: true,
                          onTap: () {
                            setState(() => _scale = key);
                            Navigator.pop(context);
                          },
                        )),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Language',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ..._languages.map((lang) => ListTile(
                  leading: Icon(
                    lang == _language
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: lang == _language
                        ? AppTheme.orange
                        : Colors.grey,
                  ),
                  title: Text(lang),
                  onTap: () {
                    setState(() => _language = lang);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String? _selectedFolderName() {
    if (_folderId == null) return null;
    final folders = ref.read(songFoldersStreamProvider).valueOrNull ?? [];
    for (final folder in folders) {
      if (folder.id == _folderId) return folder.name;
    }
    return null;
  }

  void _showFolderPicker() {
    final folders = ref.read(songFoldersStreamProvider).valueOrNull ?? [];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Songbook',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                _folderId == null ? Icons.check_circle : Icons.circle_outlined,
                color:
                    _folderId == null ? AppTheme.orange : Colors.grey,
              ),
              title: const Text('No songbook'),
              onTap: () {
                setState(() => _folderId = null);
                Navigator.pop(context);
              },
            ),
            ...folders.map((folder) => ListTile(
                  leading: Icon(
                    _folderId == folder.id
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    color: _folderId == folder.id
                        ? AppTheme.orange
                        : Colors.grey,
                  ),
                  title: Text(folder.name),
                  onTap: () {
                    setState(() => _folderId = folder.id);
                    Navigator.pop(context);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }



  Future<void> _submitTag(String tag) async {
    final trimmed = tag.trim();
    FocusScope.of(context).unfocus();
    if (trimmed.isEmpty) {
      setState(() {
        _tagController.clear();
        _isAddingTag = false;
      });
      return;
    }

    // Check if already added (by name)
    if (_tagNames.values.contains(trimmed)) {
      setState(() {
        _tagController.clear();
        _isAddingTag = false;
      });
      return;
    }

    final tagRepo = ref.read(tagRepositoryProvider);
    final userId = ref.read(currentUserIdProvider);
    final tagModel = await tagRepo.getOrCreateTag(trimmed, userId);

    if (!mounted) return;
    setState(() {
      if (!_tagIds.contains(tagModel.id)) {
        _tagIds.add(tagModel.id);
        _tagNames[tagModel.id] = tagModel.name;
      }
      _tagController.clear();
      _isAddingTag = false;
    });
  }

  bool get _hasUnsavedContent {
    if (_isEditMode) {
      // In edit mode, compare current state against the loaded snapshot
      return _titleController.text != _origTitle ||
          _lyricsController.text != _origLyrics ||
          _chordsController.text != _origChords ||
          _bookController.text != _origBook ||
          _notesController.text != _origNotes ||
          _language != _origLanguage ||
          _scale != _origScale ||
          _folderId != _origFolderId ||
          !_listEquals(_tagIds, _origTags) ||
          !_listEquals(_chordLines, _origChordLines);
    }
    // In create mode, check for any content at all
    return _titleController.text.isNotEmpty ||
        _lyricsController.text.isNotEmpty ||
        _chordsController.text.isNotEmpty ||
        _chordLines.isNotEmpty ||
        _tagIds.isNotEmpty ||
        _scale.isNotEmpty ||
        _bookController.text.isNotEmpty ||
        _notesController.text.isNotEmpty;
  }

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleClose(BuildContext outerContext) {
    if (_hasUnsavedContent) {
      showDialog(
        context: outerContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
              'You have unsaved changes. Are you sure you want to discard them?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                outerContext.pop();
              },
              child: const Text('Discard'),
            ),
          ],
        ),
      );
    } else {
      outerContext.pop();
    }
  }

  Future<void> _handleSave() async {
    if (_formKey.currentState?.validate() ?? false) {
      FocusScope.of(context).unfocus();
      setState(() => _isLoading = true);
      try {
        final repository = ref.read(songRepositoryProvider);
        final songTagRepo = ref.read(songTagRepositoryProvider);
        final userId = ref.read(currentUserIdProvider);

        String songId;
        if (_isEditMode) {
          songId = widget.songId!;
          final bookText = _bookController.text.trim();
          await repository.updateSong(
            id: songId,
            title: _titleController.text.trim(),
            folderId: _folderId,
            clearFolderId: _folderId == null,
            lyrics: _lyricsController.text,
            chords: _chordsController.text,
            scale: _scale,
            chordLines: _chordLines,
            language: _language,
            book: bookText.isNotEmpty ? bookText : null,
            clearBook: bookText.isEmpty,
            notes: _notesController.text,
          );
        } else {
          final song = await repository.createSong(
            userId: userId,
            title: _titleController.text.trim(),
            folderId: _folderId,
            lyrics: _lyricsController.text,
            chords: _chordsController.text,
            scale: _scale,
            chordLines: _chordLines,
            language: _language,
            book: _bookController.text.trim().isNotEmpty
                ? _bookController.text.trim()
                : null,
            notes: _notesController.text,
          );
          songId = song.id;
        }

        // Save tags via junction table
        await songTagRepo.setTagsForSong(songId, _tagIds, userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isEditMode
                  ? 'Song updated successfully'
                  : 'Song saved successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving song: $e'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}


