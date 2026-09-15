import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/providers/motion_preferences.dart';
import '../../../../l10n/l10n.dart';
import '../../../prayers/presentation/widgets/quick_prayer_sheet.dart';

/// Displays the daily focus prayer card on the home dashboard.
/// Uses a branded blue gradient with glass-style action button.
class DailyFocusCard extends ConsumerWidget {
  const DailyFocusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayersAsync = ref.watch(activePrayersStreamProvider);

    return prayersAsync.when(
      loading: () => _buildCard(context, null, null),
      error: (_, _) => _buildCard(context, null, null),
      data: (prayers) {
        if (prayers.isEmpty) return _buildCard(context, null, null);
        // One clock read, not three. The old expression called DateTime.now()
        // twice and could straddle midnight or a new year between them, which
        // would pick a different prayer than the one it computed the day for.
        final now = DateTime.now();
        final dayOfYear = now.difference(DateTime(now.year)).inDays;
        final prayer = prayers[dayOfYear % prayers.length];
        return _buildCard(context, prayer.title, prayer.id);
      },
    );
  }

  Widget _buildCard(
      BuildContext context, String? prayerTitle, String? prayerId) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.brandBlue, AppTheme.gradientEnd],
        ),
        borderRadius: AppTheme.borderRadius4XL,
        boxShadow: AppTheme.shadowXL(AppTheme.brandBlue),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Decorative circles (4, clean positions)
          Positioned(
            top: -30,
            right: -30,
            child: _Circle(size: 120, alpha: AppTheme.alphaLight),
          ),
          Positioned(
            bottom: -20,
            left: -20,
            child: _Circle(size: 80, alpha: AppTheme.alphaSubtle),
          ),
          Positioned(
            top: 50,
            right: 40,
            child: _Circle(size: 50, alpha: AppTheme.alphaSubtle),
          ),
          Positioned(
            bottom: 50,
            right: -10,
            child: _Circle(size: 70, alpha: 0.05),
          ),

          // Content
          Padding(
            padding: AppTheme.paddingAllLG,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n(context).dailyFocus,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: AppTheme.tiny.fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: AppTheme.spacing8),
                Text(
                  prayerTitle ?? 'No active prayers',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  prayerTitle != null
                      ? 'Scheduled for today'
                      : 'Add a prayer to get started',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: AppTheme.alphaText),
                    fontSize: AppTheme.bodySmallStyle.fontSize,
                  ),
                ),
                const SizedBox(height: 18),
                _GlassActionButton(
                  label: prayerId != null ? 'Open Prayer' : 'Add Prayer',
                  // push keeps Home underneath, so Back returns here; and
                  // the empty case opens the quick sheet rather than the long
                  // form, matching every other 'add prayer' entry point.
                  onPressed: prayerId != null
                      ? () => context.push('/prayers/$prayerId')
                      : () => showQuickPrayerSheet(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle translucent circle used as background decoration.
class _Circle extends StatelessWidget {
  final double size;
  final double alpha;

  const _Circle({required this.size, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

/// Glass-style button matching the auth screen GlassButton aesthetic.
class _GlassActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _GlassActionButton({required this.label, required this.onPressed});

  @override
  State<_GlassActionButton> createState() => _GlassActionButtonState();
}

class _GlassActionButtonState extends State<_GlassActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
      // The action lives on onTap, not onTapUp: only onTap contributes a tap
      // action to the semantics tree, so an onTapUp-only control is inert to
      // TalkBack and VoiceOver. onTapUp still resets the press animation.
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? context.pressScale(0.96) : 1.0,
        duration: context.motion(AppTheme.durationFast),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: AppTheme.spacing20, vertical: AppTheme.spacing10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: AppTheme.alphaMedStrong),
            borderRadius: AppTheme.borderRadiusXL,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.30),
              width: 0.8,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppTheme.bodySmallStyle.fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    ),
    );
  }
}
