import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/memory_verse.dart';
import '../providers/memory_verse_providers.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../l10n/l10n.dart';

/// Card-flip review session. Loads the due cards once on entry; each
/// rating advances to the next card and persists the updated schedule.
class MemorizationReviewScreen extends ConsumerStatefulWidget {
  const MemorizationReviewScreen({super.key});

  @override
  ConsumerState<MemorizationReviewScreen> createState() =>
      _MemorizationReviewScreenState();
}

class _MemorizationReviewScreenState
    extends ConsumerState<MemorizationReviewScreen> {
  List<MemoryVerse>? _queue;

  /// Set when the queue could not be read. Without it a failed load left
  /// `_queue` null, which the build reads as "still loading" — so the spinner
  /// turned forever and the screen never said why.
  bool _loadFailed = false;
  int _index = 0;
  bool _revealed = false;
  int _correctCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final due = await ref.read(memoryVerseRepositoryProvider).getDue();
      if (!mounted) return;
      setState(() {
        _queue = due;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('Could not load the review queue: $e');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _rate(ReviewQuality quality) async {
    final queue = _queue;
    if (queue == null || _index >= queue.length) return;
    final current = queue[_index];
    final updated = SpacedRepetitionScheduler.review(current, quality);
    try {
      await ref.read(memoryVerseRepositoryProvider).upsert(updated);
    } catch (e) {
      // Deliberately does not advance: the new schedule was not written, so
      // moving on would lose the review silently. Before this, a failed write
      // threw past the setState and the card simply did not move — a rating
      // button that appeared to do nothing at all.
      debugPrint('Could not save the review: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n(context).couldNotSaveReview),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      if (quality == ReviewQuality.good || quality == ReviewQuality.easy) {
        _correctCount++;
      }
      _index++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queue = _queue;

    return Scaffold(
      appBar: AppBar(title: Text(l10n(context).review)),
      body: _loadFailed
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(l10n(context).couldNotLoadReviewCards,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      setState(() => _loadFailed = false);
                      _load();
                    },
                    child: Text(l10n(context).tryAgain),
                  ),
                ],
              ),
            )
          : queue == null
              ? const Center(child: CircularProgressIndicator())
              : queue.isEmpty
              ? _AllDone(message: l10n(context).noCardsAreDueRightNow)
              : _index >= queue.length
                  ? _AllDone(
                      message:
                          'Done! $_correctCount of ${queue.length} recalled correctly.',
                    )
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Card ${_index + 1} of ${queue.length}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _index / queue.length,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: _Card(
                              verse: queue[_index],
                              revealed: _revealed,
                              onTap: () =>
                                  setState(() => _revealed = !_revealed),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (!_revealed)
                            ElevatedButton(
                              onPressed: () =>
                                  setState(() => _revealed = true),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: Text(l10n(context).showVerse),
                            )
                          else
                            _RatingRow(onRate: _rate),
                        ],
                      ),
                    ),
    );
  }
}

class _Card extends StatelessWidget {
  final MemoryVerse verse;
  final bool revealed;
  final VoidCallback onTap;

  const _Card({
    required this.verse,
    required this.revealed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
      onTap: onTap,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                verse.reference,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
              if (verse.version.isNotEmpty)
                Text(
                  verse.version,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: context.motion(const Duration(milliseconds: 220)),
                child: revealed
                    ? Text(
                        verse.text,
                        key: const ValueKey('revealed'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium,
                      )
                    : Text(
                        'Try to recite this verse from memory.\n\nTap to reveal.',
                        key: const ValueKey('hidden'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _RatingRow extends StatelessWidget {
  final Future<void> Function(ReviewQuality) onRate;
  const _RatingRow({required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => onRate(ReviewQuality.again),
            child: Text(l10n(context).again),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton(
            onPressed: () => onRate(ReviewQuality.hard),
            child: Text(l10n(context).hard),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () => onRate(ReviewQuality.good),
            child: Text(l10n(context).good),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton(
            onPressed: () => onRate(ReviewQuality.easy),
            child: Text(l10n(context).easy),
          ),
        ),
      ],
    );
  }
}

class _AllDone extends StatelessWidget {
  final String message;
  const _AllDone({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
