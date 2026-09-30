import 'package:flutter/material.dart';
import '../../../core/theme/theme_colors.dart';

/// Displays a search results section with a title
class SearchSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const SearchSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          // Uppercased here rather than in the string catalogue, as
          // SectionLabel already does. An ALL CAPS value gives a translator a
          // second copy of a word to keep in step with the first, in a form
          // that is wrong in the languages where case does not work this way.
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.mutedText,
              letterSpacing: 0.5,
            ),
          ),
        ),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }
}
