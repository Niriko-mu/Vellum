import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scrollbar;

import '../services/library_models.dart';
import '../services/notes_library.dart';
import '../theme/vellum_theme.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import '../services/reader_background.dart';
import 'reader_color_picker.dart';
import 'reader_models.dart';

class ReaderDirectoryPanel extends StatefulWidget {
  const ReaderDirectoryPanel({
    required this.chapters,
    required this.bookmarks,
    required this.notes,
    required this.chapterPageLabels,
    required this.currentParagraph,
    required this.readingMode,
    required this.onJumpToParagraph,
    required this.onRemoveBookmark,
    required this.onRemoveNote,
    required this.onClose,
    this.bookTitle = '',
    this.surface,
    super.key,
  });

  /// Fanqie reader catalog item height (`caloglayout/a.java` setItemHeight 54).
  static const double itemExtent = 54;

  /// Test-only alias so widget tests can assert the Fanqie height.
  static const double itemExtentForTest = itemExtent;

  final List<MapEntry<int, String>> chapters;
  final List<MapEntry<int, String>> bookmarks;
  final List<ReadingNote> notes;
  final Map<int, String> chapterPageLabels;
  final int currentParagraph;
  final ReadingMode readingMode;
  final ValueChanged<int> onJumpToParagraph;
  final Future<void> Function(int) onRemoveBookmark;
  final Future<void> Function(String) onRemoveNote;
  final VoidCallback onClose;
  final String bookTitle;

  /// Panel background (reading paper). Ink is derived from this so night
  /// paper stays readable even when the app theme is light.
  final Color? surface;

  @override
  State<ReaderDirectoryPanel> createState() => _ReaderDirectoryPanelState();
}

class _ReaderDirectoryPanelState extends State<ReaderDirectoryPanel> {
  var _tab = 0;

  /// Fanqie-style catalog order toggle (正序/倒序).
  var _descending = false;
  final _scrollController = ScrollController();
  var _didAutoScroll = false;

  static const double itemExtent = ReaderDirectoryPanel.itemExtent;

  List<MapEntry<int, String>> get _entries {
    final raw = _tab == 0 ? widget.chapters : widget.bookmarks;
    if (!_descending || raw.isEmpty) return raw;
    return raw.reversed.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToCurrent());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _toggleOrder() {
    setState(() {
      _descending = !_descending;
      _didAutoScroll = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScrollToCurrent());
  }

  /// Current chapter in the *displayed* list order (handles 倒序).
  bool _isCurrentChapter(
    int paragraphIndex,
    int index,
    List<MapEntry<int, String>> entries,
  ) {
    final current = widget.currentParagraph;
    if (_descending) {
      // Displayed[i] is original[n-1-i]. Range is (prevDisplay.key, this.key]
      // inverted: current is in this chapter when
      // current >= this.key && (next display is smaller chapter start OR last).
      final higherNeighbor = index > 0 ? entries[index - 1].key : 1 << 30;
      return current >= paragraphIndex && current < higherNeighbor;
    }
    final next = index + 1 < entries.length ? entries[index + 1].key : 1 << 30;
    return current >= paragraphIndex && current < next;
  }

  /// Fanqie `wl5/e.M3` three-state title colour:
  /// - current (`p3`): accent (`b5.n`) + left icon + title leftMargin 16
  /// - read (`!z2 && progress > 0`): `yz4.j.y(theme, 0.6f)` body @ 60%
  /// - unread: full body (`getReaderConfig().d1()`)
  /// Vellum approximates Fanqie's per-chapter progress % as "chapter start
  /// is strictly before the paragraph currently on screen".
  bool _isReadChapter(int paragraphIndex) =>
      paragraphIndex < widget.currentParagraph;

  /// Fanqie `P3`/`S3` secondary labels (always 60% body):
  /// - current: `读到 x/y 页` / `读到x%`
  /// - read: `已读x%` / `上次读到 x/y 页`
  /// - also word count / first-pass time when available.
  String _readStateLabel(int paragraphIndex, bool isCurrent, bool isRead) {
    if (widget.readingMode == ReadingMode.page) {
      final page = widget.chapterPageLabels[paragraphIndex];
      if (page != null && page.isNotEmpty) {
        return isCurrent ? '读到 $page' : '上次读到 $page';
      }
    }
    if (isCurrent) return '当前章节';
    if (isRead) return '已读';
    return '';
  }

  void _autoScrollToCurrent() {
    if (_didAutoScroll || !_scrollController.hasClients) return;
    final entries = _entries;
    if (entries.isEmpty) return;
    var target = 0;
    if (_descending) {
      // Reverse list: unread later chapters sit first; current is the first
      // entry whose start is <= currentParagraph.
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].key <= widget.currentParagraph) {
          target = i;
          break;
        }
      }
    } else {
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].key <= widget.currentParagraph) {
          target = i;
        } else {
          break;
        }
      }
    }
    _didAutoScroll = true;
    final maxOffset = _scrollController.position.maxScrollExtent;
    final offset = (target * itemExtent - 96).clamp(0.0, maxOffset);
    _scrollController.jumpTo(offset);
  }

  String _secondaryLabel(int paragraphIndex, bool isCurrent, bool isRead) {
    if (_tab == 1) return '第 ${paragraphIndex + 1} 段';
    if (_tab == 2) return '';
    return _readStateLabel(paragraphIndex, isCurrent, isRead);
  }

  /// Fanqie caloglayout structure: book name → tabs → divider → list.
  /// Parent supplies full band height; panel fills it.
  @override
  Widget build(BuildContext context) {
    final surface = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(surface);
    final muted = ink.withValues(alpha: .55);
    final accent = VellumTheme.readerAccentOf(context);
    final entries = _entries;
    final emptyMessage = switch (_tab) {
      0 => '这本书暂未识别出章节标题。',
      1 => '下拉阅读页面即可添加书签。',
      _ => '选中正文后可以划线或写笔记。',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Book name (Fanqie V1: 14sp, alpha 0.4 day / 0.6 night)
        if (widget.bookTitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              widget.bookTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink.withValues(alpha: .45), fontSize: 14),
            ),
          ),

        // 2) SlidingTabLayout-style tabs (Fanqie 16sp)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final (index, label) in [(0, '目录'), (1, '书签'), (2, '笔记')])
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _tab = index);
                      _didAutoScroll = false;
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _autoScrollToCurrent(),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        label,
                        style: TextStyle(
                          color: _tab == index ? accent : muted,
                          fontSize: 16,
                          fontWeight: _tab == index
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              // Fanqie catalog order toggle.
              if (_tab == 0)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(52, 44),
                  onPressed: _toggleOrder,
                  child: Text(
                    _descending ? '倒序' : '正序',
                    style: TextStyle(color: accent, fontSize: 13),
                  ),
                ),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: widget.onClose,
                child: Icon(CupertinoIcons.clear, size: 20, color: muted),
              ),
            ],
          ),
        ),

        // 3) Divider (Fanqie alj / item: 0.5dp)
        Container(height: 0.5, color: ink.withValues(alpha: .08)),

        // 4) List — fills remaining height provided by parent
        Expanded(
          child: _tab == 2
              ? _buildNotes(context)
              : entries.isEmpty
              ? Center(
                  child: Text(
                    emptyMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.zero,
                  itemCount: entries.length,
                  itemExtent: itemExtent,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isCurrent =
                        _tab == 0 &&
                        _isCurrentChapter(entry.key, index, entries);
                    // Fanqie wl5/e.M3: read = body @ 60% (`yz4.j.y(..., 0.6f)`).
                    final isRead = _tab == 0 && _isReadChapter(entry.key);
                    final titleColor = isCurrent
                        ? accent
                        : isRead
                        ? ink.withValues(alpha: .6)
                        : ink;
                    // Fanqie S3/P3: secondary always at 60% body.
                    final metaColor = ink.withValues(alpha: .45);
                    final secondary = _secondaryLabel(
                      entry.key,
                      isCurrent,
                      isRead,
                    );
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onJumpToParagraph(entry.key),
                      child: Container(
                        // Fanqie reader catalog item: 54dp, padH 20dp
                        // (caloglayout/a.java setItemHeight 54; avr 72 is audio).
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: ink.withValues(alpha: .06),
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (isCurrent)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                  CupertinoIcons.bookmark_fill,
                                  size: 14,
                                  color: accent,
                                ),
                              ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.value,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: titleColor,
                                      fontSize: 15,
                                      fontWeight: isCurrent
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                  if (secondary.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      secondary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: metaColor,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (_tab == 1)
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(32, 32),
                                onPressed: () async {
                                  await widget.onRemoveBookmark(entry.key);
                                  if (mounted) setState(() {});
                                },
                                child: Icon(
                                  CupertinoIcons.delete,
                                  size: 17,
                                  color: muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildNotes(BuildContext context) {
    final notes = widget.notes;
    final surface = widget.surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(surface);
    final muted = ink.withValues(alpha: .55);
    if (notes.isEmpty) {
      return Center(
        child: Text(
          '选中正文后可以划线或写笔记。',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted),
        ),
      );
    }
    return Scrollbar(
      thumbVisibility: true,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: notes.length,
        itemBuilder: (context, index) {
          final note = notes[index];
          return CupertinoListTile(
            backgroundColor: surface,
            backgroundColorActivated: ink.withValues(alpha: .08),
            title: Text(
              note.selectedText,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ink,
                backgroundColor: VellumTheme.readerAccentOf(
                  context,
                ).withValues(alpha: .18),
              ),
            ),
            subtitle: note.note.trim().isEmpty
                ? Text(
                    '${note.kind.label} · 第 ${note.paragraphIndex + 1} 段',
                    style: TextStyle(color: muted),
                  )
                : Text(
                    note.note.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted),
                  ),
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () async {
                await widget.onRemoveNote(note.id);
                if (mounted) setState(() {});
              },
              child: Icon(CupertinoIcons.delete, size: 17, color: muted),
            ),
            onTap: () => widget.onJumpToParagraph(note.paragraphIndex),
          );
        },
      ),
    );
  }
}

class ReaderSettingsPanel extends StatefulWidget {
  const ReaderSettingsPanel({
    required this.fontSize,
    required this.readerFontWeight,
    required this.lineSpacing,
    required this.background,
    required this.readingMode,
    required this.pageTurnStyle,
    required this.brightness,
    required this.eyeCare,
    required this.keepScreenOn,
    required this.volumeKeys,
    required this.onFontSize,
    required this.onReaderFontWeight,
    required this.onLineSpacing,
    required this.onBackground,
    required this.onReadingMode,
    required this.onPageTurnStyle,
    required this.onBrightness,
    required this.onEyeCare,
    required this.onKeepScreenOn,
    required this.onVolumeKeys,
    required this.onShowFonts,
    required this.onClose,
    this.surface,
    super.key,
  });

  final double fontSize;
  final ReaderFontWeight readerFontWeight;
  final ReaderLineSpacing lineSpacing;
  final ReaderBackground background;
  final ReadingMode readingMode;
  final PageTurnStyle pageTurnStyle;
  final double brightness;
  final ReaderEyeCare eyeCare;
  final bool keepScreenOn;
  final bool volumeKeys;
  final ValueChanged<double> onFontSize;
  final ValueChanged<ReaderFontWeight> onReaderFontWeight;
  final ValueChanged<ReaderLineSpacing> onLineSpacing;
  final ValueChanged<ReaderBackground> onBackground;
  final ValueChanged<ReadingMode> onReadingMode;
  final ValueChanged<PageTurnStyle> onPageTurnStyle;
  final ValueChanged<double> onBrightness;
  final ValueChanged<ReaderEyeCare> onEyeCare;
  final ValueChanged<bool> onKeepScreenOn;
  final ValueChanged<bool> onVolumeKeys;
  final VoidCallback onShowFonts;
  final VoidCallback onClose;
  final Color? surface;

  @override
  State<ReaderSettingsPanel> createState() => _ReaderSettingsPanelState();
}

/// First level keeps mid-book controls (mode, font size, paper, font,
/// line spacing). Rarer options live behind 「更多设置」.
class _ReaderSettingsPanelState extends State<ReaderSettingsPanel> {
  bool _showMore = false;
  bool _showBackground = false;
  // Inline pickers replace the old third-level 取色 page: one tap expands
  // a live HSV pad under the row and every drag paints the reader at once.
  bool _showInkPicker = false;
  bool _showUnderlayPicker = false;

  static const double _followSystemBrightness = -1;

  bool get _followsSystem => widget.brightness < 0;

  @override
  void dispose() {
    super.dispose();
  }

  Color get _surface => widget.surface ?? VellumTheme.readerChromeOf(context);
  Color get _ink => VellumTheme.readerChromeInk(_surface);
  Color get _muted => _ink.withValues(alpha: .55);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _showBackground
              ? _backgroundSettings(context)
              : (_showMore ? _moreSettings(context) : _mainSettings(context)),
        ),
      ),
    );
  }


  static const _presetPapers = <Color>[
    VellumTheme.readerWhite,
    VellumTheme.readerSepia,
    VellumTheme.readerMint,
    VellumTheme.readerBlue,
    VellumTheme.readerNight,
    VellumTheme.readerCharcoal,
    VellumTheme.readerSoftBlack,
  ];

  /// Second level: imported image + underlay + image opacity + ink picker +
  /// eye-care. Basic swatches live on the first level.
  List<Widget> _backgroundSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.photo,
      title: '自定义背景',
      surface: _surface,
      onClose: widget.onClose,
      onBack: () => setState(() {
        _showInkPicker = false;
        _showUnderlayPicker = false;
        _showBackground = false;
      }),
    ),
    _studioLabel('背景图'),
    Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: widget.background.usesImage
                ? Color(
                    widget.background.colorValue ?? 0xfff6f6f6,
                  ).withValues(alpha: widget.background.clampedImageOpacity)
                : Color(widget.background.colorValue ?? 0xfff6f6f6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _ink.withValues(alpha: .2)),
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.background.usesImage
              ? const Icon(CupertinoIcons.photo, size: 18)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            onPressed: _pickBackgroundImage,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.photo_on_rectangle,
                  size: 16,
                  color: _ink,
                ),
                const SizedBox(width: 4),
                Text('导入图片', style: TextStyle(fontSize: 13, color: _ink)),
              ],
            ),
          ),
        ),
        if (widget.background.usesImage)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            onPressed: () => widget.onBackground(
              widget.background.copyWith(clearImage: true, kind: BackgroundKind.solid),
            ),
            child: Text('移除', style: TextStyle(fontSize: 13, color: _muted)),
          ),
      ],
    ),
    if (widget.background.usesImage) ...[
      const SizedBox(height: 12),
      _studioLabel('背景色（图片底下的纯色）'),
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(
                widget.background.colorValue ?? VellumTheme.readerWhite.toARGB32(),
              ),
              shape: BoxShape.circle,
              border: Border.all(color: _ink.withValues(alpha: .25)),
            ),
          ),
          const SizedBox(width: 10),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 34),
            onPressed: () => setState(() {
              _showInkPicker = false;
              _showUnderlayPicker = !_showUnderlayPicker;
            }),
            child: Text(
              _showUnderlayPicker ? '收起取色' : '取色',
              style: TextStyle(fontSize: 13, color: _ink),
            ),
          ),
          if (widget.background.colorValue != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              onPressed: () => widget.onBackground(
                widget.background.copyWith(clearColor: true),
              ),
              child: Text('恢复默认', style: TextStyle(fontSize: 12, color: _muted)),
            ),
        ],
      ),
      if (_showUnderlayPicker) ...[
        const SizedBox(height: 10),
        ReaderColorPicker(
          color: Color(
            widget.background.colorValue ?? VellumTheme.readerWhite.toARGB32(),
          ),
          previewLabel: '背景色示例',
          onChanged: (c) => widget.onBackground(
            widget.background.copyWith(colorValue: c.toARGB32()),
          ),
        ),
      ],
      const SizedBox(height: 12),
      _studioLabel('背景图透明度'),
      Row(
        children: [
          Expanded(
            child: CupertinoSlider(
              value: widget.background.clampedImageOpacity,
              min: 0,
              max: 1,
              onChanged: (v) => widget.onBackground(
                widget.background.copyWith(imageOpacity: v),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(widget.background.clampedImageOpacity * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
      ),
    ],
    const SizedBox(height: 8),
    _studioLabel('正文字色（阅读正文的颜色）'),
    Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Color(widget.background.inkValue),
            shape: BoxShape.circle,
            border: Border.all(color: _ink.withValues(alpha: .25)),
          ),
        ),
        const SizedBox(width: 10),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 34),
          onPressed: () => setState(() {
            _showUnderlayPicker = false;
            _showInkPicker = !_showInkPicker;
          }),
          child: Text(
            _showInkPicker ? '收起取色' : '取色',
            style: TextStyle(fontSize: 13, color: _ink),
          ),
        ),
        if (widget.background.inkColorValue != null)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 34),
            onPressed: () => widget.onBackground(
              widget.background.copyWith(clearInk: true),
            ),
            child: Text('恢复默认', style: TextStyle(fontSize: 12, color: _muted)),
          ),
      ],
    ),
    if (_showInkPicker) ...[
      const SizedBox(height: 10),
      ReaderColorPicker(
        color: Color(widget.background.inkValue),
        previewLabel: '正文示例文字',
        onChanged: (c) => widget.onBackground(
          widget.background.copyWith(inkColorValue: c.toARGB32()),
        ),
      ),
      const SizedBox(height: 6),
      // One-tap common inks so most users never open the pad.
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in const {
            0xff000000: '纯黑',
            0xff333333: '深灰',
            0xff8c8c8c: '中灰',
            0xffb7b7b7: '浅灰',
            0xfff7e4cf: '米黄',
          }.entries)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 30),
              color: Color(entry.key),
              borderRadius: BorderRadius.circular(15),
              onPressed: () => widget.onBackground(
                widget.background.copyWith(inkColorValue: entry.key),
              ),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12,
                  color: ReaderBackground.suggestTone(entry.key) ==
                          BackgroundTone.dark
                      ? CupertinoColors.white
                      : CupertinoColors.black,
                ),
              ),
            ),
        ],
      ),
    ],
    const SizedBox(height: 8),
    _studioLabel('墨色（未自定义字体色时按底色明暗）'),
    _optionGroup<BackgroundTone>(
      groupValue: widget.background.tone,
      options: {for (final tone in BackgroundTone.values) tone: tone.label},
      onChanged: (tone) =>
          widget.onBackground(widget.background.copyWith(tone: tone)),
    ),
    const SizedBox(height: 14),
    _studioLabel('护眼'),
    _optionGroup<ReaderEyeCare>(
      groupValue: widget.eyeCare,
      options: {for (final level in ReaderEyeCare.values) level: level.label},
      onChanged: widget.onEyeCare,
    ),
    const SizedBox(height: 12),
    Text(
      '图片与自定义色只保存在本机 backgrounds/ 目录；护眼为 0.15 覆盖层，亮度走窗口属性，三者互相独立。',
      style: TextStyle(fontSize: 11, color: _muted, height: 1.5),
    ),
    const SizedBox(height: 8),
  ];

  Widget _studioLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, color: _muted, letterSpacing: .4),
    ),
  );

  bool _isSelectedColor(int argb) =>
      !widget.background.usesImage && widget.background.colorValue == argb;

  void _applyPresetColor(Color color) {
    final argb = color.toARGB32();
    widget.onBackground(
      ReaderBackground.customColor(
        argb,
        tone: ReaderBackground.suggestTone(argb),
      ),
    );
  }

  Future<void> _pickBackgroundImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      final name = await const ReaderBackgroundStore().importImage(
        Uint8List.fromList(bytes),
        file.name,
      );
      widget.onBackground(
        ReaderBackground.customImage(
          name,
          underlayColor: widget.background.colorValue,
          imageOpacity: widget.background.imageOpacity,
          tone: widget.background.tone,
          inkColorValue: widget.background.inkColorValue,
        ),
      );
    } catch (_) {
      // Picking cancelled or the provider returned nothing.
    }
  }

  Widget _optionGroup<T>({
    required T groupValue,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
  }) {
    final ink = _ink;
    final accent = VellumTheme.readerAccentOf(context);
    final surface = _surface;
    return Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(entry.key),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: groupValue == entry.key
                        ? surface.withValues(alpha: .95)
                        : const Color(0x00000000),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: groupValue == entry.key ? accent : ink,
                      fontWeight: groupValue == entry.key
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _mainSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.gear,
      title: '阅读设置',
      surface: _surface,
      onClose: widget.onClose,
    ),
    // Reading mode first — page vs scroll is the highest-frequency choice.
    ReaderSettingRow(
      label: '阅读方式',
      surface: _surface,
      child: _optionGroup<ReadingMode>(
        groupValue: widget.readingMode,
        options: const {ReadingMode.scroll: '上下滚动', ReadingMode.page: '左右翻页'},
        onChanged: widget.onReadingMode,
      ),
    ),
    if (widget.readingMode == ReadingMode.page)
      ReaderSettingRow(
        label: '翻页效果',
        surface: _surface,
        child: _optionGroup<PageTurnStyle>(
          groupValue: widget.pageTurnStyle,
          options: {
            for (final style in PageTurnStyle.values) style: style.label,
          },
          onChanged: widget.onPageTurnStyle,
        ),
      ),
    _fontSizeRow(context),
    ReaderSettingRow(
      label: '亮度',
      surface: _surface,
      child: _brightnessRow(context),
    ),
    // Basic papers sit on the first level so the panel opens ready to pick.
    Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text('背景', style: TextStyle(color: _muted, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in _presetPapers)
                  GestureDetector(
                    onTap: () => _applyPresetColor(color),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isSelectedColor(color.toARGB32())
                              ? VellumTheme.readerAccentOf(context)
                              : _ink.withValues(alpha: .2),
                          width: _isSelectedColor(color.toARGB32()) ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            onPressed: () => setState(() {
              _showMore = false;
              _showInkPicker = false;
              _showUnderlayPicker = false;
              _showBackground = true;
            }),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('自定义', style: TextStyle(fontSize: 13, color: _ink)),
                Icon(
                  CupertinoIcons.chevron_forward,
                  size: 14,
                  color: _muted,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    // Font entry preserved (FontPickerSheet) — whole row is tappable.
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onShowFonts,
      child: ReaderSettingRow(
        label: '字体',
        surface: _surface,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '系统 / 导入',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: _muted),
          ],
        ),
      ),
    ),
    ReaderSettingRow(
      label: '行间距',
      surface: _surface,
      child: _optionGroup<ReaderLineSpacing>(
        groupValue: widget.lineSpacing,
        options: {
          for (final spacing in ReaderLineSpacing.values)
            spacing: spacing.label,
        },
        onChanged: widget.onLineSpacing,
      ),
    ),
    GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showMore = true),
      child: ReaderSettingRow(
        label: '更多',
        surface: _surface,
        child: Row(
          children: [
            Expanded(
              child: Text('更多设置', style: TextStyle(fontSize: 13, color: _ink)),
            ),
            Icon(CupertinoIcons.chevron_forward, size: 16, color: _muted),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _moreSettings(BuildContext context) => [
    ReaderPanelTitle(
      icon: CupertinoIcons.slider_horizontal_3,
      title: '更多设置',
      surface: _surface,
      onClose: widget.onClose,
      onBack: () => setState(() => _showMore = false),
    ),
    ReaderSettingRow(
      label: '字重',
      surface: _surface,
      child: _optionGroup<ReaderFontWeight>(
        groupValue: widget.readerFontWeight,
        options: {
          for (final weight in ReaderFontWeight.values) weight: weight.label,
        },
        onChanged: widget.onReaderFontWeight,
      ),
    ),
    _switchRow(
      context,
      label: '常亮',
      detail: '阅读时保持屏幕常亮',
      value: widget.keepScreenOn,
      onChanged: widget.onKeepScreenOn,
    ),
    _switchRow(
      context,
      label: '音量键',
      detail: '用音量键翻页',
      value: widget.volumeKeys,
      onChanged: widget.onVolumeKeys,
    ),
  ];

  Widget _fontSizeRow(BuildContext context) => ReaderSettingRow(
    label: '字号',
    surface: _surface,
    child: Row(
      children: [
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(36, 36),
          onPressed: () => widget.onFontSize(
            (widget.fontSize - 1).clamp(kReaderFontMin, kReaderFontMax),
          ),
          child: Text('A−', style: TextStyle(fontSize: 14, color: _ink)),
        ),
        Expanded(
          child: CupertinoSlider(
            value: widget.fontSize.clamp(kReaderFontMin, kReaderFontMax),
            min: kReaderFontMin,
            max: kReaderFontMax,
            onChanged: widget.onFontSize,
          ),
        ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: const Size(36, 36),
          onPressed: () => widget.onFontSize(
            (widget.fontSize + 1).clamp(kReaderFontMin, kReaderFontMax),
          ),
          child: Text('A+', style: TextStyle(fontSize: 14, color: _ink)),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '${widget.fontSize.round()}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ),
      ],
    ),
  );

  Widget _brightnessRow(BuildContext context) => Row(
    children: [
      Icon(CupertinoIcons.sun_min, size: 16, color: _muted),
      Expanded(
        child: CupertinoSlider(
          value: (_followsSystem ? 0.6 : widget.brightness).clamp(0.05, 1.0),
          min: 0.05,
          max: 1,
          onChanged: widget.onBrightness,
        ),
      ),
      CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 36),
        onPressed: () => widget.onBrightness(_followSystemBrightness),
        child: Text(
          _followsSystem ? '跟随系统' : '恢复跟随',
          style: TextStyle(
            fontSize: 12,
            color: _followsSystem
                ? _muted
                : VellumTheme.readerAccentOf(context),
          ),
        ),
      ),
    ],
  );

  Widget _switchRow(
    BuildContext context, {
    required String label,
    required String detail,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => ReaderSettingRow(
    label: label,
    surface: _surface,
    child: Row(
      children: [
        Expanded(
          child: Text(detail, style: TextStyle(fontSize: 12, color: _muted)),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}

class ReaderPanelTitle extends StatelessWidget {
  const ReaderPanelTitle({
    required this.icon,
    required this.title,
    required this.onClose,
    this.onBack,
    this.surface,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onBack;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final ink = VellumTheme.readerChromeInk(bg);
    final muted = ink.withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
      child: Row(
        children: [
          if (onBack != null)
            CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 36),
              onPressed: onBack,
              child: Icon(CupertinoIcons.chevron_back, size: 20, color: muted),
            )
          else
            Icon(icon, size: 18, color: VellumTheme.readerAccentOf(context)),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: ink,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 36),
            onPressed: onClose,
            child: Icon(CupertinoIcons.chevron_down, size: 20, color: muted),
          ),
        ],
      ),
    );
  }
}

class ReaderSettingRow extends StatelessWidget {
  const ReaderSettingRow({
    required this.label,
    required this.child,
    this.surface,
    super.key,
  });

  final String label;
  final Widget child;
  final Color? surface;

  @override
  Widget build(BuildContext context) {
    final bg = surface ?? VellumTheme.readerChromeOf(context);
    final muted = VellumTheme.readerChromeInk(bg).withValues(alpha: .55);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(label, style: TextStyle(color: muted, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
