import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Theme-aware foreground colours, as short to write as the raw literals they
/// replace.
///
/// The app accumulated 177 colour literals — `Colors.grey.shade400` for hint
/// text, `Colors.red` for destructive labels — none of which met 4.5:1, and
/// none of which the contrast audit could see, because it reads the design
/// tokens and a literal never reaches them. They were also fixed to the light
/// theme, so they survived unchanged into dark mode.
///
/// These getters resolve against the active theme and are covered by the
/// audit, so `context.mutedText` is both shorter than the literal it replaces
/// and checked.
extension ThemeColors on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;
  Brightness get _brightness => Theme.of(this).brightness;

  /// Body text and anything else that must read as primary content.
  Color get primaryText => _scheme.onSurface;

  /// Secondary text: metadata, captions, supporting lines. Still 4.5:1.
  Color get mutedText => _scheme.onSurfaceVariant;

  /// Placeholder text inside an input. Distinct from [mutedText] only in
  /// intent — deliberately the same value, because a hint that is quieter
  /// than secondary text is a hint nobody can read.
  Color get hintText => _scheme.onSurfaceVariant;

  /// A glyph or rule that is decoration rather than information: dividers,
  /// chevrons, empty-state art. Held to the 3:1 graphical minimum.
  ///
  /// Reads the per-theme outline role rather than a fixed grey — the point of
  /// this extension is that nothing here is pinned to one theme.
  Color get decorativeInk => _scheme.outline;

  /// Destructive and error text.
  Color get dangerText => AppTheme.semanticFor(AppTheme.error, _brightness);

  /// The "favourite" heart.
  ///
  /// Red by convention, not by severity, so it is deliberately not
  /// [dangerText] — a saved song is not an error. It shares the error hue
  /// because that is the red the palette already defines. Icons are
  /// graphical objects and need 3:1, not 4.5:1, which this clears on both
  /// grounds (3.68:1 on light, 5.08:1 on dark).
  Color get favoriteInk => AppTheme.error;

  /// Confirmation and success text.
  Color get successText => AppTheme.semanticFor(AppTheme.success, _brightness);

  /// Caution text — pending, unsynced, needs attention.
  Color get warningText => AppTheme.semanticFor(AppTheme.warning, _brightness);

  /// Informational text.
  Color get infoText => AppTheme.semanticFor(AppTheme.info, _brightness);

  /// The surface a card or sheet paints itself with.
  /// A design-system colour tuned for the current theme, for text or a glyph.
  ///
  /// The raw tokens are tuned for one ground and fail on the other: teal as
  /// text measures 1.93:1 on white, and brandBlue 3.54:1 on its own dark tint.
  /// Pass the colour you want and get the readable version of it. The raw
  /// token stays correct for the *tint behind* the text — only the foreground
  /// needs tuning.
  ///
  /// semanticFor, not accentOnTintFor: the accent maps hold the nine brand
  /// hues, and a caller with a `Color accent` parameter also hands over
  /// AppTheme.error and AppTheme.mutedGrey. accentOnTintFor returns those
  /// unchanged — mutedGrey measures 2.36:1 as a glyph on its own light tint.
  /// semanticFor covers error, warning, success, info, mutedGrey and the
  /// status colours, and falls through to the accent maps for the rest.
  Color accentInk(Color accent) => AppTheme.semanticFor(accent, _brightness);

  Color get cardSurface => _scheme.surface;

  /// A surface raised above [cardSurface] — sheets over pages, menus.
  Color get raisedSurface => _scheme.surfaceContainerHigh;

  /// The page behind the cards.
  Color get pageGround => Theme.of(this).scaffoldBackgroundColor;

  /// A hairline: divider, card outline, input border at rest.
  Color get hairline => _scheme.outlineVariant;

  /// A quiet filled block — chip grounds, skeletons, empty heat-map cells.
  Color get subtleFill => _scheme.surfaceContainerHighest;

}
