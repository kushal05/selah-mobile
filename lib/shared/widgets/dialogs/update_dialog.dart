import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/app_update_service.dart';

/// Shows an update dialog — non-dismissible for forced updates, dismissible
/// for optional ones.
///
/// On Android with a direct APK URL, the dialog handles download + install.
/// On iOS, it opens the App Store URL.
class UpdateDialog extends StatefulWidget {
  final AppUpdateResult result;
  final AppUpdateService service;

  const UpdateDialog._({required this.result, required this.service});

  static Future<void> show(
    BuildContext context,
    AppUpdateResult result,
    AppUpdateService service,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !result.isForced,
      builder: (_) => UpdateDialog._(result: result, service: service),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  StreamSubscription<DownloadProgress>? _sub;
  DownloadProgress? _progress;
  bool _downloading = false;

  /// Path to the already-downloaded APK. Retained so that if the user hits a
  /// permission error and then grants it, we can retry the install without
  /// re-downloading the entire file.
  String? _completedApkPath;

  /// True when the system returned INSTALL_PERMISSION_REQUIRED. The settings
  /// page has been opened; the user just needs to toggle the permission and
  /// tap "Retry Install".
  bool _needsPermission = false;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = null;
      _needsPermission = false;
      _completedApkPath = null;
    });

    _sub = widget.service
        .downloadApk(widget.result.apkUrl)
        .listen((progress) async {
      if (!mounted) return;
      setState(() => _progress = progress);

      if (progress.isDone) {
        _sub?.cancel();
        _completedApkPath = progress.completedPath;
        await _triggerInstall(progress.completedPath!);
      }
    });
  }

  /// Calls the native installer. Handles two error cases distinctly:
  /// - INSTALL_PERMISSION_REQUIRED: settings page was already opened by
  ///   native code; show a prompt and a "Retry Install" button.
  /// - Anything else: surface as a download-style error with a full Retry.
  Future<void> _triggerInstall(String path) async {
    try {
      await widget.service.installApk(path);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (e.code == 'INSTALL_PERMISSION_REQUIRED') {
        // Download is done — we're no longer "downloading", we're waiting for
        // the user to grant permission. Clear _downloading so the Later button
        // reappears for optional updates.
        setState(() {
          _downloading = false;
          _needsPermission = true;
        });
      } else {
        setState(() {
          _downloading = false;
          _progress = DownloadProgress(
            fraction: 0,
            received: 0,
            total: 0,
            error: e.message ?? 'Installation failed',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = DownloadProgress(
          fraction: 0,
          received: 0,
          total: 0,
          error: e.toString(),
        );
      });
    }
  }

  /// Called by the "Retry Install" button after the user grants permission.
  /// Skips the download if the APK file is still in cache; re-downloads if not.
  Future<void> _retryInstall() async {
    final path = _completedApkPath;
    // Re-download if the path is unknown or the OS evicted the cached file.
    if (path == null || !File(path).existsSync()) {
      await _startDownload();
      return;
    }
    setState(() => _needsPermission = false);
    await _triggerInstall(path);
  }

  void _openStore(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;

    return PopScope(
      canPop: !result.isForced,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              result.isForced ? Icons.system_update : Icons.system_update_alt,
              color: result.isForced ? Colors.red : Colors.blue,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              result.isForced ? 'Update Required' : 'Update Available',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.isForced
                  ? 'This version is no longer supported. Please update to continue.'
                  : 'Version ${result.latestVersion} is available.',
              style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
            ),
            if (result.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                "What's new:",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                result.releaseNotes,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
              ),
            ],
            if (_needsPermission) ...[
              const SizedBox(height: 16),
              const _PermissionPrompt(),
            ] else if (_downloading) ...[
              const SizedBox(height: 16),
              _DownloadProgressBar(progress: _progress),
            ],
          ],
        ),
        actions: [
          if (!result.isForced && !_downloading && !_needsPermission)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
          _ActionButton(
            result: result,
            progress: _progress,
            downloading: _downloading,
            needsPermission: _needsPermission,
            onDownload: _startDownload,
            onRetryInstall: _retryInstall,
            onOpenStore: _openStore,
          ),
        ],
      ),
    );
  }
}

// ─── Permission prompt ────────────────────────────────────────────────────────

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Icon(Icons.info_outline, size: 16, color: Color(0xFFF59E0B)),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Enable "Install unknown apps" for Selah on the Settings page that just opened, then tap Retry Install.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
        ),
      ],
    );
  }
}

// ─── Action button ────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final AppUpdateResult result;
  final DownloadProgress? progress;
  final bool downloading;
  final bool needsPermission;
  final VoidCallback onDownload;
  final VoidCallback onRetryInstall;
  final void Function(String) onOpenStore;

  const _ActionButton({
    required this.result,
    required this.progress,
    required this.downloading,
    required this.needsPermission,
    required this.onDownload,
    required this.onRetryInstall,
    required this.onOpenStore,
  });

  @override
  Widget build(BuildContext context) {
    // Permission required: APK already downloaded, just need to retry install.
    if (needsPermission) {
      return FilledButton.icon(
        onPressed: onRetryInstall,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Retry Install'),
        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
      );
    }

    // Download/install error: retry from scratch.
    if (progress?.hasError == true) {
      return FilledButton.icon(
        onPressed: onDownload,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Retry'),
        style: FilledButton.styleFrom(backgroundColor: Colors.orange),
      );
    }

    // Download done; waiting for the system installer to take over.
    if (progress?.isDone == true) {
      return FilledButton(
        onPressed: null,
        child: const Text('Installing…'),
      );
    }

    // In progress.
    if (downloading) {
      return FilledButton(
        onPressed: null,
        child: const Text('Downloading…'),
      );
    }

    // Android with direct APK URL — primary path.
    if (result.canInstallDirectly) {
      return FilledButton.icon(
        onPressed: onDownload,
        icon: const Icon(Icons.download, size: 16),
        label: const Text('Download & Install'),
        style: FilledButton.styleFrom(
          backgroundColor: result.isForced ? Colors.red : Colors.blue,
        ),
      );
    }

    // iOS or store-URL fallback.
    return FilledButton(
      onPressed: result.storeUrl.isNotEmpty
          ? () => onOpenStore(result.storeUrl)
          : null,
      style: FilledButton.styleFrom(
        backgroundColor: result.isForced ? Colors.red : Colors.blue,
      ),
      child: const Text('Update Now'),
    );
  }
}

// ─── Progress bar ─────────────────────────────────────────────────────────────

class _DownloadProgressBar extends StatelessWidget {
  final DownloadProgress? progress;

  const _DownloadProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) {
      return const LinearProgressIndicator();
    }
    if (p.hasError) {
      return Text(
        'Download failed: ${p.error}',
        style: const TextStyle(fontSize: 12, color: Colors.red),
      );
    }
    if (p.isDone) {
      return const Text(
        'Download complete. Opening installer…',
        style: TextStyle(fontSize: 12, color: Colors.green),
      );
    }

    final pct = p.isIndeterminate ? null : p.fraction;
    final label = p.isIndeterminate
        ? 'Downloading…'
        : '${(p.fraction * 100).toStringAsFixed(0)}%'
            ' (${_formatBytes(p.received)} / ${_formatBytes(p.total)})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: pct),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
