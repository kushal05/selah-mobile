import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/bible_version_api_service.dart';
import '../../domain/models/bible_version_info.dart';
import '../providers/bible_providers.dart';

/// First-launch Bible setup screen.
///
/// Shown when the Bible database has not been initialised yet (no translations
/// downloaded).  Fetches the version list from the server, pre-selects NKJV
/// as the default, and lets the user choose additional translations before
/// downloading.
///
/// After the user taps "Get Started", the selected versions are downloaded in
/// order and the screen is dismissed.  The first selected version's .db file
/// becomes the main bible.db; subsequent ones are merged in.
class BibleVersionOnboardingScreen extends ConsumerStatefulWidget {
  /// Called after all selected downloads complete successfully.
  final VoidCallback onComplete;

  const BibleVersionOnboardingScreen({super.key, required this.onComplete});

  @override
  ConsumerState<BibleVersionOnboardingScreen> createState() =>
      _BibleVersionOnboardingScreenState();
}

class _BibleVersionOnboardingScreenState
    extends ConsumerState<BibleVersionOnboardingScreen> {
  static const _defaultCode = kDefaultBibleVersionCode;

  List<BibleVersionDto> _available = [];
  final Set<String> _selected = {_defaultCode};
  String _defaultSelection = _defaultCode;
  bool _loading = true;
  String? _fetchError;

  // code → progress (0.0–1.0), null = not started/complete
  final Map<String, double?> _progress = {};
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _fetchVersions();
  }

  Future<void> _fetchVersions() async {
    try {
      final api = ref.read(bibleVersionApiServiceProvider);
      final versions = await api.getVersions();
      if (mounted) {
        setState(() {
          _available = versions;
          // Pre-select the server-designated default if present.
          final serverDefault =
              versions.firstWhere((v) => v.isDefault, orElse: () {
            return versions.isNotEmpty
                ? versions.first
                : BibleVersionDto(
                    code: _defaultCode,
                    name: 'New King James Version',
                    downloadUrl: '',
                    isDefault: true,
                    approximateSizeMb: 8,
                    sortOrder: 0,
                  );
          });
          _defaultSelection = serverDefault.code;
          _selected.clear();
          _selected.add(_defaultSelection);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchError = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _startDownloads() async {
    if (_selected.isEmpty) return;
    setState(() => _downloading = true);

    // Put the default first so it initialises bible.db.
    final ordered = [
      ..._selected.where((c) => c == _defaultSelection),
      ..._selected.where((c) => c != _defaultSelection),
    ];

    final dbService = ref.read(bibleDatabaseServiceProvider);
    final repo = ref.read(bibleVersionStateRepositoryProvider);

    // Persist the registry + set the chosen default.
    await repo.upsertFromServer(_available);
    await repo.setDefault(_defaultSelection);

    for (final code in ordered) {
      final info = _available.firstWhere((v) => v.code == code);
      setState(() => _progress[code] = 0.0);
      try {
        if (!dbService.isOpen) {
          await dbService.download(
            info.downloadUrl,
            onProgress: (p) {
              if (mounted) setState(() => _progress[code] = p);
            },
          );
        } else {
          await dbService.downloadVersion(
            info.code,
            info.downloadUrl,
            onProgress: (p) {
              if (mounted) setState(() => _progress[code] = p);
            },
          );
        }
        if (mounted) setState(() => _progress.remove(code));
      } catch (e) {
        if (mounted) {
          setState(() => _progress.remove(code));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Download failed for ${info.name}.'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      }
    }

    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldGray,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppTheme.spacing16),
              Icon(Icons.menu_book_rounded,
                  size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: AppTheme.spacing16),
              Text('Choose Bible Versions',
                  style: AppTheme.headingLarge
                      .copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppTheme.spacing8),
              Text(
                'Select the translations you want to download. '
                'NKJV is set as your default — you can change this any time in settings.',
                style: AppTheme.bodyBase
                    .copyWith(color: AppTheme.unselectedColor),
              ),
              const SizedBox(height: AppTheme.spacing24),
              Expanded(child: _buildBody(theme)),
              const SizedBox(height: AppTheme.spacing16),
              _buildFooter(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fetchError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Could not load versions.',
                style: AppTheme.bodyBase
                    .copyWith(color: AppTheme.unselectedColor)),
            const SizedBox(height: AppTheme.spacing12),
            FilledButton.tonal(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _fetchError = null;
                });
                _fetchVersions();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _available.length,
      separatorBuilder: (_, _) => Divider(
          height: 1, thickness: 0.5, color: AppTheme.dividerColor),
      itemBuilder: (_, i) {
        final v = _available[i];
        final isSelected = _selected.contains(v.code);
        final isDefault = v.code == _defaultSelection;
        final progress = _progress[v.code];

        return InkWell(
          onTap: _downloading
              ? null
              : () {
                  setState(() {
                    if (isDefault) return; // default can't be deselected
                    if (isSelected) {
                      _selected.remove(v.code);
                    } else {
                      _selected.add(v.code);
                    }
                  });
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing4,
                vertical: AppTheme.spacing12),
            child: Row(
              children: [
                Checkbox(
                  value: isSelected,
                  onChanged: _downloading || isDefault
                      ? null
                      : (val) => setState(() {
                            if (val == true) {
                              _selected.add(v.code);
                            } else {
                              _selected.remove(v.code);
                            }
                          }),
                ),
                const SizedBox(width: AppTheme.spacing8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(v.name,
                              style: AppTheme.bodyBase.copyWith(
                                  fontWeight: FontWeight.w500)),
                          if (isDefault) ...[
                            const SizedBox(width: AppTheme.spacing6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Default',
                                  style: AppTheme.caption.copyWith(
                                    color: theme.colorScheme
                                        .onPrimaryContainer,
                                    fontWeight: FontWeight.w600,
                                  )),
                            ),
                          ],
                        ],
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: AppTheme.spacing4),
                        LinearProgressIndicator(
                          value: progress > 0 ? progress : null,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        Text(
                          progress > 0
                              ? '${(progress * 100).toStringAsFixed(0)}%'
                              : 'Downloading…',
                          style: AppTheme.caption.copyWith(
                              color: AppTheme.unselectedColor),
                        ),
                      ] else
                        Text('~${v.approximateSizeMb} MB',
                            style: AppTheme.caption.copyWith(
                                color: AppTheme.unselectedColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(ThemeData theme) {
    if (_downloading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: Text('Downloading selected versions…'),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: _selected.isEmpty || _loading ? null : _startDownloads,
        child: Text(
          _selected.length == 1
              ? 'Download $_defaultCode & Get Started'
              : 'Download ${_selected.length} versions & Get Started',
        ),
      ),
    );
  }
}
