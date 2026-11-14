import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;
import 'package:url_launcher/url_launcher.dart';

import '../services/vellum_update_installer.dart';
import '../services/vellum_update_service.dart';
import '../theme/vellum_theme.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';

/// Checks the release feed and, when a newer build exists, walks the user
/// through picking an ABI variant and installing it.
///
/// [quiet] is for the launch-time check: nothing is shown when the app is up to
/// date and network errors stay silent. Manual checks report both.
Future<void> checkForUpdates(
  BuildContext context, {
  required String repository,
  bool quiet = true,
}) async {
  try {
    final release = await const VellumUpdateService().check(
      repository: repository,
    );
    if (!context.mounted) return;
    if (release == null || !release.hasUpdate) {
      if (!quiet) {
        await showUpdateMessage(
          context,
          '当前已是最新版本 V${release?.currentVersion ?? ''}。',
        );
      }
      return;
    }
    await showUpdateSheet(context, release);
  } on UpdateCheckException catch (error) {
    if (!quiet && context.mounted)
      await showUpdateMessage(context, error.message);
  } catch (error) {
    if (!quiet && context.mounted) {
      await showUpdateMessage(context, '检查更新失败：$error');
    }
  }
}

Future<void> showUpdateMessage(
  BuildContext context,
  String message, {
  String title = '检查更新',
}) => showCupertinoDialog<void>(
  context: context,
  builder: (context) => CupertinoAlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      CupertinoDialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('好'),
      ),
    ],
  ),
);

bool _sheetOpen = false;

/// Opens the variant picker. Re-entrant calls are ignored so a launch check and
/// a manual check cannot stack two sheets.
Future<void> showUpdateSheet(
  BuildContext context,
  VellumReleaseInfo release,
) async {
  if (_sheetOpen) return;
  _sheetOpen = true;
  try {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => UpdateSheet(release: release),
    );
  } finally {
    _sheetOpen = false;
  }
}

enum _UpdatePhase { picking, downloading, ready, installing, installed, failed }

class UpdateSheet extends StatefulWidget {
  const UpdateSheet({required this.release, super.key});

  final VellumReleaseInfo release;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  final _installer = const VellumUpdateInstaller();

  late List<UpdateApkAsset> _assets = widget.release.apkAssets;
  String? _deviceAbi;
  UpdateApkAsset? _selected;
  _UpdatePhase _phase = _UpdatePhase.picking;
  String _status = '';
  String _error = '';
  int _received = 0;
  int? _total;
  bool _cancelled = false;

  /// Kept after a successful download so granting the install permission does
  /// not force downloading the APK twice.
  File? _downloaded;

  @override
  void initState() {
    super.initState();
    _resolveDeviceAbi();
  }

  Future<void> _resolveDeviceAbi() async {
    final abi = await _installer.deviceAbi();
    if (!mounted) return;
    final assets = widget.release.apkAssetsFor(abi);
    setState(() {
      _deviceAbi = abi;
      _assets = assets;
      _selected = assets.isEmpty ? null : assets.first;
    });
  }

  bool _isRecommended(UpdateApkAsset asset) =>
      _deviceAbi != null && asset.abi == _deviceAbi;

  Future<void> _start() async {
    final asset = _selected;
    if (asset == null) return;

    if (!_installer.canInstallInApp) {
      await launchUrl(
        Uri.parse(asset.url),
        mode: LaunchMode.externalApplication,
      );
      return;
    }

    // Reuse an APK that is already on disk so granting the install
    // permission does not download it a second time.
    var file = _downloaded;
    if (file == null) {
      setState(() {
        _phase = _UpdatePhase.downloading;
        _error = '';
        _received = 0;
        _total = null;
        _cancelled = false;
        _status = '正在下载 ${asset.label}…';
      });
      try {
        file = await _installer.download(
          asset,
          isCancelled: () => _cancelled,
          onProgress: (received, total) {
            if (!mounted) return;
            setState(() {
              _received = received;
              _total = total;
            });
          },
        );
      } on ApkDownloadException catch (error) {
        if (!mounted) return;
        final cancelled = error.message.contains('取消');
        setState(() {
          _phase = cancelled ? _UpdatePhase.picking : _UpdatePhase.failed;
          _error = cancelled ? '' : error.message;
        });
        return;
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _phase = _UpdatePhase.failed;
          _error = '$error';
        });
        return;
      }
      if (!mounted) return;
      _downloaded = file;
      setState(() {
        _phase = _UpdatePhase.ready;
        _status = '下载完成，可以安装了。';
      });
    }

    if (!await _installer.canRequestInstall()) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.ready;
        _status = '安装包已下载好。系统还没允许 Vellum 安装应用，请允许后点「安装」。';
      });
      if (await _askForInstallPermission() == true) {
        await _installer.openInstallSettings();
      }
      return;
    }

    setState(() {
      _phase = _UpdatePhase.installing;
      _status = '正在调起系统安装器…';
    });
    try {
      await _installer.install(file);
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.installed;
        _status = '已调起系统安装界面，按提示完成安装即可。';
      });
    } on ApkDownloadException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _UpdatePhase.failed;
        _error = error.message;
      });
    }
  }

  Future<bool?> _askForInstallPermission() => showCupertinoDialog<bool>(
    context: context,
    builder: (context) => CupertinoAlertDialog(
      title: const Text('需要安装权限'),
      content: const Text('系统还没有允许 Vellum 安装应用。请在接下来的设置页里打开「允许来自此来源的应用」后返回重试。'),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () async {
            Navigator.pop(context, true);
            await _installer.openInstallSettings();
          },
          child: const Text('去设置'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;

    return Container(
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: AppRadius.sheetTop,
        border: Border.all(color: context.c.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: context.c.border,
                  borderRadius: BorderRadius.circular(AppRadius.hairlineXs),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '发现新版本 V${widget.release.latestVersion}',
              style: TextStyle(
                fontFamily: VellumTheme.fontFamily,
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '当前版本 V${widget.release.currentVersion}',
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 14),
            Flexible(child: _buildBody(ink, muted)),
            const SizedBox(height: 14),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Color ink, Color muted) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.release.notes.trim().isNotEmpty) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(
                  widget.release.notes.trim(),
                  style: TextStyle(fontSize: 13, color: muted, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_phase == _UpdatePhase.downloading) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: _total == null || _total == 0
                    ? null
                    : (_received / _total!).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: context.c.secondary,
                valueColor: AlwaysStoppedAnimation(
                  context.c.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _total == null
                  ? '已下载 ${_formatBytes(_received)}'
                  : '${_formatBytes(_received)} / ${_formatBytes(_total!)}',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ] else if (_assets.isEmpty) ...[
            Text(
              '这个版本没有附带 APK，请到发布页自行下载。',
              style: TextStyle(fontSize: 13, color: muted, height: 1.4),
            ),
          ] else ...[
            Text(
              _installer.canInstallInApp ? '选择适合本机的安装包' : '选择要下载的安装包',
              style: TextStyle(
                fontSize: 13,
                color: muted,
                fontWeight: FontWeight.w600,
                letterSpacing: .4,
              ),
            ),
            const SizedBox(height: 8),
            for (final asset in _assets)
              _AssetRow(
                asset: asset,
                selected: _selected?.name == asset.name,
                recommended: _isRecommended(asset),
                onTap: _phase == _UpdatePhase.picking
                    ? () => setState(() => _selected = asset)
                    : null,
              ),
            if (_phase == _UpdatePhase.picking && _deviceAbi == null) ...[
              const SizedBox(height: 6),
              Text(
                '未能识别本机架构，默认推荐 arm64-v8a；装错版本会提示「应用未安装」。',
                style: TextStyle(fontSize: 13, color: muted, height: 1.4),
              ),
            ],
          ],
          if (_status.isNotEmpty &&
              _phase != _UpdatePhase.downloading &&
              _phase != _UpdatePhase.picking) ...[
            const SizedBox(height: 12),
            Text(
              _status,
              style: TextStyle(
                fontSize: 13,
                color: _phase == _UpdatePhase.failed ? muted : ink,
                height: 1.4,
              ),
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _error,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions() {
    switch (_phase) {
      case _UpdatePhase.downloading:
        return CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: () => setState(() => _cancelled = true),
          child: const Text('取消下载'),
        );
      case _UpdatePhase.installing:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CupertinoActivityIndicator(radius: 10)),
        );
      case _UpdatePhase.installed:
        return CupertinoButton.filled(
          padding: const EdgeInsets.symmetric(vertical: 12),
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        );
      case _UpdatePhase.failed:
      case _UpdatePhase.ready:
      case _UpdatePhase.picking:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CupertinoButton.filled(
              padding: const EdgeInsets.symmetric(vertical: 12),
              onPressed: _assets.isEmpty ? null : _start,
              child: Text(switch (_phase) {
                _UpdatePhase.failed => '重试',
                _UpdatePhase.ready => '安装',
                _ => _installer.canInstallInApp ? '下载并更新' : '打开下载页',
              }),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => Navigator.pop(context),
                  child: const Text('稍后'),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => launchUrl(
                    Uri.parse(widget.release.releaseUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('发布页'),
                ),
              ],
            ),
          ],
        );
    }
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.asset,
    required this.selected,
    required this.recommended,
    required this.onTap,
  });

  final UpdateApkAsset asset;
  final bool selected;
  final bool recommended;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = context.c.primary;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              selected
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.circle,
              size: 20,
              color: selected ? accent : context.c.mutedForeground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.label,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.c.foreground,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    abiDescription(asset.abi),
                    style: TextStyle(
                      fontSize: 13,
                      color: context.c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            if (recommended)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.c.secondary,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Text(
                  '推荐',
                  style: TextStyle(
                    fontSize: 13,
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}