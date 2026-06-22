import 'package:flutter/material.dart';

import '../tutorial_providers.dart';
import '../tutorial_step.dart';

/// The home-screen tutorial shown to new users on first login.
///
/// Steps:
///   1. Quick Actions — shortcut buttons
///   2. Daily Focus   — daily prayer highlight
///   3. Navigation    — bottom tab bar
///   4. Celebration   — all done, tips for editor help
List<TutorialStep> homeTutorialSteps() => [
      TutorialStep(
        targetKey: tutorialKey(TutorialKeyId.quickActionsRow),
        title: 'Quick Actions',
        description:
            'Tap here to quickly create a note, log a prayer, add a promise, or search — all in one tap.',
        shape: TutorialSpotlightShape.roundedRect,
        tooltipSide: TutorialTooltipSide.above,
        spotlightPadding:
            const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        icon: Icons.bolt_rounded,
      ),
      TutorialStep(
        targetKey: tutorialKey(TutorialKeyId.dailyFocusCard),
        title: 'Daily Focus',
        description:
            'Each day a prayer from your list is highlighted here to keep you centred. Tap it to go directly to your prayers.',
        shape: TutorialSpotlightShape.roundedRect,
        tooltipSide: TutorialTooltipSide.below,
        spotlightPadding: const EdgeInsets.all(8),
        icon: Icons.wb_sunny_outlined,
      ),
      TutorialStep(
        targetKey: tutorialKey(TutorialKeyId.bottomNavBar),
        title: 'Navigate the App',
        description:
            'Switch between Notes, Prayers, Bible, Promises, Songs, and Social using these tabs. Each tab keeps its own history.',
        shape: TutorialSpotlightShape.roundedRect,
        tooltipSide: TutorialTooltipSide.above,
        spotlightPadding: const EdgeInsets.symmetric(vertical: 4),
        icon: Icons.tab_rounded,
      ),
      const TutorialStep(
        title: "You're All Set!",
        description:
            'Explore at your own pace.\n\n'
            '• In the note editor, tap the \u2753 button in the toolbar for a full formatting guide.\n'
            '• You can replay this tour anytime from Settings → About.',
        shape: TutorialSpotlightShape.none,
        tooltipSide: TutorialTooltipSide.center,
        icon: Icons.celebration_rounded,
      ),
    ];
