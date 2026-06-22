/// A scripture memorization card managed by spaced repetition.
///
/// Persistence is currently local-only via SharedPreferences (no sync, no
/// Drift table) so the feature can ship without a schema migration. When
/// cross-device support lands, promote this to a synced Drift table and
/// keep the same field names.
class MemoryVerse {
  final String id;

  /// Free-text reference, e.g. "John 3:16" or "Romans 8:28-30".
  final String reference;

  /// The verse text the user is committing to memory.
  final String text;

  /// Bible translation code (e.g. "ESV", "NIV"). Empty when unknown.
  final String version;

  /// Optional theme/category set by the user, e.g. "Faith", "Suffering".
  final String? category;

  /// Number of times this card has been reviewed. Drives the SR interval.
  final int reviewCount;

  /// When the next review is due (Unix millis). New cards are due immediately.
  final int dueAt;

  /// Last reviewed timestamp (Unix millis); null for cards never reviewed.
  final int? lastReviewedAt;

  /// Creation timestamp (Unix millis).
  final int createdAt;

  const MemoryVerse({
    required this.id,
    required this.reference,
    required this.text,
    required this.version,
    this.category,
    required this.reviewCount,
    required this.dueAt,
    this.lastReviewedAt,
    required this.createdAt,
  });

  factory MemoryVerse.create({
    required String id,
    required String reference,
    required String text,
    String version = '',
    String? category,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return MemoryVerse(
      id: id,
      reference: reference,
      text: text,
      version: version,
      category: category,
      reviewCount: 0,
      dueAt: now,
      lastReviewedAt: null,
      createdAt: now,
    );
  }

  MemoryVerse copyWith({
    int? reviewCount,
    int? dueAt,
    int? lastReviewedAt,
    String? category,
  }) {
    return MemoryVerse(
      id: id,
      reference: reference,
      text: text,
      version: version,
      category: category ?? this.category,
      reviewCount: reviewCount ?? this.reviewCount,
      dueAt: dueAt ?? this.dueAt,
      lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
      createdAt: createdAt,
    );
  }

  bool get isDue =>
      dueAt <= DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() => {
        'id': id,
        'reference': reference,
        'text': text,
        'version': version,
        'category': category,
        'reviewCount': reviewCount,
        'dueAt': dueAt,
        'lastReviewedAt': lastReviewedAt,
        'createdAt': createdAt,
      };

  factory MemoryVerse.fromJson(Map<String, dynamic> json) {
    return MemoryVerse(
      id: json['id'] as String,
      reference: json['reference'] as String,
      text: json['text'] as String,
      version: (json['version'] as String?) ?? '',
      category: json['category'] as String?,
      reviewCount: (json['reviewCount'] as int?) ?? 0,
      dueAt: (json['dueAt'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
      lastReviewedAt: json['lastReviewedAt'] as int?,
      createdAt: (json['createdAt'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

/// User feedback after attempting to recite a verse from memory.
/// Drives the SR interval — see [SpacedRepetitionScheduler.nextInterval].
enum ReviewQuality {
  /// Forgot — reset back to step 1.
  again,

  /// Recalled with difficulty — small step forward.
  hard,

  /// Recalled correctly — normal step forward.
  good,

  /// Recalled instantly — larger step forward.
  easy,
}

/// Lightweight SM-2-inspired scheduler. Intentionally simpler than full
/// SuperMemo so the math is auditable and the intervals are predictable.
///
/// Steps in days: 1, 3, 7, 14, 30, 60, 120, 240. "Again" resets to step 0.
/// "Hard" stays at the same step. "Good" advances one step. "Easy" advances
/// two steps. Capped at the last step.
class SpacedRepetitionScheduler {
  static const List<int> _intervalDays = [1, 3, 7, 14, 30, 60, 120, 240];

  static MemoryVerse review(MemoryVerse v, ReviewQuality quality) {
    final currentStep =
        v.reviewCount.clamp(0, _intervalDays.length - 1);
    int nextStep;
    switch (quality) {
      case ReviewQuality.again:
        nextStep = 0;
        break;
      case ReviewQuality.hard:
        nextStep = currentStep;
        break;
      case ReviewQuality.good:
        nextStep = (currentStep + 1).clamp(0, _intervalDays.length - 1);
        break;
      case ReviewQuality.easy:
        nextStep = (currentStep + 2).clamp(0, _intervalDays.length - 1);
        break;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final dueAt = now + _intervalDays[nextStep] * 24 * 60 * 60 * 1000;
    return v.copyWith(
      reviewCount: nextStep,
      dueAt: dueAt,
      lastReviewedAt: now,
    );
  }

  static int nextIntervalDays(int reviewCount) {
    final step = reviewCount.clamp(0, _intervalDays.length - 1);
    return _intervalDays[step];
  }
}
