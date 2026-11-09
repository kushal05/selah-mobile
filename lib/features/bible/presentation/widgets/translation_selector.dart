import 'package:flutter/material.dart';

/// Compact translation selector dropdown for Bible chapter views.
///
/// Shows the current translation code (e.g., "KJV") and opens a
/// popup menu with all available translations when tapped.
///
/// When [onManage] is set, a tap calls it instead (to open the version
/// downloader) and the switcher menu moves to a long-press.
class TranslationSelector extends StatelessWidget {
  final String currentTranslation;
  final List<String> availableTranslations;
  final ValueChanged<String> onChanged;
  final VoidCallback? onManage;

  const TranslationSelector({
    super.key,
    required this.currentTranslation,
    required this.availableTranslations,
    required this.onChanged,
    this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    List<PopupMenuEntry<String>> items() => availableTranslations
        .map(
          (t) => PopupMenuItem(
            value: t,
            child: Row(
              children: [
                Expanded(child: Text(t)),
                if (t == currentTranslation)
                  Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
              ],
            ),
          ),
        )
        .toList();

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentTranslation,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.arrow_drop_down,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ],
      ),
    );

    if (onManage == null) {
      return PopupMenuButton<String>(
        onSelected: onChanged,
        initialValue: currentTranslation,
        itemBuilder: (context) => items(),
        child: pill,
      );
    }

    return Builder(
      builder: (context) => Semantics(
        button: true,
        onLongPress: () => _showSwitcher(context, items()),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onManage,
          onLongPress: () => _showSwitcher(context, items()),
          child: pill,
        ),
      ),
    );
  }

  Future<void> _showSwitcher(
    BuildContext context,
    List<PopupMenuEntry<String>> items,
  ) async {
    final box = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      topLeft & box.size,
      Offset.zero & overlay.size,
    );
    final picked = await showMenu<String>(
      context: context,
      position: position,
      initialValue: currentTranslation,
      items: items,
    );
    if (picked != null) onChanged(picked);
  }
}
