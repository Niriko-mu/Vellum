import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';

import '../services/vellum_backup_service.dart';
import '../theme/app_shape.dart';
import '../theme/app_colors.dart';

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
    final result = await showCupertinoDialog<String?>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title ?? (required ? '输入备份密码' : '设置备份密码')),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            placeholder: placeholder ?? (required ? '解密密码' : '留空则不加密'),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('继续'),
          ),
        ],
      ),
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

  void _toast(String message) {
    if (!mounted) return;
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );
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
    final bg = CupertinoTheme.of(context).scaffoldBackgroundColor;
    final card = context.c.card;
    final ink = context.c.foreground;
    final muted = context.c.mutedForeground;
    return CupertinoPageScaffold(
      backgroundColor: bg,
      navigationBar: CupertinoNavigationBar(
        middle: const Text('数据备份'),
        backgroundColor: context.c.background,
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _heroCard(context, card, ink, muted),
            const SizedBox(height: 18),
            Text('备份内容', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 8),
            _backupContentCard(context, card, muted),
            const SizedBox(height: 18),
            Text('本地备份', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 8),
            _sectionCard(
              context,
              card,
              children: [
                _actionTile(
                  icon: CupertinoIcons.archivebox,
                  title: '创建本地备份',
                  detail: _loading
                      ? '读取中…'
                      : '${_local.length} 个备份 · ${_encrypt ? '加密' : '未加密'} · ${_selectedSections.length}/${BackupSection.values.length} 类内容',
                  onTap: _busy ? null : _createLocal,
                ),
                _actionTile(
                  icon: CupertinoIcons.arrow_up_doc,
                  title: '导出到文件',
                  detail: '可发送到电脑或其他设备',
                  onTap: _busy ? null : _exportLocal,
                ),
                _actionTile(
                  icon: CupertinoIcons.arrow_down_doc,
                  title: '从文件恢复',
                  detail: '恢复前会校验 VELLUM 清单',
                  onTap: _busy ? null : _restoreLocal,
                ),
                CupertinoListTile(
                  title: const Text('备份加密'),
                  additionalInfo: Text(_encrypt ? '开启' : '关闭'),
                  trailing: CupertinoSwitch(
                    value: _encrypt,
                    onChanged: (value) => setState(() => _encrypt = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('云备份', style: TextStyle(color: muted, fontSize: 13)),
            const SizedBox(height: 8),
            _sectionCard(
              context,
              card,
              children: [
                CupertinoListTile(
                  leading: const Icon(CupertinoIcons.cloud),
                  title: const Text('对象存储'),
                  additionalInfo: Text(
                    _bucket.text.trim().isEmpty
                        ? '未配置'
                        : VellumCloudConfig(
                            bucketUrl: _bucket.text,
                          ).vendorLabel,
                  ),
                  trailing: CupertinoSwitch(
                    value: _showCloud,
                    onChanged: (value) => setState(() => _showCloud = value),
                  ),
                  onTap: () => setState(() => _showCloud = !_showCloud),
                ),
                if (_showCloud) ...[
                  _field('SecretId', _id),
                  _field(
                    'SecretKey',
                    _key,
                    obscure: _obscureKey,
                    suffix: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                      child: Icon(
                        _obscureKey
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                      ),
                    ),
                  ),
                  _field('存储桶 URL', _bucket),
                  _field('对象前缀', _prefix),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: Text(
                      '支持 https://bucket.cos.region.myqcloud.com 与 https://bucket.oss-cn-region.aliyuncs.com。密钥只保存在本机安全存储。',
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                  _actionTile(
                    icon: CupertinoIcons.checkmark_shield,
                    title: '保存配置',
                    detail: '仅保存到系统安全存储',
                    onTap: _saveCloud,
                  ),
                  _actionTile(
                    icon: CupertinoIcons.cloud_upload,
                    title: '立即上传备份',
                    detail: _busy
                        ? '上传中…'
                        : '上传已选择的${_encrypt ? '加密' : '未加密'}内容',
                    onTap: _busy ? null : _uploadCloud,
                  ),
                  _actionTile(
                    icon: CupertinoIcons.refresh,
                    title: '读取云端备份',
                    detail: _cloudLoading ? '读取中…' : '${_cloud.length} 个云端备份',
                    onTap: _busy || _cloudLoading ? null : _loadCloudBackups,
                  ),
                  if (_cloud.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    for (final item in _cloud.take(10))
                      CupertinoListTile(
                        leading: const Icon(CupertinoIcons.cloud_download),
                        title: Text(item.fileName),
                        additionalInfo: Text(_cloudItemDetail(item)),
                        onTap: _busy ? null : () => _restoreCloud(item),
                      ),
                  ],
                ],
              ],
            ),
            if (_local.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('最近备份', style: TextStyle(color: muted, fontSize: 13)),
              const SizedBox(height: 8),
              _sectionCard(
                context,
                card,
                children: [
                  for (final item in _local.take(5))
                    CupertinoListTile(
                      leading: const Icon(CupertinoIcons.doc),
                      title: Text(_basename(item.file.path)),
                      additionalInfo: Text(_formatBytes(item.size)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _heroCard(BuildContext context, Color card, Color ink, Color muted) =>
      Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(AppRadius.xl3),
          border: Border.all(color: context.c.border),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.lock_shield,
              size: 30,
              color: context.c.primary,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '数据由你掌握',
                    style: TextStyle(
                      color: ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '书库、笔记、阅读进度和设置可随时导出。',
                    style: TextStyle(color: muted, fontSize: 13, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _backupContentCard(
    BuildContext context,
    Color card,
    Color muted,
  ) => Container(
    decoration: BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(AppRadius.xl2),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${_selectedSections.length}/${BackupSection.values.length} 类内容已选择',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(44, 36),
                onPressed: () => _setAllSections(true),
                child: const Text('全选'),
              ),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(44, 36),
                onPressed: () => _setAllSections(false),
                child: const Text('清空'),
              ),
            ],
          ),
        ),
        for (final section in BackupSection.values)
          CupertinoListTile(
            leading: CupertinoCheckbox(
              value: _selectedSections.contains(section),
              activeColor: context.c.primary,
              onChanged: (_) => _toggleSection(section),
            ),
            title: Text(section.label),
            subtitle: Text(section.description),
            onTap: () => _toggleSection(section),
          ),
      ],
    ),
  );

  Widget _sectionCard(
    BuildContext context,
    Color card, {
    required List<Widget> children,
  }) => Container(
    decoration: BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(AppRadius.xl2),
      border: Border.all(color: context.c.border),
    ),
    child: Column(children: children),
  );

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String detail,
    required VoidCallback? onTap,
  }) => CupertinoListTile(
    leading: Icon(icon),
    title: Text(title),
    additionalInfo: Text(detail),
    onTap: onTap,
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
    child: CupertinoTextField(
      controller: controller,
      obscureText: obscure,
      prefix: Padding(
        padding: const EdgeInsets.only(left: 10),
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
      suffix: suffix,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      decoration: BoxDecoration(
        color: CupertinoColors.systemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(AppRadius.xl),
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