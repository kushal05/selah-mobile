import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/sync/providers/sync_providers.dart';
import '../../../../core/sync/services/public_share_api_service.dart';
import '../../../../l10n/l10n.dart';
import '../../../../shared/widgets/error_state.dart';

/// Unauthenticated read-only viewer for a public-link shared note.
///
/// Reached via the `/share/:token` deeplink. Loads a snapshot from the
/// public API on open; manual refresh is the default. If the user opts
/// in with the toggle, a 60s polling timer refreshes in place so live
/// edits by the owner appear without a pull-to-refresh.
class PublicNoteViewerScreen extends ConsumerStatefulWidget {
  final String token;
  const PublicNoteViewerScreen({super.key, required this.token});

  @override
  ConsumerState<PublicNoteViewerScreen> createState() =>
      _PublicNoteViewerScreenState();
}

class _PublicNoteViewerScreenState
    extends ConsumerState<PublicNoteViewerScreen> {
  PublicNoteSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;
  bool _pollingEnabled = false;
  Timer? _pollTimer;

  static const Duration _pollInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(publicShareApiServiceProvider);
      final snap = await api.resolveNote(widget.token);
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _togglePolling(bool enabled) {
    setState(() => _pollingEnabled = enabled);
    _pollTimer?.cancel();
    if (enabled) {
      _pollTimer = Timer.periodic(_pollInterval, (_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n(context).sharedNote),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n(context).refresh,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _snapshot == null) {
      return ErrorState(error: _error!, onRetry: _load);
    }
    final snap = _snapshot!;
    final title = (snap.note['title'] as String?) ?? 'Untitled';
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _ViewOnlyBanner(
          fetchedAt: snap.fetchedAt,
          pollingEnabled: _pollingEnabled,
          onPollToggle: _togglePolling,
          pollInterval: _pollInterval,
        ),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 12),
        ...snap.blocks.map((b) => _BlockView(block: b)),
      ],
    );
  }
}

class _ViewOnlyBanner extends StatelessWidget {
  final int fetchedAt;
  final bool pollingEnabled;
  final ValueChanged<bool> onPollToggle;
  final Duration pollInterval;

  const _ViewOnlyBanner({
    required this.fetchedAt,
    required this.pollingEnabled,
    required this.onPollToggle,
    required this.pollInterval,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined, size: 18),
              const SizedBox(width: 6),
              Text(l10n(context).readOnly,
                  style: theme.textTheme.labelLarge),
              const Spacer(),
              Text(
                'Updated ${_relative(fetchedAt)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Auto-refresh every ${pollInterval.inSeconds}s',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Switch(value: pollingEnabled, onChanged: onPollToggle),
            ],
          ),
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  final Map<String, dynamic> block;
  const _BlockView({required this.block});

  @override
  Widget build(BuildContext context) {
    final text = (block['plainText'] as String?) ??
        (block['text'] as String?) ??
        (block['content'] as String?) ??
        '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}




String _relative(int ms) {
  final diff = DateTime.now().millisecondsSinceEpoch - ms;
  if (diff < 60 * 1000) return 'just now';
  if (diff < 60 * 60 * 1000) return '${diff ~/ 60000}m ago';
  return '${diff ~/ 3600000}h ago';
}
