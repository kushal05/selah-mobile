import 'package:flutter/material.dart';

/// Displays a scripture verse of the day with fade-in animation.
///
/// Scriptures are stored locally. Rotates daily based on day of year.
class DailyScriptureWidget extends StatefulWidget {
  const DailyScriptureWidget({super.key});

  @override
  State<DailyScriptureWidget> createState() => DailyScriptureWidgetState();
}

class DailyScriptureWidgetState extends State<DailyScriptureWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
  }

  /// Start the fade-in animation. Called externally by entrance animation.
  void fadeIn() {
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scripture = _getScriptureOfTheDay();

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Text(
              '"${scripture.text}"',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.white.withValues(alpha: 0.7),
                height: 1.5,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              scripture.reference,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  _Scripture _getScriptureOfTheDay() {
    final dayOfYear = DateTime.now().difference(
      DateTime(DateTime.now().year, 1, 1),
    ).inDays;
    return _scriptures[dayOfYear % _scriptures.length];
  }
}

class _Scripture {
  final String text;
  final String reference;
  const _Scripture(this.text, this.reference);
}

const _scriptures = [
  _Scripture(
    'The Lord is my shepherd; I shall not want.',
    'Psalm 23:1',
  ),
  _Scripture(
    'Be still, and know that I am God.',
    'Psalm 46:10',
  ),
  _Scripture(
    'Trust in the Lord with all your heart, and lean not on your own understanding.',
    'Proverbs 3:5',
  ),
  _Scripture(
    'For I know the plans I have for you, declares the Lord, plans to prosper you and not to harm you.',
    'Jeremiah 29:11',
  ),
  _Scripture(
    'I can do all things through Christ who strengthens me.',
    'Philippians 4:13',
  ),
  _Scripture(
    'The Lord is my light and my salvation; whom shall I fear?',
    'Psalm 27:1',
  ),
  _Scripture(
    'Cast all your anxiety on him because he cares for you.',
    '1 Peter 5:7',
  ),
  _Scripture(
    'But those who hope in the Lord will renew their strength.',
    'Isaiah 40:31',
  ),
  _Scripture(
    'God is our refuge and strength, an ever-present help in trouble.',
    'Psalm 46:1',
  ),
  _Scripture(
    'Come to me, all you who are weary and burdened, and I will give you rest.',
    'Matthew 11:28',
  ),
  _Scripture(
    'The peace of God, which transcends all understanding, will guard your hearts and your minds.',
    'Philippians 4:7',
  ),
  _Scripture(
    'Delight yourself in the Lord, and he will give you the desires of your heart.',
    'Psalm 37:4',
  ),
  _Scripture(
    'He has made everything beautiful in its time.',
    'Ecclesiastes 3:11',
  ),
  _Scripture(
    'Your word is a lamp for my feet, a light on my path.',
    'Psalm 119:105',
  ),
  _Scripture(
    'Do not be anxious about anything, but in every situation, by prayer and petition, present your requests to God.',
    'Philippians 4:6',
  ),
  _Scripture(
    'Great is thy faithfulness, O Lord my God.',
    'Lamentations 3:23',
  ),
  _Scripture(
    'The Lord bless you and keep you; the Lord make his face shine on you.',
    'Numbers 6:24-25',
  ),
  _Scripture(
    'In all your ways submit to him, and he will make your paths straight.',
    'Proverbs 3:6',
  ),
  _Scripture(
    'And we know that in all things God works for the good of those who love him.',
    'Romans 8:28',
  ),
  _Scripture(
    'The name of the Lord is a fortified tower; the righteous run to it and are safe.',
    'Proverbs 18:10',
  ),
  _Scripture(
    'Be strong and courageous. Do not be afraid; do not be discouraged.',
    'Joshua 1:9',
  ),
  _Scripture(
    'Create in me a pure heart, O God, and renew a steadfast spirit within me.',
    'Psalm 51:10',
  ),
  _Scripture(
    'The joy of the Lord is your strength.',
    'Nehemiah 8:10',
  ),
  _Scripture(
    'Draw near to God, and he will draw near to you.',
    'James 4:8',
  ),
  _Scripture(
    'Let us not become weary in doing good, for at the proper time we will reap a harvest.',
    'Galatians 6:9',
  ),
  _Scripture(
    'He restores my soul. He leads me in paths of righteousness for his name\'s sake.',
    'Psalm 23:3',
  ),
  _Scripture(
    'Wait for the Lord; be strong and take heart and wait for the Lord.',
    'Psalm 27:14',
  ),
  _Scripture(
    'The Lord is gracious and compassionate, slow to anger and rich in love.',
    'Psalm 145:8',
  ),
  _Scripture(
    'Every good and perfect gift is from above, coming down from the Father of the heavenly lights.',
    'James 1:17',
  ),
  _Scripture(
    'If God is for us, who can be against us?',
    'Romans 8:31',
  ),
  _Scripture(
    'Rejoice always, pray continually, give thanks in all circumstances.',
    '1 Thessalonians 5:16-18',
  ),
];
