import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'tts_preferences.dart';

enum TtsFailure { invalidKey, quota, network, server, badResponse }

class TtsException implements Exception {
  const TtsException(this.failure, this.message);

  final TtsFailure failure;
  final String message;

  /// Shown to the user, with an actionable hint where possible.
  String get userMessage => switch (failure) {
    TtsFailure.invalidKey => 'API Key 无效或没有权限，请检查朗读服务设置。',
    TtsFailure.quota => '朗读服务返回限流/余额不足（429），请稍后重试。',
    TtsFailure.network => '连不上朗读服务，请检查网络或接口地址。',
    TtsFailure.server => '朗读服务错误：$message',
    TtsFailure.badResponse =>
      message.contains('安全大小') ? message : '朗读服务返回了无法播放的内容，请检查模型/音色设置。',
  };

  @override
  String toString() => 'TtsException($failure): $message';
}

/// Speech synthesis client: turns one piece of text into MP3 bytes.
abstract class TtsClient {
  Future<Uint8List> synthesize(String text);

  factory TtsClient.forPreferences(
    TtsPreferences prefs, {
    http.Client? httpClient,
  }) => prefs.provider == TtsProvider.azure
      ? AzureTtsClient(preferences: prefs, httpClient: httpClient)
      : OpenAiCompatibleTtsClient(preferences: prefs, httpClient: httpClient);
}

/// POST `{base}/v1/audio/speech` — OpenAI, 火山方舟, 硅基流动 and self-hosted
/// proxies all speak this protocol.
class OpenAiCompatibleTtsClient implements TtsClient {
  OpenAiCompatibleTtsClient({
    required this.preferences,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _httpClient = httpClient ?? http.Client();

  final TtsPreferences preferences;
  final Duration timeout;
  final http.Client _httpClient;

  @override
  Future<Uint8List> synthesize(String text) async {
    final uri = Uri.parse(_endpoint(preferences.baseUrl));
    try {
      final response = await _httpClient
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${preferences.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': preferences.model.trim(),
              'input': text,
              'voice': preferences.voice.trim(),
              'response_format': 'mp3',
              if (preferences.speed != 1.0) 'speed': preferences.speed,
            }),
          )
          .timeout(timeout);
      return _bytesOrThrow(response);
    } on TimeoutException {
      throw const TtsException(TtsFailure.network, '请求超时');
    } on SocketException catch (error) {
      throw TtsException(TtsFailure.network, '$error');
    } on http.ClientException catch (error) {
      throw TtsException(TtsFailure.network, '$error');
    }
  }

  /// Accepts `host`, `https://host`, `https://host/v1` and appends the right
  /// path — users paste endpoints in every shape.
  static String _endpoint(String raw) {
    var base = raw.trim();
    if (base.isEmpty) base = 'https://api.openai.com';
    if (!base.startsWith('http')) base = 'https://$base';
    base = base.replaceAll(RegExp(r'/+$'), '');
    if (base.endsWith('/v1')) return '$base/audio/speech';
    return '$base/v1/audio/speech';
  }

  Uint8List _bytesOrThrow(http.Response response) {
    switch (response.statusCode) {
      case 200:
        final bytes = response.bodyBytes;
        if (bytes.isEmpty) {
          throw const TtsException(TtsFailure.badResponse, 'empty body');
        }
        return bytes;
      case 401:
      case 403:
        throw TtsException(
          TtsFailure.invalidKey,
          'HTTP ${response.statusCode}',
        );
      case 429:
        throw const TtsException(TtsFailure.quota, 'HTTP 429');
      default:
        throw TtsException(TtsFailure.server, 'HTTP ${response.statusCode}');
    }
  }
}

/// Azure Speech REST (`/cognitiveservices/v1`) with SSML output as MP3.
class AzureTtsClient implements TtsClient {
  AzureTtsClient({
    required this.preferences,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
  }) : _httpClient = httpClient ?? http.Client();

  final TtsPreferences preferences;
  final Duration timeout;
  final http.Client _httpClient;

  static const _outputFormat = 'audio-24khz-48kbitrate-mono-mp3';

  @override
  Future<Uint8List> synthesize(String text) async {
    final voice = preferences.voice.trim().isEmpty
        ? 'zh-CN-XiaoxiaoNeural'
        : preferences.voice.trim();
    final rate = (((preferences.speed - 1) * 100).round()).toString();
    final ssml =
        '<speak version="1.0" xml:lang="zh-CN">'
        '<voice name="$voice">'
        '<prosody rate="$rate%">${_escape(text)}</prosody>'
        '</voice>'
        '</speak>';
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_endpoint(preferences.baseUrl)),
            headers: {
              'Ocp-Apim-Subscription-Key': preferences.apiKey.trim(),
              'Content-Type': 'application/ssml+xml',
              'X-Microsoft-OutputFormat': _outputFormat,
            },
            body: utf8.encode(ssml),
          )
          .timeout(timeout);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        if (bytes.isEmpty) {
          throw const TtsException(TtsFailure.badResponse, 'empty body');
        }
        return bytes;
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw TtsException(
          TtsFailure.invalidKey,
          'HTTP ${response.statusCode}',
        );
      }
      if (response.statusCode == 429) {
        throw const TtsException(TtsFailure.quota, 'HTTP 429');
      }
      throw TtsException(TtsFailure.server, 'HTTP ${response.statusCode}');
    } on TimeoutException {
      throw const TtsException(TtsFailure.network, '请求超时');
    } on SocketException catch (error) {
      throw TtsException(TtsFailure.network, '$error');
    } on http.ClientException catch (error) {
      throw TtsException(TtsFailure.network, '$error');
    }
  }

  /// Accepts a region name (`eastasia`) or a full endpoint URL.
  static String _endpoint(String raw) {
    final value = raw.trim();
    if (value.startsWith('http')) {
      return value.replaceAll(RegExp(r'/+$'), '');
    }
    final region = value.isEmpty ? 'eastasia' : value;
    return 'https://$region.tts.speech.microsoft.com/cognitiveservices/v1';
  }

  /// SSML-escapes the text; Azure rejects raw `<`, `&`, quotes.
  static String _escape(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
