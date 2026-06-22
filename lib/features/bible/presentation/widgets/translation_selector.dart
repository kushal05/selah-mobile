import 'package:flutter/material.dart';

/// Compact translation selector dropdown for Bible chapter views.
///
/// Shows the current translation code (e.g., "KJV") and opens a
/// popup menu with all available translations when tapped.
class TranslationSelector extends StatelessWidget {
  final String currentTranslation;
  final List<String> availableTranslations;
  final ValueChanged<String> onChanged;

  const TranslationSelector({
    super.key,
    required this.currentTranslation,
    required this.availableTranslations,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopupMenuButton<String>(
      onSelected: onChanged,
      initialValue: currentTranslation,
      itemBuilder: (context) => availableTranslations
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
          .toList(),
      child: Container(
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
                fontSize: 13,
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
      ),
    );
  }
}
