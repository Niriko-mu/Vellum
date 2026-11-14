import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;

import '../services/book_importer.dart';
import '../services/book_library.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_page.dart';
import '../widgets/ui/app_pressable.dart';
import '../widgets/ui/app_section.dart';
import 'book_widgets.dart';

class HomePage extends StatelessWidget {
  final List<ImportedBook> books;
  final ReadingState? continueState;
  final ValueChanged<ImportedBook> onOpen;
  final VoidCallback onImport;
  const HomePage({
    required this.books,
    required this.onOpen,
    required this.onImport,
    this.continueState,
    super.key,
  });

  double get _continueProgress {
    final state = continueState;
    final book = continueBook;
    if (state == null || book == null) return 0;
    final total = book.paragraphCount;
    if (total <= 1) return 0;
    return (state.paragraphIndex / (total - 1)).clamp(0.0, 1.0);
  }

  /// Prefer the book that owns [continueState]; fall back to the newest.
  ImportedBook? get continueBook {
    if (books.isEmpty) return null;
    final state = continueState;
    if (state != null && state.bookId.isNotEmpty) {
      for (final book in books) {
        if (book.storageId == state.bookId) return book;
      }
    }
    return books.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.c;

    return CupertinoPageScaffold(
      backgroundColor: colors.background,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: colors.background,
        border: null,
        middle: const _Wordmark(),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onImport,
          child: Icon(CupertinoIcons.add, color: colors.primary),
        ),
      ),
      child: books.isEmpty
          ? AppPage(
              child: EmptyLibrary(onImport: onImport),
            )
          : AppPage(
              sections: [
                const SizedBox(height: AppSpace.x4),
                Text(
                  '继续阅读',
                  style: AppText.pageTitle(colors.foreground),
                ),
                const SizedBox(height: AppSpace.x4),
                _ContinueCard(
                  book: continueBook!,
                  progress: _continueProgress,
                  onTap: () => onOpen(continueBook!),
                ),
                if (books.length > 1) ...[
                  const SizedBox(height: AppSpace.x6),
                  _RecentHeader(count: books.length - 1),
                  const SizedBox(height: AppSpace.x2),
                  ClipRRect(
                    borderRadius: AppRadius.groupedAll,
                    child: ColoredBox(
                      color: colors.card,
                      child: Column(
                        children: [
                          for (var i = 1; i < books.length; i++) ...[
                            if (i > 1)
                              Padding(
                                padding: const EdgeInsets.only(left: 70),
                                child: SizedBox(
                                  height: appHairline(context),
                                  child: ColoredBox(color: colors.border),
                                ),
                              ),
                            BookRow(
                              book: books[i],
                              onTap: () => onOpen(books[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.x6),
                // The product's own voice, kept as a grouped footer.
                Center(
                  child: Text(
                    '安静地读一本书',
                    style: AppText.caption(colors.mutedForeground),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The wordmark is the one place letter spacing is allowed: it is brand
/// artwork, not running text.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Text(
    'VELLUM',
    style: AppText.sectionHeader(context.c.foreground).copyWith(
      letterSpacing: 2.2,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _RecentHeader extends StatelessWidget {
  const _RecentHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            '最近加入',
            style: AppText.sectionHeader(colors.foreground),
          ),
        ),
        Text('$count 本', style: AppText.caption(colors.mutedForeground)),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.progress,
    required this.onTap,
  });

  final ImportedBook book;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final percent = (progress * 100).round();

    return AppPressable(
      onTap: onTap,
      borderRadius: AppRadius.groupedAll,
      semanticLabel: '继续阅读《${book.title}》',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: AppRadius.groupedAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverThumb(book: book, width: 78, height: 112),
              const SizedBox(width: AppSpace.x4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.sectionHeader(colors.foreground),
                          ),
                        ),
                        const SizedBox(width: AppSpace.x2),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 20,
                          color: colors.foregroundTertiary,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.x2),
                    Text(
                      [
                        if (book.author.trim().isNotEmpty) book.author.trim(),
                        book.format.name.toUpperCase(),
                        '${book.paragraphCount} 段',
                      ].join(' · '),
                      style: AppText.caption(colors.mutedForeground),
                    ),
                    const SizedBox(height: AppSpace.x4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.hairlineXs),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: colors.border,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                    const SizedBox(height: AppSpace.x2),
                    // The bar already carries progress; the number does not
                    // need a second, louder encoding.
                    Text(
                      percent == 0 ? '从这里开始' : '已读 $percent%',
                      style: AppText.caption(colors.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
