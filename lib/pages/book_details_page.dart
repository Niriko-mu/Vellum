import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_motion.dart';
import '../theme/app_shape.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';
import '../widgets/ui/book_motion.dart';
import 'book_widgets.dart';

/// Local book details: only metadata already owned by the library.
/// No catalogue request, account state, remote review or recommendation feed.
class BookDetailsPage extends StatefulWidget {
  const BookDetailsPage({
    required this.book,
    required this.progress,
    required this.onRead,
    this.onEditCover,
    super.key,
  });

  final ImportedBook book;
  final double progress;
  final Future<void> Function() onRead;
  final VoidCallback? onEditCover;

  @override
  State<BookDetailsPage> createState() => _BookDetailsPageState();
}

class _BookDetailsPageState extends State<BookDetailsPage> {
  bool _opening = false;

  Future<void> _read() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onRead();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final colors = context.c;
    final percent = (widget.progress.clamp(0.0, 1.0) * 100).round();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 300,
            child: BookAtmosphere(),
          ),
          Positioned.fill(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                      child: Row(
                        children: [
                          AppPressable(
                            onTap: () => Navigator.pop(context),
                            semanticLabel: '返回书库',
                            borderRadius: AppRadius.pillAll,
                            child: const SizedBox(
                              width: 48,
                              height: 44,
                              child: Icon(AppIcons.chevronBack, size: 25),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '本地书籍',
                            style: AppText.caption(colors.mutedForeground),
                          ),
                          if (widget.onEditCover != null) ...[
                            const SizedBox(width: 12),
                            AppPressable(
                              onTap: widget.onEditCover,
                              semanticLabel: '编辑封面',
                              borderRadius: AppRadius.pillAll,
                              child: const SizedBox(
                                width: 44,
                                height: 44,
                                child: Icon(AppIcons.photo, size: 20),
                              ),
                            ),
                          ] else
                            const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpace.contentMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.x6,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: AppSpace.x5),
                            _BookIdentity(book: book),
                            const SizedBox(height: AppSpace.x8),
                            BookPageReveal(
                              order: 1,
                              child: _ReadingProgress(
                                progress: widget.progress,
                                percent: percent,
                              ),
                            ),
                            const SizedBox(height: AppSpace.x8),
                            BookPageReveal(
                              order: 2,
                              child: _BookContents(book: book),
                            ),
                            const SizedBox(height: AppSpace.x6),
                            BookPageReveal(
                              order: 3,
                              child: Center(
                                child: Text(
                                  '保存在此设备 · 无需网络',
                                  style: AppText.caption(
                                    colors.mutedForeground,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 116 + bottomInset),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: BookPageReveal(
              order: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.background.withValues(alpha: 0),
                      colors.background,
                    ],
                    stops: const [0, .2],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(24, 30, 24, 14),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpace.contentMaxWidth,
                      ),
                      child: AppButton(
                        key: const Key('book-detail-read'),
                        label: percent > 0 ? '继续阅读 · $percent%' : '开始阅读',
                        icon: AppIcons.book,
                        busy: _opening,
                        expand: true,
                        pill: true,
                        size: AppButtonSize.large,
                        onPressed: _read,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookIdentity extends StatelessWidget {
  const _BookIdentity({required this.book});
  final ImportedBook book;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final cover = Hero(
      tag: bookCoverHeroTag(book.storageId),
      child: CoverThumb(
        book: book,
        // 118 wide at 1.4 is the reading-dock proportion: large enough to read
        // the artwork, small enough that the title beside it keeps two full
        // lines on a 360 dp phone.
        width: 118,
        height: 165,
        radius: AppRadius.md,
      ),
    );
    final metadata = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title,
          maxLines: 5,
          overflow: TextOverflow.ellipsis,
          // A named role, not a local copyWith: w800 and negative tracking were
          // a loudness fix that broke the type scale's semibold ceiling, and the
          // same 24pt heading appeared twice on this screen under two different
          // names.
          style: AppText.bookTitle(colors.foreground),
        ),
        const SizedBox(height: AppSpace.x2),
        Text(
          book.author.trim().isEmpty ? '未知作者' : book.author.trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          // Semibold, not a plain row: the author line reads as a byline under
          // the title, and regular weight at this size disappears next to it.
          style: AppText.rowTitle(
            colors.mutedForeground,
          ).copyWith(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpace.x5),
        Wrap(
          spacing: AppSpace.x2,
          runSpacing: AppSpace.x2,
          children: [
            AppChip(label: book.format.name.toUpperCase()),
            if (book.tocEntries.isNotEmpty)
              AppChip(label: '${book.tocEntries.length} 章节'),
          ],
        ),
        const SizedBox(height: AppSpace.x3),
        Text(
          '${book.paragraphCount} 段内容',
          style: AppText.caption(colors.mutedForeground),
        ),
      ],
    );
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (scale > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(height: AppSpace.x6),
          metadata,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cover,
        const SizedBox(width: AppSpace.x6),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.x2),
            child: metadata,
          ),
        ),
      ],
    );
  }
}

class _ReadingProgress extends StatelessWidget {
  const _ReadingProgress({required this.progress, required this.percent});
  final double progress;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '阅读进度',
                style: AppText.sectionHeader(colors.foreground),
              ),
            ),
            Text(
              percent == 0 ? '尚未开始' : '$percent%',
              style: AppText.rowDescription(colors.mutedForeground),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.x4),
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: motionDuration(context, AppMotion.slow),
            curve: AppMotion.settle,
            builder: (_, value, _) => SizedBox(
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(color: colors.secondary),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.primary),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookContents extends StatelessWidget {
  const _BookContents({required this.book});
  final ImportedBook book;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final entries = book.tocEntries.take(5).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '目录',
          style: AppText.bookTitle(colors.foreground),
        ),
        const SizedBox(height: AppSpace.x3),
        Text(
          '从这本书的本地目录开始，阅读时可随时跳转。',
          style: AppText.rowDescription(colors.mutedForeground),
        ),
        const SizedBox(height: AppSpace.x4),
        if (entries.isEmpty)
          Text(
            book.format == BookFormat.txt
                ? 'TXT 会在打开时读取章节索引。'
                : '这本书没有单独的章节标题，可连续阅读全文。',
            style: AppText.rowDescription(colors.mutedForeground),
          )
        else
          ClipRRect(
            borderRadius: AppRadius.groupedAll,
            child: ColoredBox(
              color: colors.card,
              child: Column(
                children: [
                  for (var index = 0; index < entries.length; index++) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: SizedBox(
                          height: 0.5,
                          child: ColoredBox(color: colors.border),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              '${index + 1}'.padLeft(2, '0'),
                              // mutedForeground, not foregroundTertiary: the
                            // tertiary role is declared for non-text graphics,
                            // and at 3.53:1 on the card this ordinal was under
                            // the text floor.
                            style: AppText.caption(colors.mutedForeground),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entries[index].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.rowDescription(colors.foreground),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
