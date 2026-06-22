import 'package:flutter/material.dart';

/// Whitelist of icons the backend may reference by name.
///
/// Flutter release builds tree-shake `MaterialIcons` down to the codepoints
/// referenced by literal `Icons.x` in source. An arbitrary icon name arriving
/// from the server therefore has no glyph and renders blank. This registry is
/// the fix: every value is a literal `Icons.x`, so all referenced glyphs are
/// retained, and config can only pick from these known names.
///
/// Adding a new icon to a config requires adding it here first and shipping a
/// build — the icon *vocabulary* is release-gated, but icon *selection* is not.
const Map<String, IconData> kIconRegistry = {
  // Navigation / core
  'home': Icons.home_rounded,
  'description': Icons.description_rounded,
  'notes': Icons.description_rounded,
  'favorite': Icons.favorite_rounded,
  'menu_book': Icons.menu_book_rounded,
  'bookmark': Icons.bookmark_rounded,
  'music_note': Icons.music_note_rounded,
  'groups': Icons.groups_rounded,
  'people': Icons.people_rounded,
  'people_outline': Icons.people_outline,
  'search': Icons.search_rounded,

  // Onboarding / decorative
  'auto_awesome': Icons.auto_awesome_rounded,
  'spa': Icons.spa_outlined,
  'light_mode': Icons.light_mode_outlined,
  'edit_note': Icons.edit_note_rounded,
  'bookmark_add': Icons.bookmark_add_outlined,
  'star_outline': Icons.star_outline_rounded,
  'church': Icons.church_rounded,
  'handshake': Icons.handshake_outlined,

  // Quick actions
  'add_circle_outline': Icons.add_circle_outline_rounded,
  'wb_sunny': Icons.wb_sunny_outlined,

  // Settings
  'badge': Icons.badge_outlined,
  'notifications': Icons.notifications_outlined,
  'feedback': Icons.feedback_outlined,
  'cloud_sync': Icons.cloud_sync_outlined,
  'label': Icons.label_outline,
  'delete': Icons.delete_outline,
  'file_download': Icons.file_download_outlined,
  'picture_as_pdf': Icons.picture_as_pdf_outlined,
  'cloud_upload': Icons.cloud_upload_outlined,
  'history': Icons.history_outlined,
  'map': Icons.map_outlined,
  'system_update': Icons.system_update_alt_outlined,
  'info': Icons.info_outline,
  'logout': Icons.logout_rounded,
  'settings': Icons.settings_outlined,

  // Generic fallbacks
  'circle': Icons.circle_outlined,
  'star': Icons.star_rounded,
  'flag': Icons.flag_outlined,
};

/// Resolves an icon name to its [IconData], falling back to a safe default for
/// unknown / null names so a bad config value can never crash or blank the UI.
IconData iconFor(String? name, {IconData fallback = Icons.circle_outlined}) {
  if (name == null) return fallback;
  return kIconRegistry[name] ?? fallback;
}

/// Parses a `#RRGGBB` or `#AARRGGBB` hex string to a [Color]. Returns null on
/// any malformed input so the caller can fall back to its in-code colour.
Color? colorFromHex(String? hex) {
  if (hex == null) return null;
  var s = hex.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s'; // assume opaque
  if (s.length != 8) return null;
  final value = int.tryParse(s, radix: 16);
  if (value == null) return null;
  return Color(value);
}
