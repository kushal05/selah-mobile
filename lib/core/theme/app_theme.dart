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
  static const Color textMuted = Color(0xFF6B7280);

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

  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFF5A623);
  static const Color info = skyBlue;

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

  /// Navigation bar height
  static const double navBarHeight = 64;

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
    fontSize: 15,
    fontWeight: FontWeight.w600,
  );

  /// Standard body text
  static const TextStyle bodyBase = TextStyle(
    fontSize: 14,
    height: 1.5,
  );

  /// Small body text (preview, secondary info)
  static const TextStyle bodySmallStyle = TextStyle(
    fontSize: 13,
    height: 1.4,
  );

  /// Caption / metadata
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  /// Tiny label (tags, chips, badges)
  static const TextStyle tiny = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  /// Micro text (phone mockup screens only — 10px)
  static const TextStyle micro = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
  );
  /// Orange micro text — for small accent labels and badges.
  static const TextStyle microOrange = TextStyle(
    fontSize: 10,
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

  /// Gradient for overview cards — pass the card's accent color
  static LinearGradient cardGradient(Color color) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color.lerp(color, Colors.white, 0.80)!,
      Color.lerp(color, Colors.white, 0.68)!,
    ],
  );

  /// Light tint background for icon badges
  static Color tintBackground(Color color, [double lerp = 0.84]) =>
      Color.lerp(color, Colors.white, lerp)!;

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDER / DIVIDER
  // ═══════════════════════════════════════════════════════════════════════════

  static const double borderWidthThin = 0.6;
  static const double borderWidthDefault = 1.0;
  static const double borderWidthFocused = 1.5;

  /// Standard enabled border color
  static final Color borderColor = Colors.grey.shade200;

  /// Input fill color
  static final Color inputFillColor = Colors.grey.shade50;

  /// Divider color
  static final Color dividerColor = Colors.grey.shade100;

  /// Hint text color
  static final Color hintColor = Colors.grey.shade400;

  /// Unselected / secondary icon color
  static final Color unselectedColor = Colors.grey.shade500;

  /// Chevron / subtle action color
  static final Color chevronColor = Colors.grey.shade300;

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
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(fontSize: 16, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, height: 1.5),
        bodySmall: TextStyle(fontSize: 13, height: 1.4),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
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
          return IconThemeData(color: Colors.grey.shade500, size: iconLG);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: primary,
              letterSpacing: 0.1,
            );
          }
          return TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade500,
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
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding: inputPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(color: error, width: borderWidthDefault),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXL),
          borderSide: const BorderSide(color: error, width: borderWidthFocused),
        ),
        labelStyle: const TextStyle(fontSize: 14),
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
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
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      // ── Floating Action Button ────────────────────────────────────────
      floatingActionButtonTheme: FloatingActionButtonThemeData(
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

      // ── Chip ──────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: Colors.grey.shade100,
        selectedColor: primary.withValues(alpha: alphaMedLight),
        padding: chipPadding,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
        ),
      ),
    );
  }
}
