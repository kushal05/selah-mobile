/// Suggested prayer templates for new users.
///
/// Shown on the dashboard when the user has 0 active prayers.
class SuggestedPrayer {
  final String title;
  final String description;

  const SuggestedPrayer({required this.title, required this.description});
}

const suggestedPrayers = [
  SuggestedPrayer(
    title: 'Daily Gratitude',
    description:
        'Thank God for His blessings today — health, family, provision, and grace.',
  ),
  SuggestedPrayer(
    title: 'Wisdom & Guidance',
    description:
        'Ask the Lord for wisdom in decisions, direction for the day, and clarity of purpose.',
  ),
  SuggestedPrayer(
    title: 'Family & Loved Ones',
    description:
        'Pray for the protection, health, and spiritual growth of your family members.',
  ),
  SuggestedPrayer(
    title: 'Strength in Trials',
    description:
        'Ask God for endurance and peace during difficult seasons and challenges.',
  ),
  SuggestedPrayer(
    title: 'Church & Community',
    description:
        'Lift up your church leaders, fellowship groups, and the unity of believers.',
  ),
  SuggestedPrayer(
    title: 'The Lost & Unreached',
    description:
        'Pray for those who don\'t yet know Christ — for open hearts and divine encounters.',
  ),
];
