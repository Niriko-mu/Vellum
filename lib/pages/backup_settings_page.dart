import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/vellum_backup_service.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_page.dart';
import '../widgets/ui/app_section.dart';
import '../widgets/ui/app_pressable.dart';
import '../theme/app_icons.dart';
import '../widgets/ui/app_dialog.dart';
import '../widgets/ui/app_toast.dart';

/// Local and object-storage backup settings for VELLUM. The page deliberately
/// keeps cloud credentials in a separate collapsed section and never displays
/// the secret key after saving.
class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  final _service = VellumBackupService();
  final _id = TextEditingController();
  final _key = TextEditingController();
  final _bucket = TextEditingController();
  final _prefix = TextEditingController(text: 'vellum/backups/v1');
  List<VellumBackupItem> _local = const [];
  List<VellumCloudBackupObject> _cloud = const [];
  bool _loading = true;
  bool _cloudLoading = false;
  bool _busy = false;
  bool _showCloud = false;
  bool _encrypt = true;
  bool _obscureKey = true;
  Set<BackupSection> _selectedSections = {...BackupSection.values};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _id.dispose();
    _key.dispose();
    _bucket.dispose();
    _prefix.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final config = await _service.loadCloudConfig();
      _id.text = config.secretId;
      _key.text = config.secretKey;
      _bucket.text = config.bucketUrl;
      _prefix.text = config.prefix;
      final files = await _service.listLocalBackups();
      if (!mounted) return;
      setState(() {
        _local = files;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askPassword({
    required bool required,
    String? title,
    String? placeholder,
  }) async {
    final controller = TextEditingController();
    final result = await showAppDialog<String>(
      context: context,
      title: title ?? (required ? '输入备份密码' : '设置备份密码'),
      message: required ? '这个备份是加密的，需要密码才能恢复。' : null,
      contentController: controller,
      content: CupertinoTextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        placeholder: placeholder ?? (required ? '解密密码' : '留空则不加密'),
        cursorColor: context.c.primary,
        style: AppText.rowTitle(context.c.foreground),
        decoration: BoxDecoration(
          color: context.c.secondary,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: context.c.border),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.x3,
          vertical: 10,
        ),
      ),
      actions: [
        AppDialogAction<String>(
          label: '继续',
          valueBuilder: () => controller.text,
          // A required password cannot be submitted empty; without this the
          // dialog closed on a value captured before anyone could type.
          enabledBuilder: () => !required || controller.text.isNotEmpty,
          isDefault: true,
        ),
      ],
    );
    controller.dispose();
    if (required && (result == null || result.isEmpty)) return null;
    return result;
  }

  Future<void> _createLocal() async {
    if (_busy) return;
    if (!_ensureBackupSelection()) return;
    final password = _encrypt ? await _askPassword(required: false) : null;
    if (_encrypt && (password == null || password.isEmpty)) {
      if (mounted) _toast('未设置密码，本次未创建备份');
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await _service.createLocalBackup(
        password: password,
        sections: _selectedSections,
      );
      await _refreshFiles();
      if (mounted) _toast('本地备份已创建：${_basename(file.path)}');
    } catch (error) {
      if (mounted) _toast('创建失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportLocal() async {
    if (_busy) return;
    if (!_ensureBackupSelection()) return;
    final password = _encrypt ? await _askPassword(required: false) : '';
    if (password == null && mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await _service.exportArchive(
        password: password,
        sections: _selectedSections,
      );
      final extension = password == null || password.isEmpty
          ? 'zip'
          : 'vbackup';
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出 VELLUM 备份',
        fileName: 'vellum_backup.$extension',
        type: FileType.custom,
        allowedExtensions: const ['zip', 'vbackup'],
        bytes: bytes,
      );
      if (mounted && path != null) _toast('备份已导出');
    } catch (error) {
      if (mounted) _toast('导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreLocal() async {
    if (_busy) return;
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 VELLUM 备份',
      type: FileType.custom,
      allowedExtensions: const ['zip', 'vbackup'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    final password = await _askPassword(
      required: false,
      title: '输入备份密码',
      placeholder: '加密备份需填写，未加密可留空',
    );
    if (password == null && mounted) return;
    setState(() => _busy = true);
    try {
      await _service.restore(File(path), password: password);
      if (mounted) _toast('恢复完成，重新打开页面后生效');
    } catch (error) {
      if (mounted) _toast('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCloud() async {
    final config = _cloudConfig();
    if (!config.isConfigured) {
      _toast('请填写有效的腾讯云 COS 或阿里云 OSS 存储桶 URL 与密钥');
      return;
    }
    await _service.saveCloudConfig(config);
    if (mounted) _toast('云备份配置已保存（${config.vendorLabel}）');
  }

  VellumCloudConfig _cloudConfig() => VellumCloudConfig(
    secretId: _id.text,
    secretKey: _key.text,
    bucketUrl: _bucket.text,
    prefix: _prefix.text,
  );

  Future<void> _loadCloudBackups() async {
    if (_cloudLoading) return;
    final config = _cloudConfig();
    if (!config.isConfigured) {
      if (mounted) _toast('请先填写并保存对象存储配置');
      return;
    }
    setState(() => _cloudLoading = true);
    try {
      await _service.saveCloudConfig(config);
      final files = await _service.listCloud(config);
      if (mounted) setState(() => _cloud = files);
    } catch (error) {
      if (mounted) _toast('读取云端列表失败：$error');
    } finally {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  Future<void> _restoreCloud(VellumCloudBackupObject item) async {
    if (_busy) return;
    final config = _cloudConfig();
    if (!config.isConfigured) return;
    final password = await _askPassword(
      required: false,
      title: '输入备份密码',
      placeholder: '加密备份需填写，未加密可留空',
    );
    if (password == null && mounted) return;
    setState(() => _busy = true);
    try {
      await _service.restoreCloud(config, item.key, password: password);
      if (mounted) _toast('云端备份已恢复，重新打开页面后生效');
    } catch (error) {
      if (mounted) _toast('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadCloud() async {
    if (!_ensureBackupSelection()) return;
    final config = _cloudConfig();
    if (!config.isConfigured) {
      _toast('请先完成云备份配置');
      return;
    }
    final password = _encrypt ? await _askPassword(required: false) : null;
    if (_encrypt && (password == null || password.isEmpty)) return;
    setState(() => _busy = true);
    try {
      await _service.saveCloudConfig(config);
      await _service.upload(
        config,
        password: password,
        sections: _selectedSections,
      );
      await _refreshFiles();
      await _loadCloudBackups();
      if (mounted) _toast('已上传到 ${config.vendorLabel}');
    } catch (error) {
      if (mounted) _toast('上传失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshFiles() async {
    final files = await _service.listLocalBackups();
    if (mounted) setState(() => _local = files);
  }

  /// A backup result is an acknowledgement, not a decision: a modal alert for
  /// "备份已创建" would make a run of actions a run of taps on 「好」.
  void _toast(String message) {
    if (!mounted) return;
    showAppToast(context, message);
  }

  bool _ensureBackupSelection() {
    if (_selectedSections.isNotEmpty) return true;
    _toast('请至少选择一类备份内容');
    return false;
  }

  void _setAllSections(bool selected) {
    setState(() {
      _selectedSections = selected
          ? {...BackupSection.values}
          : <BackupSection>{};
    });
  }

  void _toggleSection(BackupSection section) {
    setState(() {
      final next = {..._selectedSections};
      if (!next.add(section)) next.remove(section);
      _selectedSections = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.background,
        border: null,
        middle: const Text('数据备份'),
      ),
      child: AppPage(
        scrollable: true,
        // The floating dock draws over the page; without this the last row sits
        // under the capsule and cannot be tapped.
        reserveDock: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // An intro, not a card: it is the page's own voice, and a card
            // would imply it is one more thing to act on.
            Row(
              children: [
                Icon(
                  AppIcons.lockShield,
                  size: 26,
                  color: colors.primary,
                ),
                const SizedBox(width: AppSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('数据由你掌握', style: AppText.sectionHeader(colors.foreground)),
                      const SizedBox(height: AppSpace.x1),
                      Text(
                        '书库、笔记、阅读进度和设置可随时导出。',
                        style: AppText.caption(colors.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.x6),
            // The primary task, so it comes first and carries no header.
            AppSection(
              header: '备份内容',
              headerTrailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    label: '全选',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    onPressed: () => _setAllSections(true),
                  ),
                  AppButton(
                    label: '清空',
                    variant: AppButtonVariant.ghost,
                    size: AppButtonSize.small,
                    onPressed: () => _setAllSections(false),
                  ),
                ],
              ),
              children: [
                AppRow(
                  label: '${_selectedSections.length}/'
                      '${BackupSection.values.length} 类内容已选择',
                  value: _encrypt ? '加密' : '未加密',
                ),
                for (final section in BackupSection.values)
                  AppRow(
                    label: section.label,
                    description: section.description,
                    // A checkbox row toggles in place; a chevron would promise
                    // a page that never opens.
                    showChevron: false,
                    leading: CupertinoCheckbox(
                      value: _selectedSections.contains(section),
                      activeColor: colors.primary,
                      onChanged: (_) => _toggleSection(section),
                    ),
                    onTap: () => _toggleSection(section),
                  ),
              ],
            ),
            AppSection(
              header: '本地备份',
              children: [
                AppRow(
                  leading: const Icon(AppIcons.archivebox),
                  label: '创建本地备份',
                  description: _loading
                      ? '读取中…'
                      : '${_local.length} 个备份 · ${_encrypt ? '加密' : '未加密'} · ${_selectedSections.length}/${BackupSection.values.length} 类内容',
                  onTap: _busy ? null : _createLocal,
                ),
                AppRow(
                  leading: const Icon(AppIcons.arrowUpDoc),
                  label: '导出到文件',
                  description: '可发送到电脑或其他设备',
                  onTap: _busy ? null : _exportLocal,
                ),
                AppRow(
                  leading: const Icon(AppIcons.arrowDownDoc),
                  label: '从文件恢复',
                  description: '恢复前会校验 VELLUM 清单',
                  onTap: _busy ? null : _restoreLocal,
                ),
                AppSwitchRow(
                  label: '备份加密',
                  value: _encrypt,
                  onChanged: (value) => setState(() => _encrypt = value),
                ),
              ],
            ),
            AppSection(
              header: '云备份',
              children: [
                AppSwitchRow(
                  leading: const Icon(AppIcons.cloud),
                  label: '对象存储',
                  description: _bucket.text.trim().isEmpty
                      ? '未配置'
                      : VellumCloudConfig(
                          bucketUrl: _bucket.text,
                        ).vendorLabel,
                  value: _showCloud,
                  onChanged: (value) => setState(() => _showCloud = value),
                ),
                if (_showCloud) ...[
                  _field('SecretId', _id),
                  _field(
                    'SecretKey',
                    _key,
                    obscure: _obscureKey,
                    suffix: AppPressable(
                      onTap: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      semanticLabel: _obscureKey ? '显示密钥' : '隐藏密钥',
                      child: SizedBox(
                        width: 40,
                        height: 36,
                        child: Icon(
                          _obscureKey
                              ? AppIcons.eye
                              : AppIcons.eyeSlash,
                        ),
                      ),
                    ),
                  ),
                  _field('存储桶', _bucket),
                  _field('路径前缀', _prefix),
                  AppRow(
                    leading: const Icon(AppIcons.checkmarkSeal),
                    label: '保存云配置',
                    description: '仅保存到系统安全存储',
                    onTap: _saveCloud,
                  ),
                  AppRow(
                    leading: const Icon(AppIcons.cloudUpload),
                    label: '立即上传备份',
                    description: _busy
                        ? '上传中…'
                        : '上传已选择的${_encrypt ? '加密' : '未加密'}内容',
                    onTap: _busy ? null : _uploadCloud,
                  ),
                  AppRow(
                    leading: const Icon(AppIcons.refresh),
                    label: '读取云端备份',
                    description: _cloudLoading
                        ? '读取中…'
                        : '${_cloud.length} 个云端备份',
                    onTap: _busy || _cloudLoading ? null : _loadCloudBackups,
                  ),
                ],
              ],
            ),
            if (_cloud.isNotEmpty)
              AppSection(
                header: '云端备份',
                children: [
                  for (final item in _cloud.take(10))
                    AppRow(
                      leading: const Icon(AppIcons.cloudDownload),
                      label: item.fileName,
                      description: _cloudItemDetail(item),
                      onTap: _busy ? null : () => _restoreCloud(item),
                    ),
                ],
              ),
            if (_local.isNotEmpty)
              AppSection(
                header: '最近备份',
                children: [
                  for (final item in _local.take(5))
                    AppRow(
                      leading: const Icon(AppIcons.doc),
                      label: _basename(item.file.path),
                      value: _formatBytes(item.size),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }


  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.x4,
      AppSpace.x3,
      AppSpace.x4,
      AppSpace.x3,
    ),
    child: CupertinoTextField(
      controller: controller,
      obscureText: obscure,
      prefix: Padding(
        padding: const EdgeInsets.only(left: AppSpace.x3),
        child: Text(
          label,
          style: AppText.caption(context.c.mutedForeground),
        ),
      ),
      suffix: suffix,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.x2,
        vertical: 11,
      ),
      cursorColor: context.c.primary,
      style: AppText.rowTitle(context.c.foreground),
      decoration: BoxDecoration(
        color: context.c.secondary,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.c.border),
      ),
    ),
  );

  String _basename(String path) => path.replaceAll('\\', '/').split('/').last;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _cloudItemDetail(VellumCloudBackupObject item) {
    final size = _formatBytes(item.size);
    final date = item.lastModified;
    if (date == null) return size;
    final local = date.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '$size · ${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}