import 'package:flutter/cupertino.dart';

import '../services/book_importer.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';
import '../widgets/ui/book_motion.dart';
import '../theme/app_icons.dart';

/// Destructive affordance shared by the grid cover and the list row.
///
/// The cover variant is a dark disc so it stays legible on any artwork; the row
/// variant uses the neutral overlay. Neither is a shadowed chip.
class LibraryDeleteButton extends StatelessWidget {
  const LibraryDeleteButton({
    required this.onPressed,
    this.onCover = false,
    super.key,
  });

  final VoidCallback onPressed;

  /// Overlay style for book covers; false for list rows.
  final bool onCover;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final size = onCover ? 30.0 : 32.0;

    return AppPressable(
      onTap: onPressed,
      semanticLabel: '删除这本书',
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: onCover
                  ? colors.constantBlack.withValues(alpha: 0.42)
                  : colors.secondary,
              shape: BoxShape.circle,
              border: Border.all(
                color: onCover
                    ? colors.constantWhite.withValues(alpha: 0.28)
                    : colors.border,
              ),
            ),
            child: Icon(
              AppIcons.trash,
              color: onCover ? colors.constantWhite : colors.destructive,
              size: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyLibrary extends StatelessWidget {
  final VoidCallback onImport;

  /// Debug-only escape hatch: seeds a book from the bundled fixture so the
  /// reader can be exercised on a device without the system file picker. The
  /// caller decides whether to pass it; this widget stays free of build-mode
  /// logic of its own.
  final VoidCallback? onDebugSeed;

  const EmptyLibrary({required this.onImport, this.onDebugSeed, super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppContentState(
          kind: AppContentStateKind.empty,
          icon: AppIcons.book,
          title: '书房还没有书',
          description: '导入 EPUB、MOBI 或 TXT，开始你的私人书房。',
          actions: [AppButton(label: '导入电子书', pill: true, onPressed: onImport)],
        ),
        if (onDebugSeed != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.x2),
            child: AppTextButton(
              key: const Key('debug-seed-book'),
              label: '导入测试书（调试）',
              onPressed: onDebugSeed,
            ),
          ),
      ],
    ),
  );
}

class BookGridCard extends StatelessWidget {
  final ImportedBook book;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onLongPress;
  const BookGridCard({
    required this.book,
    required this.onTap,
    required this.onDelete,
    this.progress = 0,
    this.onLongPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final percent = (progress * 100).round();
    final metaLine = [
      if (book.author.trim().isNotEmpty) book.author.trim(),
      book.format.name.toUpperCase(),
    ].join(' · ');

    return GestureDetector(
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AppPressable(
                    onTap: onTap,
                    borderRadius: AppRadius.mdAll,
                    semanticLabel: '打开《${book.title}》',
                    child: Hero(
                      // The grid cover flies to the details cover. Tagged by
                      // storage id: two books with the same title must not
                      // share a flight.
                      tag: bookCoverHeroTag(book.storageId),
                      child: ClipRRect(
                        borderRadius: AppRadius.mdAll,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            book.coverBytes == null
                                ? DefaultCover(book: book)
                                : Image.memory(
                                    book.coverBytes!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 640,
                                    errorBuilder: (_, _, _) =>
                                        DefaultCover(book: book),
                                  ),
                            // Reading progress as a small badge on the cover's
                            // top-right corner, inset 4 — the shelf convention.
                            // A full-width bar across the bottom of every cover
                            // fights the artwork and outweighs the title below.
                            if (percent > 0)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: _ProgressBadge(percent: percent),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: LibraryDeleteButton(
                    onPressed: onDelete,
                    onCover: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.x2),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.rowDescription(colors.foreground),
          ),
          const SizedBox(height: 2),
          Text(
            metaLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: AppText.caption(colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

/// The reading-progress badge on a cover: a small pill in the cover's
/// top-right corner.
///
/// It sits on uncontrolled artwork, so it uses the constant chrome colours
/// rather than a theme role — a themed fill would change with day/night while
/// the cover behind it does not.
class _ProgressBadge extends StatelessWidget {
  const _ProgressBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(
            '$percent%',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TextStyle(
              color: colors.primaryForeground,
              fontSize: 9,
              height: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class DefaultCover extends StatelessWidget {
  final ImportedBook book;
  const DefaultCover({required this.book, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    // A generated cover shows the book, not the file extension. Two shelves of
    // "TXT" tiles are indistinguishable; the title is the only thing that makes
    // a cover identifiable at a glance, which is the job a cover does.
    if (book.coverText?.isNotEmpty ?? false) {
      return ColoredBox(
        color: colors.primary,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.x3),
          child: Center(
            child: Text(
              book.coverText!,
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(
                colors.primaryForeground,
              ).copyWith(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      );
    }
    return _GeneratedCover(book: book);
  }
}

/// A cover drawn from the book's own metadata: title, author, and the format in
/// a quiet corner.
class _GeneratedCover extends StatelessWidget {
  const _GeneratedCover({required this.book});

  final ImportedBook book;

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final title = book.title.trim().isEmpty ? '未命名' : book.title.trim();
    final author = book.author.trim();
    return ColoredBox(
      // Artwork, not a surface: one flat brand fill instead of a gradient.
      color: colors.primary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Type has to follow the tile: the same widget is used for a 42 pt
          // list thumbnail and a 200 pt grid cover.
          final w = constraints.maxWidth;
          final scale = (w / 120).clamp(.55, 1.6);
          return Padding(
            padding: EdgeInsets.all(AppSpace.x3 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(colors.primaryForeground).copyWith(
                      fontSize: 12 * scale,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (author.isNotEmpty || w > 60)
                  Text(
                    author.isEmpty ? book.format.name.toUpperCase() : author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption(
                      colors.primaryForeground.withValues(alpha: .78),
                    ).copyWith(fontSize: 9 * scale, height: 1.2),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class BookRow extends StatelessWidget {
  final ImportedBook book;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const BookRow({
    required this.book,
    required this.onTap,
    this.onDelete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    return AppPressable(
      onTap: onTap,
      onLongPress: onDelete,
      semanticLabel: book.title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpace.rowMinHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.x3,
            vertical: AppSpace.x2,
          ),
          child: Row(
            children: [
              CoverThumb(book: book, width: 42, height: 58, radius: 4.8),
              const SizedBox(width: AppSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.rowTitle(colors.foreground),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (book.author.trim().isNotEmpty) book.author.trim(),
                        book.format.name.toUpperCase(),
                        '${book.paragraphCount} 段',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption(colors.mutedForeground),
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                LibraryDeleteButton(onPressed: onDelete!)
              else
                Icon(
                  AppIcons.chevronRight,
                  size: 20,
                  color: colors.foregroundTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CoverThumb extends StatelessWidget {
  const CoverThumb({
    super.key,
    required this.book,
    required this.width,
    required this.height,
    this.radius = 6.4,
  });

  final ImportedBook book;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.c.border),
      ),
      position: DecorationPosition.foreground,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: book.coverBytes == null
            ? DefaultCover(book: book)
            : Image.memory(
                book.coverBytes!,
                fit: BoxFit.cover,
                cacheWidth: (width * 2.5).round(),
                errorBuilder: (_, _, _) => DefaultCover(book: book),
              ),
      ),
    ),
  );
}
