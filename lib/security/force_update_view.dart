import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../bridge/siya_bridge.dart';
import 'remote_config_model.dart';

enum UpdateStatus {
  idle,
  downloading,
  downloaded,
  failed,
}

/// In-App Dynamic Force Updater Dialog/View.
///
/// Features:
/// 1. Styled dynamically with the app's current theme colors (Theme.of(context).colorScheme).
///    No static background images.
/// 2. In-app direct download from "app_config/update_url" using 'dio'.
/// 3. Linear progress bar showing live percentage and downloaded MB vs total MB.
/// 4. Direct Android Package Installer intent via Android FileProvider.
/// 5. Persistent & non-dismissible: blocks back navigation, maintains "Retry Install"
///    if installer is dismissed so the outdated app cannot be used.
class ForceUpdateView extends StatefulWidget {
  final AppRemoteConfig config;
  final int currentVersionCode;
  final SiyaBridge bridge;

  const ForceUpdateView({
    super.key,
    required this.config,
    required this.currentVersionCode,
    required this.bridge,
  });

  @override
  State<ForceUpdateView> createState() => _ForceUpdateViewState();
}

class _ForceUpdateViewState extends State<ForceUpdateView> {
  UpdateStatus _status = UpdateStatus.idle;
  double _progress = 0.0;
  String _downloadedMb = '0.0';
  String _totalMb = '0.0';
  String? _errorMessage;
  String? _downloadedFilePath;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  void _startInAppDownload() async {
    final url = widget.config.updateUrl.trim();
    if (url.isEmpty) {
      setState(() {
        _status = UpdateStatus.failed;
        _errorMessage = 'Update URL is not configured. Please contact administrator.';
      });
      return;
    }

    setState(() {
      _status = UpdateStatus.downloading;
      _progress = 0.0;
      _downloadedMb = '0.0';
      _totalMb = '0.0';
      _errorMessage = null;
    });

    try {
      final cacheDir = await widget.bridge.getCacheDir();
      final dir = cacheDir.isNotEmpty ? cacheDir : Directory.systemTemp.path;
      final savePath = '$dir/siya_update_${widget.config.latestVersionCode}.apk';

      _cancelToken = CancelToken();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
      ));

      await dio.download(
        url,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _progress = (received / total).clamp(0.0, 1.0);
              _downloadedMb = (received / (1024 * 1024)).toStringAsFixed(1);
              _totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
            });
          } else {
            setState(() {
              _downloadedMb = (received / (1024 * 1024)).toStringAsFixed(1);
              _totalMb = 'Unknown';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _status = UpdateStatus.downloaded;
        _progress = 1.0;
        _downloadedFilePath = savePath;
      });

      // Immediately trigger Android Package Installer workflow via FileProvider
      _triggerInstaller(savePath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = UpdateStatus.failed;
        _errorMessage = 'Download failed: ${e.toString()}';
      });
    }
  }

  void _triggerInstaller([String? path]) async {
    final targetPath = path ?? _downloadedFilePath;
    if (targetPath == null || targetPath.isEmpty) {
      _startInAppDownload();
      return;
    }

    final success = await widget.bridge.installApk(targetPath);
    if (!success && mounted) {
      // Fallback: try opening as external intent
      await widget.bridge.openUrl(widget.config.updateUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withOpacity(0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dynamic Themed Header Icon
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primaryContainer.withOpacity(0.7),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.system_update_rounded,
                            size: 38,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Text(
                        'Update Required',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Text(
                        'A newer version of Siya AI is required to continue. Please install the mandatory update below.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Version Badge Comparison
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  'Installed',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Build ${widget.currentVersionCode}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: colorScheme.primary,
                              size: 20,
                            ),
                            Column(
                              children: [
                                Text(
                                  'Latest',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Build ${widget.config.latestVersionCode}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Progress Bar or Download Status
                      if (_status == UpdateStatus.downloading) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            minHeight: 10,
                            backgroundColor: colorScheme.primary.withOpacity(0.15),
                            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Downloading: ${(_progress * 100).toStringAsFixed(1)}%',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$_downloadedMb MB / $_totalMb MB',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (_status == UpdateStatus.failed && _errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 20, color: colorScheme.error),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onErrorContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: _buildActionButton(colorScheme, theme),
                      ),

                      if (_status == UpdateStatus.downloaded) ...[
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _startInAppDownload,
                          child: Text(
                            'Re-download APK',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(ColorScheme colorScheme, ThemeData theme) {
    switch (_status) {
      case UpdateStatus.downloading:
        return ElevatedButton.icon(
          onPressed: null,
          icon: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          label: const Text('Downloading APK...'),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );

      case UpdateStatus.downloaded:
        return ElevatedButton.icon(
          onPressed: () => _triggerInstaller(),
          icon: const Icon(Icons.install_mobile_rounded, size: 22),
          label: const Text(
            'Retry Install',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );

      case UpdateStatus.failed:
        return ElevatedButton.icon(
          onPressed: _startInAppDownload,
          icon: const Icon(Icons.refresh_rounded, size: 22),
          label: const Text(
            'Retry Download',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );

      case UpdateStatus.idle:
        return ElevatedButton.icon(
          onPressed: _startInAppDownload,
          icon: const Icon(Icons.download_rounded, size: 22),
          label: const Text(
            'Update Now',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        );
    }
  }
}
