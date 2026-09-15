import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Application theme configuration — Single Source of Truth.
///
/// ALL colors, spacing, radii, shadows, text styles, and component tokens
/// are defined here. Import this file instead of hardcoding values in widgets.
class AppTheme {
  AppTheme._();

  // ═══════════════════════════════════════════════════════════════════════════
  // BRAND PALETTE
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color brandBlue = Color(0xFF2D6CDF);
  static const Color brandPurple = Color(0xFF7B61FF);
  static const Color navyDark = Color(0xFF0D1B3E);
  static const Color navyMid = Color(0xFF1A3666);
  static const Color scaffoldGray = Color(0xFFF4F5F7);

  // Container and outline roles, set explicitly on both ColorSchemes. Widgets
  // read these for chip grounds, skeletons, dividers and card edges; leaving
  // them to ColorScheme's defaults meant ~100 migrated call sites resolving to
  // a Material grey no one had measured.
  static const Color containerHigh = Color(0xFFF1F2F6);
  static const Color containerHighest = Color(0xFFE9EAF0);
  static const Color hairlineLight = Color(0xFFD3D6DE);
  /// Tuned against [scaffoldGray], not white: an outline that clears 3:1 on
  /// a white card can still fail on the slightly darker page behind it, and
  /// the page is where most dividers and chevrons actually sit.
  static const Color outlineLight = Color(0xFF858B99);
  static const Color darkContainerHigh = Color(0xFF1F232D);
  static const Color darkContainerHighest = Color(0xFF262B37);

  // ── Accent palette ──────────────────────────────────────────────────────
  static const Color teal = Color(0xFF4ECDC4);
  static const Color rosePink = Color(0xFFE74C6F);
  static const Color coral = Color(0xFFFF6B6B);
  static const Color amber = Color(0xFFE67E22);
  static const Color orange = Color(0xFFFF9F43);
  static const Color orangeFaint = Color(0x1AFF9F43);
  static const Color emerald = Color(0xFF27AE60);
  static const Color bibleGreen = Color(0xFF43A047);
  static const Color skyBlue = Color(0xFF3498DB);
  static const Color cyan = Color(0xFF00BCD4);
  static const Color mutedGrey = Color(0xFF95A5A6);

  // ── Text / surface ──────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF1C1C1E);
  /// Secondary text. Clears AA on both the white surface (4.98:1) and the
  /// [scaffoldGray] page (4.57:1) — the previous value passed on white but
  /// missed at 4.43:1 on the page, which is where most of it is drawn.
  static const Color textMuted = Color(0xFF626874);

  // ── Dark theme surfaces ─────────────────────────────────────────────────
  // Devotional reading happens early morning and last thing at night, so a
  // full-white screen is a reason people stop using the app rather than adjust
  // it. These are the dark counterparts of the light surface tokens.
  static const Color darkScaffold = Color(0xFF101218);
  static const Color darkSurface = Color(0xFF181B23);
  static const Color darkSurfaceRaised = Color(0xFF1F232D);
  /// Divider / hairline on dark surfaces. Subtle by design.
  static const Color darkBorder = Color(0xFF333846);

  /// Card and container edge on dark surfaces. A dark card is only 1.09:1
  /// against the dark page and shadows do not read on a dark ground, so the
  /// edge is what separates a card from the background — it needs the 3:1
  /// non-text minimum, not a hairline.
  static const Color darkCardBorder = Color(0xFF616A84);
  static const Color darkTextPrimary = Color(0xFFE8E9EF);
  static const Color darkTextMuted = Color(0xFFA0A6B8);
  static const Color darkInputBorder = Color(0xFF6E7688);

  /// Accent variants for dark surfaces. The light-theme accents are too dark
  /// to read on a dark ground, so each is lightened until it clears 4.5:1 on
  /// [darkSurface].
  static const Color brandBlueOnDark = Color(0xFF8FA8F0);
  static const Color brandPurpleOnDark = Color(0xFFB49CFF);
  static const Color emeraldOnDark = Color(0xFF5FD08C);
  static const Color rosePinkOnDark = Color(0xFFFF8CA6);
  static const Color orangeOnDark = Color(0xFFFFB067);
  static const Color tealOnDark = Color(0xFF5FD3C9);

  /// Maps a palette accent to a variant readable on a dark surface.
  static Color accentOnDark(Color accent) => _accentOnDark[accent] ?? accent;

  static final Map<Color, Color> _accentOnDark = {
    brandBlue: brandBlueOnDark,
    brandPurple: brandPurpleOnDark,
    emerald: emeraldOnDark,
    rosePink: rosePinkOnDark,
    orange: orangeOnDark,
    teal: tealOnDark,
  };

  // ── Foreground on light tinted surfaces ─────────────────────────────────
  // An accent colour cannot be used as text on a tint of itself: same hue and
  // similar lightness caps contrast at 1.4–2.3:1 whichever accent is chosen.
  // Tinted cards therefore draw text in these neutrals and reserve the accent
  // for glyphs.

  /// Primary text on a light tinted surface. ≥12.6:1 on every card tint.
  static const Color onTintPrimary = textDark;

  /// Primary/secondary text on a tinted card, for the active theme. In dark
  /// the tint is a deep shade of the accent, so near-black text would vanish.
  static Color onTintPrimaryFor(Brightness b) =>
      b == Brightness.dark ? darkTextPrimary : onTintPrimary;

  /// Muted body text is drawn on the page surface, where [darkTextMuted]
  /// passes — but on a *tinted* card in dark mode it drops as low as 3.46:1
  /// (teal). Tinted surfaces get their own, lighter muted neutral.
  static const Color onTintMutedOnDark = Color(0xFFC3C4C6);

  static Color onTintSecondaryFor(Brightness b) =>
      b == Brightness.dark ? onTintMutedOnDark : onTintSecondary;

  /// Accent safe as a glyph on a tinted card, for the active theme.
  static Color accentOnTintFor(Color accent, Brightness b) =>
      b == Brightness.dark ? accentOnDark(accent) : accentOnLight(accent);

  /// Secondary text on a light tinted surface. ≥7.5:1 worst case, while
  /// staying visibly subordinate to [onTintPrimary].
  static const Color onTintSecondary = Color(0xFF3D4150);

  // ── Tinted "ink": text that carries the card's own hue ──────────────────
  // Neutral near-black on a coloured card reads as a default rather than a
  // choice, and the six card tints end up looking like one grey template.
  // These are the accent itself darkened (light) or lightened (dark) until it
  // clears WCAG on that card's *most saturated* gradient stop — the hardest
  // background the text actually sits on — so each card's text belongs to its
  // own colour while staying comfortably legible.
  //
  // Primary clears 6:1 and muted 4.5:1, both above the 4.5 requirement for
  // normal text; the gap between them is what preserves the count/label
  // hierarchy now that both are hued.

  static const Color inkBlue = Color(0xFF1C438A);
  static const Color inkPurple = Color(0xFF493996);
  static const Color inkEmerald = Color(0xFF145931);
  static const Color inkRose = Color(0xFF7F2A3D);
  static const Color inkOrange = Color(0xFF75491F);
  static const Color inkTeal = Color(0xFF245E5A);
  static const Color inkError = Color(0xFF84241D);

  static const Color inkBlueMuted = Color(0xFF2354AE);
  static const Color inkPurpleMuted = Color(0xFF5A47BA);
  static const Color inkEmeraldMuted = Color(0xFF196E3C);
  static const Color inkRoseMuted = Color(0xFF9F344D);
  static const Color inkOrangeMuted = Color(0xFF8F5926);
  static const Color inkTealMuted = Color(0xFF2B716C);
  static const Color inkErrorMuted = Color(0xFFA12C24);

  static const Color inkBlueOnDark = Color(0xFF9AB8F0);
  static const Color inkPurpleOnDark = Color(0xFFBEB2FF);
  static const Color inkEmeraldOnDark = Color(0xFF95D7B1);
  static const Color inkRoseOnDark = Color(0xFFF3A9BA);
  static const Color inkOrangeOnDark = Color(0xFFFFCD9D);
  static const Color inkTealOnDark = Color(0xFFA5E6E1);
  static const Color inkErrorOnDark = Color(0xFFFAA59F);

  static const Color inkBlueOnDarkMuted = Color(0xFF7BA2EB);
  static const Color inkPurpleOnDarkMuted = Color(0xFFA897FF);
  static const Color inkEmeraldOnDarkMuted = Color(0xFF63C58D);
  static const Color inkRoseOnDarkMuted = Color(0xFFEF89A0);
  static const Color inkOrangeOnDarkMuted = Color(0xFFFFAD5F);
  static const Color inkTealOnDarkMuted = Color(0xFF65D4CC);
  static const Color inkErrorOnDarkMuted = Color(0xFFF8837A);

  static final Map<Color, Color> _inkOnTint = {
    error: inkError,
    brandBlue: inkBlue,
    brandPurple: inkPurple,
    emerald: inkEmerald,
    rosePink: inkRose,
    orange: inkOrange,
    teal: inkTeal,
  };

  static final Map<Color, Color> _inkOnTintMuted = {
    error: inkErrorMuted,
    brandBlue: inkBlueMuted,
    brandPurple: inkPurpleMuted,
    emerald: inkEmeraldMuted,
    rosePink: inkRoseMuted,
    orange: inkOrangeMuted,
    teal: inkTealMuted,
  };

  static final Map<Color, Color> _inkOnTintDark = {
    error: inkErrorOnDark,
    brandBlue: inkBlueOnDark,
    brandPurple: inkPurpleOnDark,
    emerald: inkEmeraldOnDark,
    rosePink: inkRoseOnDark,
    orange: inkOrangeOnDark,
    teal: inkTealOnDark,
  };

  static final Map<Color, Color> _inkOnTintDarkMuted = {
    error: inkErrorOnDarkMuted,
    brandBlue: inkBlueOnDarkMuted,
    brandPurple: inkPurpleOnDarkMuted,
    emerald: inkEmeraldOnDarkMuted,
    rosePink: inkRoseOnDarkMuted,
    orange: inkOrangeOnDarkMuted,
    teal: inkTealOnDarkMuted,
  };

  /// Primary text on a tinted card, tinted with that card's own accent.
  ///
  /// An accent outside the palette (a remote-config override, say) has no
  /// verified ink, so it falls back to the audited neutral rather than a
  /// derived colour nobody has checked for contrast.
  static Color inkOnTintFor(Color accent, Brightness b) =>
      (b == Brightness.dark ? _inkOnTintDark : _inkOnTint)[accent] ??
      onTintPrimaryFor(b);

  /// Subordinate text on a tinted card. Same hue as [inkOnTintFor], lighter.
  static Color inkOnTintMutedFor(Color accent, Brightness b) =>
      (b == Brightness.dark ? _inkOnTintDarkMuted : _inkOnTintMuted)[accent] ??
      onTintSecondaryFor(b);

  // ── Accent variants safe as foreground on light surfaces ────────────────
  // Each clears 4.5:1 against its own 10% tint — the background these are
  // most often drawn on (badges, pills, avatar circles) and the strictest of
  // the cases. That implies passing on plain white too (4.84-5.15), and on
  // the lighter 20% card tint they clear the 3:1 glyph minimum. The raw
  // palette values clear none of these: teal was 1.81 and orange 1.90 on
  // their own tints, 1.93 and 2.04 on white.
  static const Color brandBlueOnLight = Color(0xFF2564D7);
  static const Color brandPurpleOnLight = Color(0xFF694CFF);
  static const Color emeraldOnLight = Color(0xFF1C7F46);
  static const Color rosePinkOnLight = Color(0xFFD61D46);
  static const Color orangeOnLight = Color(0xFFB45800);
  static const Color tealOnLight = Color(0xFF247E77);

  /// Maps a palette accent to a variant safe to draw as an icon on a light
  /// tinted surface. [brandBlue] already clears 3:1 and is returned unchanged,
  /// as is any colour outside the palette (e.g. a remote-config override), so
  /// a deliberate custom colour is never silently replaced.
  static Color accentOnLight(Color accent) => _accentOnLight[accent] ?? accent;

  static final Map<Color, Color> _accentOnLight = {
    brandBlue: brandBlueOnLight,
    brandPurple: brandPurpleOnLight,
    emerald: emeraldOnLight,
    rosePink: rosePinkOnLight,
    orange: orangeOnLight,
    teal: tealOnLight,
  };

  // ── Per-tab accent colours (ordered by bottom-nav index) ────────────────
  static const tabColors = [
    brandBlue,    // 0 Home     — blue
    brandPurple,  // 1 Notes    — purple
    brandBlue,    // 2 Prayers  — blue
    emerald,      // 3 Bible    — green
    rosePink,     // 4 Promises — dark pink
    orange,       // 5 Songs    — orange
    teal,         // 6 Social   — teal
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // SEMANTIC COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Background for an error snackbar or banner. White on the raw [error] red
  /// is only 3.68:1; this clears AA at 5.94:1, so the message is actually
  /// readable at the moment something has gone wrong.
  static const Color errorSurface = Color(0xFFC6180B);

  // ── Solid accent fills ──────────────────────────────────────────────────
  // A FAB, a filled button or any solid accent block carries a white glyph,
  // and the raw palette cannot: teal behind white is 1.93:1, orange 2.04,
  // emerald 2.87. Every FAB in the app used the raw value, so most of them
  // had an icon nobody could see. These are the same hues darkened until
  // white clears 4.5:1, and they read as the accent they came from.
  static const Color brandBlueSurface = brandBlue; // already 4.86:1
  static const Color brandPurpleSurface = Color(0xFF745BF0);
  static const Color emeraldSurface = Color(0xFF1E864A);
  static const Color rosePinkSurface = Color(0xFFCB4362);
  static const Color orangeSurface = Color(0xFFA3662B);
  static const Color tealSurface = Color(0xFF31817B);

  static final Map<Color, Color> _accentSurface = {
    brandBlue: brandBlueSurface,
    brandPurple: brandPurpleSurface,
    emerald: emeraldSurface,
    rosePink: rosePinkSurface,
    orange: orangeSurface,
    teal: tealSurface,
  };

  /// The glyph colour for a solid block of the *true* [accent].
  ///
  /// Prefer this to [accentSurface] wherever the fill is icon-only. Darkening
  /// the accent so white works turns orange into brown and teal into slate —
  /// the control stops looking like its own tab. Keeping the real colour and
  /// choosing the glyph keeps the brand intact: teal and orange take a dark
  /// glyph (8.8:1 and 8.3:1), blue and purple take white.
  ///
  /// Sound for an icon, which needs 3:1. A fill carrying *text* needs 4.5:1
  /// and should use [accentSurface] instead — brandPurple behind white is
  /// 4.20, fine for a glyph and short for a label.
  static Color onAccent(Color accent) {
    final white = _contrast(Colors.white, accent);
    final ink = _contrast(textDark, accent);
    return white >= ink ? Colors.white : textDark;
  }

  static double _relativeLuminance(Color c) {
    double channel(double v) {
      v = v / 255.0;
      return v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(c.r * 255) +
        0.7152 * channel(c.g * 255) +
        0.0722 * channel(c.b * 255);
  }

  static double _contrast(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// A solid fill of [accent] that a white glyph can sit on.
  ///
  /// Theme-independent: the fill is opaque, so the surface behind it does not
  /// change the contrast. An accent with no verified fill falls back to the
  /// audited primary rather than to an unchecked colour.
  static Color accentSurface(Color accent) =>
      _accentSurface[accent] ?? brandBlueSurface;


  /// Ground for snackbars in both themes. Fixing it here rather than letting
  /// each theme derive `inverseSurface` keeps the action-label contrast
  /// deterministic.
  static const Color snackBackground = Color(0xFF2F3033);

  /// Action label ("Undo") on [snackBackground] — 6.33:1.
  static const Color snackAction = Color(0xFF8AB5FA);

  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFF5A623);
  static const Color info = skyBlue;

  // ── Semantic colours as foreground ──────────────────────────────────────
  // The semantic palette above is tuned as a *fill*. Drawn as text — which is
  // what StatusChip and ColoredBadge do — every one of them fails AA on white
  // (warning 2.03:1, statusInProgress 1.94:1). These are the darkened
  // equivalents for light surfaces; on dark the original brighter values are
  // already correct (7.3-8.9:1), so [semanticFor] picks per theme.
  static const Color successOnLight = Color(0xFF16803D);
  static const Color errorOnLight = Color(0xFFD5190C);
  static const Color warningOnLight = Color(0xFF9B6407);
  static const Color infoOnLight = Color(0xFF1F75AF);
  static const Color statusOpenOnLight = Color(0xFF0B72C4);
  static const Color statusInProgressOnLight = Color(0xFFA16000);
  static const Color statusResolvedOnLight = Color(0xFF387E3B);
  static const Color mutedGreyOnLight = Color(0xFF627374);

  static final Map<Color, Color> _semanticOnLight = {
    success: successOnLight,
    error: errorOnLight,
    warning: warningOnLight,
    info: infoOnLight,
    statusOpen: statusOpenOnLight,
    statusInProgress: statusInProgressOnLight,
    statusResolved: statusResolvedOnLight,
    mutedGrey: mutedGreyOnLight,
  };

  /// Error red is the one semantic colour that is still too dark on a dark
  /// ground once it sits on its own tint (4.40:1). This is the M3 dark-theme
  /// error, matching the ColorScheme in [dark].
  static const Color errorOnDark = Color(0xFFFFB4AB);

  static final Map<Color, Color> _semanticOnDark = {
    error: errorOnDark,
  };

  /// A semantic (or accent) colour safe to draw as text or a glyph on the
  /// current theme's surface. Unmapped colours pass through unchanged.
  static Color semanticFor(Color color, Brightness brightness) {
    if (brightness == Brightness.dark) {
      return _semanticOnDark[color] ?? accentOnDark(color);
    }
    return _semanticOnLight[color] ?? accentOnLight(color);
  }

  // ── Feature-specific colours ────────────────────────────────────────────
  static const Color bibleBackground = Color(0xFFE8F5E9);
  static const Color bibleForeground = Color(0xFF1B5E20);
  static const Color bibleVerseNumber = Color(0xFFE65100); // amber-600 equiv
  static const Color prayerAnswered = Color(0xFF66BB6A);   // green-400 equiv
  static const Color prayerHeatmapEmpty = Color(0xFFEBEDF0);
  static const Color promiseInactive = Color(0xFFF5A623);
  static const Color ministryPurple = Color(0xFF9B59B6);

  // ── Onboarding / auth gradient colours ──────────────────────────────────
  static const Color onboardingBlue = Color(0xFF4C8EF7);
  static const Color onboardingPurple = Color(0xFF8F9CFF);
  static const Color auroraEnd = Color(0xFF1A1040);
  static const Color gradientEnd = Color(0xFF1A4FA8);

  /// Text drawn on top of a Bible highlight.
  ///
  /// The six highlight colours are light pastels in both themes, so anything
  /// on them must be near-black regardless of the active theme. Following
  /// `colorScheme.onSurface` puts near-white text on pale yellow in dark mode
  /// (1.08:1); the accent `foregroundColor` of each highlight is meant for
  /// glyphs and also fails as body text (yellow 1.84:1). This clears
  /// 7.1-15.2:1 on all six.
  static const Color onHighlight = textDark;

  // ── Bible highlight colours ─────────────────────────────────────────────
  static const Map<String, Color> highlightColors = {
    'yellow': Color(0xFFFFF59D),
    'green': Color(0xFFA5D6A7),
    'blue': Color(0xFF90CAF9),
    'pink': Color(0xFFF48FB1),
    'orange': Color(0xFFFFCC80),
    'purple': Color(0xFFCE93D8),
  };

  // ── Bible reference picker category colours ─────────────────────────────
  static const List<Color> bibleBookCategoryColors = [
    Color(0xFFE53935), // Law / Pentateuch (Red)
    Color(0xFF1E88E5), // History (Blue)
    Color(0xFFFFB300), // Wisdom / Poetry (Amber)
    Color(0xFF43A047), // Major Prophets (Green)
    Color(0xFF8E24AA), // Minor Prophets (Purple)
    Color(0xFF00897B), // Gospels / Acts (Teal)
    Color(0xFFD81B60), // Epistles / Revelation (Pink)
  ];

  // ── Status badge colours ────────────────────────────────────────────────
  static const Color statusOpen = Color(0xFF2196F3);
  static const Color statusInProgress = Color(0xFFFFA726);
  static const Color statusResolved = Color(0xFF66BB6A);
  static const Color statusClosed = mutedGrey;

  // ═══════════════════════════════════════════════════════════════════════════
  // GREY SCALE (matches Flutter Colors.grey.shadeN)
  // ═══════════════════════════════════════════════════════════════════════════

  static const Color gray50 = Color(0xFFFAFAFA);
  static const Color gray100 = Color(0xFFF5F5F5);
  static const Color gray200 = Color(0xFFEEEEEE);
  static const Color gray300 = Color(0xFFE0E0E0);
  static const Color gray400 = Color(0xFFBDBDBD);
  static const Color gray500 = Color(0xFF9E9E9E);
  static const Color gray600 = Color(0xFF757575);
  static const Color gray700 = Color(0xFF616161);
  static const Color gray800 = Color(0xFF424242);
  static const Color gray900 = Color(0xFF212121);

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDER RADII
  // ═══════════════════════════════════════════════════════════════════════════

  static const double radiusXS = 4;
  static const double radiusSM = 6;
  static const double radiusMD = 8;
  static const double radiusLG = 10;
  static const double radiusXL = 12;
  static const double radius2XL = 14;
  static const double radius3XL = 16;
  static const double radius4XL = 20;
  static const double radiusFull = 999;

  // Pre-built BorderRadius for common use
  static final BorderRadius borderRadiusXS = BorderRadius.circular(radiusXS);
  static final BorderRadius borderRadiusSM = BorderRadius.circular(radiusSM);
  static final BorderRadius borderRadiusMD = BorderRadius.circular(radiusMD);
  static final BorderRadius borderRadiusLG = BorderRadius.circular(radiusLG);
  static final BorderRadius borderRadiusXL = BorderRadius.circular(radiusXL);
  static final BorderRadius borderRadius2XL = BorderRadius.circular(radius2XL);
  static final BorderRadius borderRadius3XL = BorderRadius.circular(radius3XL);
  static final BorderRadius borderRadius4XL = BorderRadius.circular(radius4XL);
  static final BorderRadius borderRadiusFull = BorderRadius.circular(radiusFull);

  // ═══════════════════════════════════════════════════════════════════════════
  // SPACING (used for padding, margin, SizedBox, gaps)
  // ═══════════════════════════════════════════════════════════════════════════

  static const double spacing2 = 2;
  static const double spacing3 = 3;
  static const double spacing4 = 4;
  static const double spacing6 = 6;
  static const double spacing7 = 7;
  static const double spacing8 = 8;
  static const double spacing10 = 10;
  static const double spacing11 = 11;
  static const double spacing12 = 12;
  static const double spacing14 = 14;
  static const double spacing16 = 16;
  static const double spacing20 = 20;
  static const double spacing24 = 24;
  static const double spacing32 = 32;
  static const double spacing56 = 56;

  // Pre-built EdgeInsets for common patterns
  static const EdgeInsets paddingAllSM = EdgeInsets.all(spacing8);
  static const EdgeInsets paddingAllMD = EdgeInsets.all(spacing12);
  static const EdgeInsets paddingAllBase = EdgeInsets.all(spacing16);
  static const EdgeInsets paddingAllLG = EdgeInsets.all(spacing20);
  static const EdgeInsets paddingAllXL = EdgeInsets.all(spacing24);

  static const EdgeInsets paddingH12 = EdgeInsets.symmetric(horizontal: spacing12);
  static const EdgeInsets paddingH16 = EdgeInsets.symmetric(horizontal: spacing16);
  static const EdgeInsets paddingH20 = EdgeInsets.symmetric(horizontal: spacing20);
  static const EdgeInsets paddingH24 = EdgeInsets.symmetric(horizontal: spacing24);

  static const EdgeInsets paddingV4 = EdgeInsets.symmetric(vertical: spacing4);
  static const EdgeInsets paddingV8 = EdgeInsets.symmetric(vertical: spacing8);
  static const EdgeInsets paddingV14 = EdgeInsets.symmetric(vertical: spacing14);
  static const EdgeInsets paddingV24 = EdgeInsets.symmetric(vertical: spacing24);

  /// Standard card / list item margin
  static const EdgeInsets cardMargin = EdgeInsets.symmetric(
    horizontal: spacing16,
    vertical: spacing4,
  );

  /// Standard card inner padding
  static const EdgeInsets cardPadding = EdgeInsets.all(spacing14);

  /// Chip padding
  static const EdgeInsets chipPadding = EdgeInsets.symmetric(
    horizontal: spacing10,
    vertical: spacing4,
  );

  /// Tag chip padding (smaller than chip)
  static const EdgeInsets tagPadding = EdgeInsets.symmetric(
    horizontal: spacing8,
    vertical: spacing3,
  );

  /// Button padding
  static const EdgeInsets buttonPaddingSM = EdgeInsets.symmetric(
    horizontal: spacing12,
    vertical: spacing8,
  );
  static const EdgeInsets buttonPaddingMD = EdgeInsets.symmetric(
    horizontal: spacing24,
    vertical: 13,
  );
  static const EdgeInsets buttonPaddingLG = EdgeInsets.symmetric(
    horizontal: spacing24,
    vertical: spacing14,
  );

  /// Input field content padding
  static const EdgeInsets inputPadding = EdgeInsets.symmetric(
    horizontal: spacing16,
    vertical: spacing14,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // ICON SIZES
  // ═══════════════════════════════════════════════════════════════════════════

  static const double iconXS = 11;
  static const double iconSM = 14;
  static const double iconMD = 16;
  static const double iconBase = 20;
  static const double iconLG = 22;
  static const double iconXL = 24;
  static const double iconXXL = 28;
  static const double icon3XL = 32;
  static const double icon4XL = 36;

  // ═══════════════════════════════════════════════════════════════════════════
  // COMPONENT SIZES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Small icon badge (e.g., note row left icon)
  static const double iconBadgeSM = 44;

  /// Medium icon badge (e.g., overview card icon)
  static const double iconBadgeMD = 44;

  /// Large icon badge (e.g., timeline node, DayWithSelah)
  static const double iconBadgeLG = 56;

  /// Quick action button width
  static const double quickActionWidth = 80;

  /// Navigation bar height. Raised with the label size so a 12px label and a
  /// 22px icon both fit without the destination clipping.
  static const double navBarHeight = 72;

  /// Scroll indicator (e.g., loading spinner)
  static const double spinnerSize = 32;

  // ═══════════════════════════════════════════════════════════════════════════
  // ALPHA / OPACITY VALUES
  // ═══════════════════════════════════════════════════════════════════════════

  static const double alphaSubtle = 0.06;
  static const double alphaLight = 0.08;
  static const double alphaLightMed = 0.10;
  static const double alphaMedLight = 0.12;
  static const double alphaMedium = 0.15;
  static const double alphaMedStrong = 0.18;
  static const double alphaStrong = 0.35;
  static const double alphaHeavy = 0.50;
  static const double alphaText = 0.65;
  static const double alphaTextStrong = 0.85;
  static const double alphaNearlySolid = 0.90;

  // ═══════════════════════════════════════════════════════════════════════════
  // SHADOWS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Subtle shadow for flat cards
  static List<BoxShadow> shadowSM(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.07),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// Standard card shadow
  static List<BoxShadow> shadowMD(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.07),
      blurRadius: 14,
      offset: const Offset(0, 3),
    ),
  ];

  /// Elevated shadow (overview cards, feature cards)
  static List<BoxShadow> shadowLG(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.14),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

  /// Heavy shadow (modals, floating elements)
  static List<BoxShadow> shadowXL(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.18),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  /// Glow shadow (auth screens, logo)
  static List<BoxShadow> shadowGlow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.20),
      blurRadius: 30,
      spreadRadius: 2,
    ),
  ];

  /// Default card shadow (black-based)
  static final List<BoxShadow> cardShadow = shadowMD(Colors.black);

  /// Colored card shadow (pass the card's accent color)
  static List<BoxShadow> coloredCardShadow(Color color) => shadowLG(color);

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION DURATIONS
  // ═══════════════════════════════════════════════════════════════════════════

  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationNormal = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 200);
  static const Duration durationSlow = Duration(milliseconds: 300);
  static const Duration durationVerySlow = Duration(milliseconds: 500);

  /// Press scale for buttons/cards
  static const double pressedScale = 0.97;
  static const double pressedScaleSmall = 0.94;

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT STYLES (standalone, for use outside Theme.of(context))
  // ═══════════════════════════════════════════════════════════════════════════

  /// Display-size heading (e.g., overview card count)
  // ── Note document scale ─────────────────────────────────────────────────
  // One scale for a note's own content, used by both the editor and the
  // read-only view. They had drifted apart: the editor drew headings at
  // 28/24/20 from hardcoded numbers while the reader took them from the
  // theme, where `titleLarge` is 28 and `headlineSmall` was never defined —
  // so it fell back to Material's 24. A heading 2 therefore rendered *larger*
  // than the note's title, and H1 and H2 came out the same size.
  //
  // Sized against the 16px body: big enough to structure a note, small enough
  // that a section heading does not dominate the screen.

  /// The note's own title — above every heading inside it.
  static const TextStyle noteTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle noteHeading1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.3,
  );

  static const TextStyle noteHeading2 = TextStyle(
    fontSize: 19,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    height: 1.3,
  );

  static const TextStyle noteHeading3 = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    height: 1.05,
    letterSpacing: -0.5,
  );

  /// Section heading
  static const TextStyle headingLarge = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.3,
  );

  /// Card/dialog title
  static const TextStyle headingMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Sub-heading (e.g., list section title)
  static const TextStyle headingSmall = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  /// Standard body text. iOS body is 17pt and Android 16sp; 14 sat three
  /// points under the platform norm and set the tone for the whole app.
  static const TextStyle bodyBase = TextStyle(
    fontSize: 16,
    height: 1.5,
  );

  /// Small body text (preview, secondary info)
  static const TextStyle bodySmallStyle = TextStyle(
    fontSize: 14,
    height: 1.4,
  );

  /// Caption / metadata
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Smallest label (tags, chips, badges). 12px is the hard floor — nothing
  /// in the app should be smaller, and the former 10px `micro` styles are gone.
  static const TextStyle tiny = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// Deprecated alias for [tiny], kept so existing call sites keep compiling.
  /// Was 10px, below the readable floor.
  static const TextStyle micro = tiny;

  /// Orange small label — for accent labels and badges.
  static const TextStyle microOrange = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: orange,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENT PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  static const LinearGradient brandGradient = LinearGradient(
    colors: [brandBlue, brandPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient navyGradient = LinearGradient(
    colors: [navyDark, navyMid],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Gradient for overview cards — pass the card's accent color.
  ///
  /// In dark mode the accent is mixed toward [darkSurface] rather than white:
  /// a pastel panel on a near-black page is both visually loud and defeats the
  /// point of dark mode for night reading.
  static LinearGradient cardGradient(Color color, {bool dark = false}) {
    final toward = dark ? darkSurface : Colors.white;
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(color, toward, dark ? 0.80 : 0.80)!,
        Color.lerp(color, toward, dark ? 0.70 : 0.68)!,
      ],
    );
  }

  /// Tinted background for icon badges and quick actions, for the active
  /// theme. See [cardGradient] for why dark mixes toward [darkSurface].
  static Color tintBackground(Color color,
          [double lerp = 0.84, bool dark = false]) =>
      Color.lerp(color, dark ? darkSurface : Colors.white, dark ? 0.80 : lerp)!;

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDER / DIVIDER
  // ═══════════════════════════════════════════════════════════════════════════

  static const double borderWidthThin = 0.6;
  static const double borderWidthDefault = 1.0;
  static const double borderWidthFocused = 1.5;

  /// Standard enabled border color
  static final Color borderColor = Colors.grey.shade200;

  /// Input fill color. White, so a field reads as a distinct surface against
  /// the [scaffoldGray] page rather than blending into it.
  static const Color inputFillColor = Colors.white;

  /// Decoration for an editor that sits inline in a page rather than in a
  /// form — a note's title, a prayer's description.
  ///
  /// The app-wide [InputDecorationTheme] is filled with a visible border,
  /// which is right for a form field and wrong for text that should look like
  /// the content it replaces. Setting `border: InputBorder.none` alone does
  /// not achieve that: `filled`, `enabledBorder` and `focusedBorder` all
  /// still come from the theme, which is why these fields kept a box around
  /// them. Every one has to be cleared.
  static InputDecoration inlineInput({String? hint, Color? hintColorOverride}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: hint == null
          ? null
          : TextStyle(color: hintColorOverride ?? hintColor, fontSize: 16),
      filled: false,
      isDense: true,
      contentPadding: EdgeInsets.zero,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );
  }

  /// Input outline at rest. Clears the 3:1 non-text minimum against both the
  /// white fill (3.29:1) and the page (3.01:1) — a field has to be
  /// recognisable as a field before it is focused.
  static const Color inputBorderColor = Color(0xFF888E9B);

  /// Divider color
  static final Color dividerColor = Colors.grey.shade100;

  /// Hint text color. grey.shade400 was 1.88:1; this clears AA at 4.83:1.
  static const Color hintColor = textMuted;

  /// Unselected / secondary icon color. grey.shade500 was 2.68:1 on white;
  /// gray600 clears AA at 4.61:1.
  static const Color unselectedColor = gray600;

  /// Chevron / subtle action color. grey.shade300 was 1.32:1 on white and
  /// gray500 still only 2.68:1; this clears the 3:1 non-text minimum on both
  /// the surface (3.28:1) and the page (3.00:1) while staying subordinate.
  static const Color chevronColor = Color(0xFF8E8E8E);

  // ═══════════════════════════════════════════════════════════════════════════
  // MATERIAL 3 THEME DATA
  // ═══════════════════════════════════════════════════════════════════════════

  static ThemeData light() {
    const primary = brandBlue;
    const secondary = brandPurple;

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: Colors.white,
        onPrimary: Colors.white,
        onSurface: textDark,
        onSurfaceVariant: textMuted,
        // Set explicitly: widgets read these for fills, dividers and edges,
        // and ColorScheme's own defaults are a differently-tinted grey that
        // nothing here has checked.
        surfaceContainerHigh: containerHigh,
        surfaceContainerHighest: containerHighest,
        outlineVariant: hairlineLight,
        outline: outlineLight,
      ),
      scaffoldBackgroundColor: scaffoldGray,

      // ── Typography ────────────────────────────────────────────────────
      textTheme: const TextTheme(
        titleLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.3,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(fontSize: 17, height: 1.5),
        bodyMedium: TextStyle(fontSize: 16, height: 1.5),
        bodySmall: TextStyle(fontSize: 14, height: 1.4),
        labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),

      // ── Card ──────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius3XL),
        ),
        shadowColor: Colors.black.withValues(alpha: alphaLight),
        surfaceTintColor: Colors.transparent,
      ),

      // ── Navigation Bar (M3) ───────────────────────────────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withValues(alpha: alphaLight),
        elevation: 0,
        height: navBarHeight,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: primary.withValues(alpha: alphaLightMed),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXL),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: iconLG);
          }
          return const IconThemeData(color: unselectedColor, size: iconLG);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
              letterSpacing: 0.1,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: unselectedColor,
            letterSpacing: 0.1,
          );
        }),
      ),

      // ── List Tile ─────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: spacing20, vertical: spacing2),
        minLeadingWidth: 24,
        iconColor: textMuted,
      ),

      // ── Input Decoration ──────────────────────────────────────────────
      // A field must look like a field before it is touched, and must visibly
      // change on focus. Every non-error state was previously BorderSide.none,
      // so inputs were indistinguishable from body text and focus was silent.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFillColor,
        contentPadding: inputPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(
              color: inputBorderColor, width: borderWidthDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(
              color: inputBorderColor, width: borderWidthDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(color: error, width: borderWidthFocused),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 16),
        hintStyle: const TextStyle(color: hintColor, fontSize: 16),
      ),

      // ── Elevated Button ───────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: buttonPaddingMD,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXL),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // ── Floating Action Button ────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // So a screen that sets nothing still gets a readable icon.
        backgroundColor: brandBlue,
        foregroundColor: Colors.white, // 4.86:1 on brandBlue
        elevation: 3,
        focusElevation: 5,
        hoverElevation: 5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius3XL),
        ),
        extendedPadding: buttonPaddingLG,
      ),

      // ── App Bar ───────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldGray,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: textDark),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textDark,
          letterSpacing: -0.2,
        ),
      ),

      // ── Divider ───────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade100,
        thickness: borderWidthDefault,
        space: 0,
      ),

      // ── SnackBar ──────────────────────────────────────────────────────
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: snackBackground,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 15),
        actionTextColor: snackAction,
        behavior: SnackBarBehavior.floating,
      ),

      // ── Chip ──────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: containerHigh,
        selectedColor: primary.withValues(alpha: alphaMedLight),
        padding: chipPadding,
        // Both label colours set explicitly. Left to Material's defaults the
        // selected label resolved against a container role this app never
        // defined, which is how a pale chip ended up with a white label.
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: textDark,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          // The icon accent is only 4.15:1 on the chip's own selected tint —
          // this is the deeper ink tuned for exactly that background.
          color: inkBlue,
        ),
        side: BorderSide(color: hairlineLight),
        showCheckmark: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MATERIAL 3 THEME DATA — DARK
  // ═══════════════════════════════════════════════════════════════════════════

  /// Dark counterpart of [light]. Same spacing, radii and component shapes —
  /// only the surface and foreground tokens differ, so the two themes stay in
  /// step as components change.
  static ThemeData dark() {
    const primary = brandBlueOnDark;
    const secondary = brandPurpleOnDark;
    final base = light();

    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: darkSurface,
        onPrimary: Color(0xFF10203F),
        onSurface: darkTextPrimary,
        onSurfaceVariant: darkTextMuted,
        error: Color(0xFFFFB4AB),
        surfaceContainerHigh: darkContainerHigh,
        surfaceContainerHighest: darkContainerHighest,
        outlineVariant: darkBorder,
        outline: darkCardBorder,
      ),
      scaffoldBackgroundColor: darkScaffold,
      canvasColor: darkSurface,
      dividerColor: darkBorder,

      textTheme: base.textTheme.apply(
        bodyColor: darkTextPrimary,
        displayColor: darkTextPrimary,
      ),

      // A dark card is only 1.09:1 against the dark page, and shadows do not
      // read on a dark ground, so the card edge has to be drawn explicitly or
      // every list dissolves into the background.
      cardTheme: base.cardTheme.copyWith(
        color: darkSurface,
        shadowColor: Colors.black.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius3XL),
          side: const BorderSide(
              color: darkCardBorder, width: borderWidthDefault),
        ),
      ),

      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: darkScaffold,
        iconTheme: const IconThemeData(color: darkTextPrimary),
        titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
          color: darkTextPrimary,
        ),
      ),

      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: darkSurface,
        indicatorColor: primary.withValues(alpha: alphaMedium),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: iconLG);
          }
          return const IconThemeData(color: darkTextMuted, size: iconLG);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? primary : darkTextMuted,
            letterSpacing: 0.1,
          );
        }),
      ),

      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: darkSurfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(
              color: darkInputBorder, width: borderWidthDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(
              color: darkInputBorder, width: borderWidthDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        labelStyle: const TextStyle(fontSize: 16, color: darkTextMuted),
        hintStyle: const TextStyle(fontSize: 16, color: darkTextMuted),
      ),

      dividerTheme: base.dividerTheme.copyWith(color: darkBorder),

      chipTheme: base.chipTheme.copyWith(
        backgroundColor: darkSurfaceRaised,
        selectedColor: primary.withValues(alpha: alphaMedium),
        // Dark needs its own label colours: the light theme's near-black
        // would be invisible on a raised dark chip.
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
          color: darkTextPrimary,
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: brandBlueOnDark,
        ),
        side: const BorderSide(color: darkBorder),
      ),

      listTileTheme: base.listTileTheme.copyWith(iconColor: darkTextMuted),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: darkSurface,
      ),
      dialogTheme: base.dialogTheme.copyWith(backgroundColor: darkSurface),
    );
  }
}
