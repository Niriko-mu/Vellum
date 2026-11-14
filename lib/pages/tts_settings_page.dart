import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:just_audio/just_audio.dart';

import '../services/tts_client.dart';
import '../services/tts_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_page.dart';
import '../widgets/ui/app_section.dart';
import '../widgets/ui/app_dialog.dart';

/// Configuration page for the listen (听书) service.
///
/// Plain JSON storage on purpose: the app's promise is "data stays on this
/// device", and the page says so next to the key field.
class TtsSettingsPage extends StatefulWidget {
  const TtsSettingsPage({super.key});

  @override
  State<TtsSettingsPage> createState() => _TtsSettingsPageState();
}

class _TtsSettingsPageState extends State<TtsSettingsPage> {
  final _store = const TtsPreferencesStore();
  TtsPreferences _prefs = const TtsPreferences();

  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _voiceController = TextEditingController();
  AudioPlayer? _testPlayer;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _store.load();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _baseUrlController.text = prefs.baseUrl;
      _apiKeyController.text = prefs.apiKey;
      _modelController.text = prefs.model;
      _voiceController.text = prefs.voice;
    });
  }

  @override
  void dispose() {
    _testPlayer?.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _persist() async {
    final prefs = _collect();
    setState(() => _prefs = prefs);
    await _store.save(prefs);
  }

  /// Current field values merged onto the selected provider.
  TtsPreferences _collect() => _prefs.copyWith(
    baseUrl: _baseUrlController.text.trim(),
    apiKey: _apiKeyController.text.trim(),
    model: _modelController.text.trim(),
    voice: _voiceController.text.trim(),
  );

  Future<void> _testSpeech() async {
    await _persist();
    if (_prefs.apiKey.isEmpty) {
      _message('请先填写 API Key。');
      return;
    }
    setState(() => _testing = true);
    try {
      final bytes = await TtsClient.forPreferences(
        _prefs,
      ).synthesize('朗读设置成功，可以开始听书了。');
      final file = File(
        '${Directory.systemTemp.path}'
        '${Platform.pathSeparator}vellum_tts_test.mp3',
      );
      await file.writeAsBytes(bytes, flush: true);
      await (_testPlayer ??= AudioPlayer()).setFilePath(file.path);
      await _testPlayer!.play();
      if (mounted) _message('连接成功，正在播放测试语音。');
    } on TtsException catch (error) {
      if (mounted) _message(error.userMessage);
    } catch (error) {
      if (mounted) _message('测试失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _message(String text) =>
      showAppNote(context: context, title: '朗读服务', message: text);

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final isAzure = _prefs.provider == TtsProvider.azure;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.background,
        border: null,
        middle: const Text('朗读服务'),
      ),
      child: AppPage(
        scrollable: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '配置后即可在阅读页点「听书」，从当前页开始朗读；'
              '语音会缓存在本机以省流量。Key 只保存在这台设备上。',
              style: AppText.rowDescription(colors.mutedForeground),
            ),
            const SizedBox(height: AppSpace.x6),
            AppSection(
              footer: 'OpenAI 兼容接口按合成音频计费，Azure 按朗读字符数计费；'
                  '同一本书的语音会缓存，重复听不重复计费。',
              children: [
                AppRow(
                  label: '接口类型',
                  trailing: CupertinoSlidingSegmentedControl<TtsProvider>(
                    groupValue: _prefs.provider,
                    children: {
                      for (final provider in TtsProvider.values)
                        provider: Text(provider.label),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(
                        () => _prefs = _collect().copyWith(provider: value),
                      );
                      _store.save(_collect());
                    },
                  ),
                ),
                _field(
                  '接口地址',
                  _baseUrlController,
                  isAzure
                      ? 'eastasia 或完整 URL'
                      : 'https://api.openai.com 或中转地址',
                ),
                _field(
                  'API Key',
                  _apiKeyController,
                  'sk-…（只存本机）',
                  obscure: true,
                ),
                if (isAzure)
                  _field('音色', _voiceController, 'zh-CN-XiaoxiaoNeural')
                else ...[
                  _field('模型', _modelController, 'tts-1 / cosyvoice-v1 …'),
                  _field('音色', _voiceController, 'alloy / longxiaochun …'),
                ],
                AppRow(
                  label: '语速',
                  value: '×${_prefs.speed.toStringAsFixed(2)}',
                  trailing: SizedBox(
                    width: 160,
                    child: CupertinoSlider(
                      value: _prefs.speed,
                      min: 0.5,
                      max: 2.0,
                      onChanged: (value) {
                        setState(
                          () => _prefs = _prefs.copyWith(speed: value),
                        );
                      },
                      onChangeEnd: (_) => _store.save(_collect()),
                    ),
                  ),
                ),
                AppRow(
                  label: '测试朗读',
                  value: _testing ? '连接中…' : null,
                  trailing: _testing
                      ? const CupertinoActivityIndicator(radius: 9)
                      : null,
                  onTap: _testing ? null : _testSpeech,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One editable field, laid out like a row so it lines up with the rest of
  /// the block instead of inventing a second form rhythm.
  Widget _field(
    String label,
    TextEditingController controller,
    String placeholder, {
    bool obscure = false,
  }) {
    final colors = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x4,
        AppSpace.x3,
        AppSpace.x4,
        AppSpace.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.rowDescription(colors.mutedForeground)),
          const SizedBox(height: AppSpace.x2),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            obscureText: obscure,
            onChanged: (_) => _persist(),
            cursorColor: colors.primary,
            style: AppText.rowTitle(colors.foreground),
            placeholderStyle: AppText.rowTitle(colors.mutedForeground),
            decoration: BoxDecoration(
              color: colors.secondary,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.x3,
              vertical: 10,
            ),
          ),
        ],
      ),
    );
  }
}

