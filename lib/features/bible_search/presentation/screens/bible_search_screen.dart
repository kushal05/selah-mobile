import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/navigation/routes.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../bible/presentation/providers/bible_providers.dart';
import '../../domain/models/bible_search_result.dart';
import '../providers/bible_search_providers.dart';
import '../widgets/bible_search_filters.dart';
import '../widgets/bible_verse_result_card.dart';
import '../../../../shared/widgets/skeletons/skeletons.dart';

/// Dedicated Bible verse search screen.
///
/// - Completely separate from global search and song search
/// - Uses SQLite FTS5 for fast offline full-text search
/// - Search triggers on button press or keyboard submit, minimum 2 characters
/// - Supports testament / book / translation filters
/// - Results show highlighted matched terms
///
/// When opened with `selectMode: true`, tapping a verse pops with
/// the [BibleSearchResult] so the caller can insert it into a note.
class BibleSearchScreen extends ConsumerStatefulWidget {
  /// When true, tapping a result pops with the [BibleSearchResult]
  /// instead of showing the action bottom sheet.
  final bool selectMode;

  const BibleSearchScreen({super.key, this.selectMode = false});

  @override
  ConsumerState<BibleSearchScreen> createState() => _BibleSearchScreenState();
}

class _BibleSearchScreenState extends ConsumerState<BibleSearchScreen> {
  static const _pageSize = 10;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<BibleSearchResult> _results = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _hasSearched = false;
  String? _error;
  BibleSearchFilters _filters = BibleSearchFilters.empty;
  BibleSearchSortOption _sortOption = BibleSearchSortOption.frequency;

  /// Cached verse count — fetched once from the worker isolate, then
  /// constant for the session. `null` means "not yet returned" so the UI can
  /// avoid showing the empty-database state during the brief cold-start
  /// window while the isolate spawns.
  int? _verseCount;

  /// Monotonically increasing generation counter. Each call to
  /// [_performSearch] bumps this so that stale results from a
  /// superseded search are silently discarded.
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Pre-select the default translation so searches don't return
    // duplicate results for every installed version.
    final defaultVersion = ref.read(defaultBibleVersionProvider);
    if (defaultVersion.isNotEmpty) {
      _filters = BibleSearchFilters(translations: {defaultVersion});
    }

    // Verse count runs in the background isolate; surface it once ready.
    final service = ref.read(bibleSearchServiceProvider);
    service.getVerseCount().then((count) {
      if (!mounted) return;
      setState(() => _verseCount = count);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMore();
    }
  }

  // ── Search Logic ─────────────────────────────────────────────────────

  void _onTextChanged(String _) {
    // Only rebuild for clear/search button visibility — no search triggered.
    setState(() {});
  }

  void _triggerSearch() {
    final query = _searchController.text.trim();
    if (query.length < 2) return;
    // Dismiss keyboard so results are fully visible.
    FocusScope.of(context).unfocus();
    _performSearch(query);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _results = [];
      _hasSearched = false;
      _isLoading = false;
      _isLoadingMore = false;
      _hasMore = true;
      _error = null;
    });
  }

  /// Returns the translation set to send to FTS, dropping the filter when it
  /// already covers every translation present in the local DB. The resulting
  /// `IN (?)` clause would otherwise force FTS5 to rank rows it would never
  /// reject — meaningful overhead when only one translation is installed.
  Set<String> _effectiveTranslations() {
    final installed = ref.read(bibleTranslationsProvider);
    if (installed.isEmpty) return _filters.translations;
    return _filters.translations.length >= installed.length
        ? const <String>{}
        : _filters.translations;
  }

  Future<void> _performSearch(String query) async {
    final generation = ++_searchGeneration;

    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
      _hasMore = true;
    });

    try {
      final service = ref.read(bibleSearchServiceProvider);

      final results = await service.search(
        query: query,
        testaments: _filters.testaments,
        bookIds: _filters.bookIds,
        translations: _effectiveTranslations(),
        sortBy: _sortOption,
        limit: _pageSize,
        offset: 0,
      );

      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _hasSearched = true;
        _hasMore = results.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = [];
        _isLoading = false;
        _hasSearched = true;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    final query = _searchController.text.trim();
    if (query.length < 2) return;

    final generation = _searchGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final service = ref.read(bibleSearchServiceProvider);

      final more = await service.search(
        query: query,
        testaments: _filters.testaments,
        bookIds: _filters.bookIds,
        translations: _effectiveTranslations(),
        sortBy: _sortOption,
        limit: _pageSize,
        offset: _results.length,
      );

      // Drop the page if a new search has been triggered while we were
      // waiting on the worker isolate.
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = [..._results, ...more];
        _isLoadingMore = false;
        _hasMore = more.length >= _pageSize;
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _isLoadingMore = false);
    }
  }

  void _onFiltersChanged(BibleSearchFilters newFilters) {
    setState(() => _filters = newFilters);

    // Re-run search with new filters only if a search was already submitted.
    final query = _searchController.text.trim();
    if (_hasSearched && query.length >= 2) {
      _performSearch(query);
    }
  }

  void _onSortChanged(BibleSearchSortOption option) {
    if (option == _sortOption) return;
    setState(() => _sortOption = option);

    final query = _searchController.text.trim();
    if (_hasSearched && query.length >= 2) {
      _performSearch(query);
    }
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: AppTheme.paddingAllBase,
              child: Text(
                'Sort by',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            ...BibleSearchSortOption.values.map((option) => ListTile(
              title: Text(option.label),
              trailing: _sortOption == option
                  ? Icon(Icons.check_rounded,
                      color: Theme.of(context).colorScheme.primary)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _onSortChanged(option);
              },
            )),
          ],
        ),
      ),
    );
  }

  // ── Verse Actions ────────────────────────────────────────────────────

  void _onVerseTapped(BibleSearchResult result) {
    if (widget.selectMode) {
      Navigator.of(context).pop(result);
      return;
    }
    _showVerseActions(result);
  }

  void _showVerseActions(BibleSearchResult result) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: AppTheme.paddingAllBase,
              child: Text(
                result.displayReference,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy verse'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: result.copyText));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Verse copied to clipboard'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            if (widget.selectMode)
              ListTile(
                leading: const Icon(Icons.note_add),
                title: const Text('Insert into note'),
                subtitle: const Text('Returns verse to the editor'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pop(result);
                },
              ),
            ListTile(
              leading: const Icon(Icons.menu_book),
              title: const Text('View in chapter'),
              subtitle: Text(
                '${result.bookName} ${result.chapter}',
              ),
              onTap: () {
                Navigator.pop(ctx);
                context.go(
                  '${Routes.bible}/chapter'
                  '?bookId=${result.bookId}'
                  '&chapter=${result.chapter}'
                  '&translation=${result.translation}'
                  '&verse=${result.verse}',
                );
              },
            ),
            const SizedBox(height: AppTheme.spacing8),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  /// Bible tab accent colour — matches the bottom nav item.
  static const _bibleGreen = AppTheme.bibleGreen;

  @override
  Widget build(BuildContext context) {
    final parentTheme = Theme.of(context);
    final service = ref.watch(bibleSearchServiceProvider);
    final allBooks = ref.watch(bibleBooksProvider);
    final translations = ref.watch(bibleTranslationsProvider);

    // Build the overridden theme once so it can be passed to helpers
    // (Theme.of(context) in helpers would resolve the *parent* theme).
    final theme = parentTheme.copyWith(
      colorScheme: parentTheme.colorScheme.copyWith(
        primary: _bibleGreen,
        onPrimary: Colors.white,
        secondaryContainer: AppTheme.bibleBackground,
        onSecondaryContainer: AppTheme.bibleForeground,
      ),
    );

    return Theme(
      data: theme,
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: parentTheme.scaffoldBackgroundColor,
        elevation: 0,
        // Only show a close button when opened as a verse-picker dialog.
        // As a tab, no leading icon is needed.
        leading: widget.selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
              )
            : null,
        automaticallyImplyLeading: false,
        title: const Text(
          'Bible Search',
          style: AppTheme.headingMedium,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: AppTheme.paddingH16,
          child: Column(
            children: [
              // Search field
              TextField(
                controller: _searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search Bible verses...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.arrow_forward_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              onPressed: _triggerSearch,
                            ),
                          ],
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: AppTheme.borderRadiusFull,
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _triggerSearch(),
              ),
              const SizedBox(height: AppTheme.spacing12),

              // Filters
              BibleSearchFiltersBar(
                filters: _filters,
                onChanged: _onFiltersChanged,
                allBooks: allBooks,
                availableTranslations: translations,
              ),
              const SizedBox(height: AppTheme.spacing12),

              // Results area
              Expanded(
                child: _buildBody(theme: theme, isAvailable: service.isAvailable),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildBody({required ThemeData theme, required bool isAvailable}) {

    if (_isLoading) {
      return const ListTileSkeletonList(count: 6, hasLeading: false);
    }

    // Database not available
    if (!isAvailable) {
      return _buildUnavailableState(theme);
    }

    // Database empty state — only after the count has actually returned.
    // While _verseCount is null we're still waiting on the worker isolate's
    // first response; assume the DB is non-empty so the user doesn't see a
    // misleading "no data" flash.
    if (_verseCount == 0 && !_hasSearched) {
      return _buildEmptyDatabaseState(theme);
    }

    // Initial state (no search yet)
    if (!_hasSearched) {
      return _buildInitialState(theme);
    }

    // Error state
    if (_error != null) {
      return _buildErrorState(theme);
    }

    // No results
    if (_results.isEmpty) {
      return _buildNoResultsState(theme);
    }

    // Results list
    return _buildResultsList(theme);
  }

  Widget _buildUnavailableState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'Bible database not available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'The Bible database could not be loaded.\nPlease restart the app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDatabaseState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'No Bible data loaded',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'The Bible database has no verses.\nPlease reinstall the app to restore the data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'Search Bible verses by text',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            'e.g., "faith hope love"',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.outline,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          // Hidden until the background isolate returns the count, otherwise
          // the user briefly sees "0 verses loaded" on cold start.
          if ((_verseCount ?? 0) > 0)
            Text(
              '${_verseCount!} verses loaded',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'Search failed',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            'No verses found',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_filters.hasActiveFilters) ...[
            const SizedBox(height: AppTheme.spacing8),
            TextButton(
              onPressed: () =>
                  _onFiltersChanged(BibleSearchFilters.empty),
              style: TextButton.styleFrom(foregroundColor: AppTheme.textMuted),
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    final itemCount = _results.length + (_hasMore ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Result count + sort control
        Padding(
          padding: const EdgeInsets.only(left: AppTheme.spacing4, right: AppTheme.spacing4, bottom: AppTheme.spacing8),
          child: Row(
            children: [
              Text(
                '${_results.length}${_hasMore ? '+' : ''} result${_results.length == 1 ? '' : 's'}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _showSortOptions,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _sortOption.label,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing4),
                    Icon(
                      Icons.swap_vert_rounded,
                      size: AppTheme.iconSM,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Results
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: itemCount,
            itemBuilder: (_, i) {
              if (i >= _results.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTheme.spacing16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              return BibleVerseResultCard(
                result: _results[i],
                onTap: () => _onVerseTapped(_results[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}
