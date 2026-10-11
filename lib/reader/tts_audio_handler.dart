import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../services/tts_cache.dart';
import '../services/tts_client.dart';
import '../services/tts_preferences.dart';
import '../services/tts_text.dart';

/// The listen (听书) playback engine.
///
/// One instance lives for the whole app (created in `main` via
/// `AudioService.init`) so playback survives the reader page closing and is
/// controllable from the notification / lock screen. Segments are sentence
/// granular: notification next/previous mean next/previous sentence, which is
/// what a reader expects. `onSentenceChanged` feeds the page's follow-scroll,
/// sentence highlight and subtitle line.
class VellumAudioHandler extends BaseAudioHandler {
  VellumAudioHandler({
    this.cache = const TtsCache(),
    this.preferencesStore = const TtsPreferencesStore(),
  }) {
    _player.processingStateStream.listen(_onProcessingState);
    _player.playbackEventStream.listen(
      (_) => _broadcastPlaybackState(),
      onError: (Object _) {},
    );
  }

  final AudioPlayer _player = AudioPlayer();
  final TtsCache cache;
  final TtsPreferencesStore preferencesStore;

  TtsPreferences? _preferences;
  List<SpeakableSegment> _segments = const [];
  int _index = -1;
  String _bookId = '';
  bool _loading = false;
  int _queueGeneration = 0;

  /// Reader callback: a sentence started (paragraph, sentence, text).
  void Function(int paragraphIndex, int sentenceIndex, String text)?
  onSentenceChanged;

  /// Reader callback: synthesis failed; playback has stopped.
  void Function(TtsException error)? onError;

  bool get hasBook => _segments.isNotEmpty && _index >= 0;
  bool get isPlaying => _player.playing;

  TtsPreferences? get preferences => _preferences;

  /// Position label for the player bar: `第 12 段 · 3 句 · 34/560`.
  String get positionLabel {
    if (!hasBook) return '';
    final segment = _segments[_index];
    return '第 ${segment.paragraphIndex + 1} 段 · ${segment.sentenceIndex + 1} 句'
        ' · ${_index + 1}/${_segments.length}';
  }

  /// Starts (or restarts) playback of [paragraphs] from [startParagraph].
  ///
  /// [startSentence] selects a sentence inside that paragraph (resume).
  Future<void> startBook({
    required String bookId,
    required String bookTitle,
    required List<String> paragraphs,
    required int startParagraph,
    int startSentence = 0,
  }) async {
    final generation = ++_queueGeneration;
    final preferences = await preferencesStore.load();
    if (generation != _queueGeneration) return;
    _preferences = preferences;
    _bookId = bookId;
    try {
      final segments = await buildSpeakableSegmentsInBackground(paragraphs);
      if (generation != _queueGeneration) return;
      _segments = segments;
    } on FormatException catch (error) {
      if (generation == _queueGeneration) {
        onError?.call(TtsException(TtsFailure.badResponse, error.message));
      }
      return;
    }
    if (_segments.isEmpty) {
      onError?.call(const TtsException(TtsFailure.badResponse, '这本书没有可朗读的文字'));
      return;
    }
    var index = _segments.indexWhere(
      (segment) =>
          segment.paragraphIndex == startParagraph &&
          segment.sentenceIndex >= startSentence,
    );
    if (index < 0) {
      index = _segments.indexWhere(
        (segment) => segment.paragraphIndex >= startParagraph,
      );
    }
    if (index < 0) index = _segments.length - 1;
    mediaItem.add(MediaItem(id: bookId, title: bookTitle, artist: 'Vellum 听书'));
    await _playIndex(index);
  }

  /// Double-tap listen: jump to the segment matching [sentence].
  ///
  /// Matching is on normalised text, because the tapped sentence comes from
  /// the rendered paragraph (markers stripped) while the queue was built from
  /// speakable text.
  Future<void> speakSentence(String sentence) async {
    if (_segments.isEmpty) return;
    final target = _normalize(sentence);
    if (target.isEmpty) return;
    var found = -1;
    for (var i = 0; i < _segments.length; i++) {
      if (_normalize(_segments[i].text) == target) {
        found = i;
        break;
      }
    }
    if (found < 0) {
      for (var i = 0; i < _segments.length; i++) {
        final text = _normalize(_segments[i].text);
        if (text.contains(target) || target.contains(text)) {
          found = i;
          break;
        }
      }
    }
    if (found >= 0) await _playIndex(found);
  }

  /// Resume helper for a remembered (paragraph, sentence) position.
  Future<void> speakAt(int paragraphIndex, int sentenceIndex) async {
    if (_segments.isEmpty) return;
    var index = _segments.indexWhere(
      (segment) =>
          segment.paragraphIndex == paragraphIndex &&
          segment.sentenceIndex == sentenceIndex,
    );
    if (index < 0) {
      index = _segments.indexWhere(
        (segment) => segment.paragraphIndex >= paragraphIndex,
      );
    }
    if (index >= 0) await _playIndex(index);
  }

  /// Sets the rate, persists it and applies it to the current stream.
  @override
  Future<void> setSpeed(double speed) async {
    final preferences = _preferences;
    if (preferences == null) return;
    _preferences = preferences.copyWith(speed: speed);
    await preferencesStore.save(_preferences!);
    await _player.setSpeed(speed.clamp(0.5, 2.0));
    _broadcastPlaybackState();
  }

  // --- transport controls (notification, lock screen, in-app bar) ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _queueGeneration++;
    _segments = const [];
    _index = -1;
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> skipToNext() async {
    if (_index + 1 < _segments.length) await _playIndex(_index + 1);
  }

  @override
  Future<void> skipToPrevious() async {
    if (_index > 0) await _playIndex(_index - 1);
  }

  // --- internals ---

  static String _normalize(String value) {
    var text = value.replaceAll(_spaceRuns, ' ').trim();
    while (text.length > 1 && _trailingPunct.hasMatch(text)) {
      text = text.substring(0, text.length - 1).trimRight();
    }
    return text;
  }

  static final _spaceRuns = RegExp(r'\s+');
  static final _trailingPunct = RegExp(r'[。！？!?…；;]$');

  Future<void> _playIndex(int index) async {
    if (_segments.isEmpty) return;
    final preferences = _preferences;
    if (preferences == null) return;
    _index = index;
    final segment = _segments[index];
    onSentenceChanged?.call(
      segment.paragraphIndex,
      segment.sentenceIndex,
      segment.text,
    );

    _loading = true;
    _broadcastPlaybackState();
    try {
      final key = cache.keyFor(
        preferences: preferences,
        bookId: _bookId,
        segment: segment,
      );
      var file = await cache.lookup(key);
      if (file == null) {
        final bytes = await TtsClient.forPreferences(
          preferences,
        ).synthesize(segment.text);
        file = await cache.write(key, bytes);
      }
      if (_index != index) return;
      await _player.setFilePath(file.path);
      await _player.setSpeed(preferences.speed.clamp(0.5, 2.0));
      _loading = false;
      await _player.play();
      _prefetch(index + 1);
    } on TtsException catch (error) {
      _loading = false;
      _broadcastPlaybackState();
      await stop();
      onError?.call(error);
    } catch (error) {
      _loading = false;
      _broadcastPlaybackState();
      await stop();
      onError?.call(TtsException(TtsFailure.server, '$error'));
    }
  }

  /// Warms the next sentence's cache entry while the current one plays.
  Future<void> _prefetch(int index) async {
    final preferences = _preferences;
    if (preferences == null || index >= _segments.length) return;
    final segment = _segments[index];
    final key = cache.keyFor(
      preferences: preferences,
      bookId: _bookId,
      segment: segment,
    );
    if (await cache.lookup(key) != null) return;
    try {
      final bytes = await TtsClient.forPreferences(
        preferences,
      ).synthesize(segment.text);
      await cache.write(key, bytes);
    } catch (_) {
      // Prefetch is best effort; the real error surfaces when it plays.
    }
  }

  void _onProcessingState(ProcessingState state) {
    if (state == ProcessingState.completed) {
      if (_index + 1 < _segments.length) {
        _playIndex(_index + 1);
      } else {
        stop();
      }
    }
    _broadcastPlaybackState();
  }

  /// Mirrors the player state into the notification / lock screen.
  void _broadcastPlaybackState() {
    final controls = <MediaControl>[
      if (_index > 0)
        const MediaControl(
          label: '上一句',
          androidIcon: 'drawable/ic_stat_skip_previous',
          action: MediaAction.skipToPrevious,
        ),
      if (_player.playing)
        const MediaControl(
          label: '暂停',
          androidIcon: 'drawable/ic_stat_pause',
          action: MediaAction.pause,
        )
      else
        const MediaControl(
          label: '播放',
          androidIcon: 'drawable/ic_stat_play',
          action: MediaAction.play,
        ),
      if (_index + 1 < _segments.length)
        const MediaControl(
          label: '下一句',
          androidIcon: 'drawable/ic_stat_skip_next',
          action: MediaAction.skipToNext,
        ),
      const MediaControl(
        label: '停止',
        androidIcon: 'drawable/ic_stat_stop',
        action: MediaAction.stop,
      ),
    ];
    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: const {
          MediaAction.skipToPrevious,
          MediaAction.skipToNext,
        },
        androidCompactActionIndices: List<int>.generate(
          controls.length < 3 ? controls.length : 3,
          (index) => index,
        ),
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: _player.playing || _loading,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _index,
      ),
    );
  }
}

/// The app-wide handler, assigned by `main` via `AudioService.init`.
///
/// Stays null where listening is unsupported (desktop platforms, or tests
/// where `AudioService.init` never ran) — reading it is always safe.
VellumAudioHandler? ttsHandler;
