import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/tutorial/tutorial_providers.dart';
import '../../l10n/l10n.dart';

/// A one-time, dismissible explanation of what a tab is for.
///
/// The onboarding flow sold the app ("Capture what God teaches you") without
/// teaching it, and the four-step home tour was the only guidance anywhere —
/// six of seven tabs were entered cold. This is the missing piece: the first
/// time someone opens a section, it says in plain words what the section holds
/// and what to do first.
///
/// It sits inline at the top of the list rather than appearing as a modal, so
/// it never blocks someone who already knows the app, and it disappears for
/// good once dismissed.
class FeatureIntro extends ConsumerStatefulWidget {
  /// Stable id used to remember dismissal: 'notes', 'bible', 'prayers'…
  final String featureId;
  final IconData icon;
  final String title;
  final String message;
  final Color accent;

  const FeatureIntro({
    super.key,
    required this.featureId,
    required this.icon,
    required this.title,
    required this.message,
    required this.accent,
  });

  @override
  ConsumerState<FeatureIntro> createState() => _FeatureIntroState();
}

class _FeatureIntroState extends ConsumerState<FeatureIntro> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.read(tutorialServiceProvider);
    if (_dismissed || !service.needsFeatureIntro(widget.featureId)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final accent = theme.brightness == Brightness.dark
        ? AppTheme.accentOnDark(widget.accent)
        : AppTheme.accentOnLight(widget.accent);

    return Semantics(
      container: true,
      child: Container(
        // Vertical only: the banner sits inside whatever horizontal padding
        // its list or column already applies, so baking in a side margin
        // here double-inset it against its own siblings. Screens that place
        // it in an unpadded parent wrap it in their own Padding.
        margin: const EdgeInsets.only(top: 12, bottom: 4),
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: AppTheme.alphaLight),
          borderRadius: AppTheme.borderRadius2XL,
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(widget.icon, size: 24, color: accent)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              tooltip: l10n(context).gotItHideThis,
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: () async {
                await service.markFeatureIntroSeen(widget.featureId);
                if (mounted) setState(() => _dismissed = true);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The intro copy for each tab, in one place so the vocabulary stays
/// consistent — and so the terms the app coins ("Promise", "Selah") are
/// actually defined somewhere the user will see.
abstract final class FeatureIntros {
  static const notes = FeatureIntro(
    featureId: 'notes',
    icon: Icons.description_outlined,
    title: 'Your notes',
    message: 'Write down what you hear in a sermon or study. Add verses, and '
        'group related notes into folders.',
        accent: AppTheme.brandPurple,
  );

  static const bible = FeatureIntro(
    featureId: 'bible',
    icon: Icons.menu_book_outlined,
    title: 'Read the Bible',
    message: 'Pick a book and chapter to read. Tap any verse to highlight it '
        'or add a note, and use Aa at the top to make the text bigger.',
        accent: AppTheme.emerald,
  );

  static const prayers = FeatureIntro(
    featureId: 'prayers',
    icon: Icons.favorite_outline_rounded,
    title: 'Your prayers',
    message: 'Keep track of what you are praying for. Mark a prayer as '
        'answered when it is, and look back at what God has done.',
        accent: AppTheme.brandBlue,
  );

  static const promises = FeatureIntro(
    featureId: 'promises',
    icon: Icons.bookmark_outline_rounded,
    title: 'Your promises',
    message: 'A promise is a verse you want to hold on to. Save the ones that '
        'matter to you, so you can come back to them.',
        accent: AppTheme.rosePink,
  );

  static const songs = FeatureIntro(
    featureId: 'songs',
    icon: Icons.music_note_outlined,
    title: 'Your songs',
    message: 'Keep the songs your church sings, with lyrics and chords. '
        'Transpose to whatever key you need.',
        accent: AppTheme.orange,
  );

  static const social = FeatureIntro(
    featureId: 'social',
    icon: Icons.groups_outlined,
    title: 'Pray together',
    message: 'Add friends and join groups to share prayer requests, and see '
        'what others have asked prayer for.',
        accent: AppTheme.teal,
  );
}
