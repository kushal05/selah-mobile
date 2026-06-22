import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/sync/providers/sync_providers.dart';

/// Resolves an incoming share-code deep link and navigates to the prayer.
///
/// Opened when the user taps `https://selahapp.in/social/share/:shareCode`.
/// Shows a loading indicator while the code is resolved, then either:
/// - navigates to the prayer detail screen, or
/// - shows an error if the code is expired / not found.
class ShareCodeScreen extends ConsumerStatefulWidget {
  final String shareCode;

  const ShareCodeScreen({super.key, required this.shareCode});

  @override
  ConsumerState<ShareCodeScreen> createState() => _ShareCodeScreenState();
}

class _ShareCodeScreenState extends ConsumerState<ShareCodeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    try {
      final api = ref.read(sharedPrayerApiServiceProvider);
      final prayerId = await api.lookupShareCode(widget.shareCode);

      if (!mounted) return;

      if (prayerId == null) {
        _showError('This share link is no longer valid.');
        return;
      }

      // Replace this loading screen with the prayer detail.
      context.go('/prayers/$prayerId');
    } catch (e) {
      if (!mounted) return;
      _showError('Could not open the shared prayer. Please try again.');
    }
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Link Unavailable'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (mounted) context.go('/social');
            },
            child: const Text('Go Back'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Opening shared prayer…'),
          ],
        ),
      ),
    );
  }
}
