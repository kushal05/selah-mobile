import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/services/public_share_api_service.dart';
import '../../../../l10n/l10n.dart';

/// Opens `https://selahapp.in/social/share/:shareCode`.
///
/// Who sees what:
/// - A prayer already on this device (the author's own, or one they
///   collaborate on) opens the normal prayer screen, whose permission checks
///   decide what they can change.
/// - Anyone else, signed in or not, sees a read-only preview fetched from the
///   public endpoint: no edit, log, update or sharing controls.
class ShareCodeScreen extends ConsumerStatefulWidget {
  final String shareCode;

  const ShareCodeScreen({super.key, required this.shareCode});

  @override
  ConsumerState<ShareCodeScreen> createState() => _ShareCodeScreenState();
}

class _ShareCodeScreenState extends ConsumerState<ShareCodeScreen> {
  PublicPrayerPreview? _preview;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _failed = false;
    });

    // Step 1: is this prayer already ours? The device remembers the codes of
    // prayers it shared, so the author gets in with no network. Otherwise ask
    // the server (needs a signed-in session). Every failure here just falls
    // through to the preview.
    final prayerId = await _ownPrayerId();
    if (!mounted) return;
    if (prayerId != null) {
      context.go('/prayers/$prayerId');
      return;
    }

    // Step 2: a read-only preview for everyone else.
    try {
      final preview = await ref
          .read(publicShareApiServiceProvider)
          .resolvePrayer(widget.shareCode);
      if (!mounted) return;
      if (preview == null) {
        _showUnavailable();
        return;
      }
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  /// The id of the prayer this code opens, if that prayer is on this device.
  Future<String?> _ownPrayerId() async {
    try {
      final prayers = ref.read(prayerRepositoryProvider);
      var prayerId =
          await ref.read(localShareCodeRepositoryProvider).prayerIdFor(widget.shareCode);
      prayerId ??= await ref
          .read(sharedPrayerApiServiceProvider)
          .lookupShareCode(widget.shareCode);
      if (prayerId == null) return null;
      final local = await prayers.getPrayerById(prayerId);
      return (local != null && local.deleted == 0) ? prayerId : null;
    } catch (_) {
      return null;
    }
  }

  void _showUnavailable() {
    setState(() => _loading = false);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n(dialogContext).linkUnavailable),
        content: Text(l10n(dialogContext).sharedPrayerLinkInvalid),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (mounted) context.go('/');
            },
            child: Text(l10n(dialogContext).goBack),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    if (preview != null) return _PrayerPreview(preview: preview);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: _failed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n(context).sharedPrayerOpenFailed, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _resolve,
                      child: Text(l10n(context).retry),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading) const CircularProgressIndicator(),
                    if (_loading) const SizedBox(height: 16),
                    if (_loading) Text(l10n(context).openingSharedPrayer),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Read-only: text only, nothing editable.
class _PrayerPreview extends StatelessWidget {
  final PublicPrayerPreview preview;

  const _PrayerPreview({required this.preview});

  @override
  Widget build(BuildContext context) {
    final t = l10n(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.sharedPrayerViewOnlyTitle),
        leading: IconButton(
          tooltip: t.close,
          icon: const Icon(Icons.close),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.visibility_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t.sharedPrayerViewOnlyNotice)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (preview.sharedByName != null &&
                preview.sharedByName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  t.sharedPrayerSharedBy(preview.sharedByName!),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            SelectableText(preview.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (preview.category.isNotEmpty)
                  Chip(label: Text(preview.category)),
                if (preview.isAnswered)
                  Chip(label: Text(t.answered))
                else if (preview.status.isNotEmpty)
                  Chip(label: Text(preview.status)),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(preview.content, style: theme.textTheme.bodyLarge),
            if (preview.answeredAt != null) ...[
              const SizedBox(height: 16),
              Text(
                t.sharedPrayerAnsweredOn(DateFormat.yMMMd().format(
                    DateTime.fromMillisecondsSinceEpoch(preview.answeredAt!))),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
