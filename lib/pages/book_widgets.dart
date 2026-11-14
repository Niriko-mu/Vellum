import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;

import '../services/book_importer.dart';
import '../theme/app_colors.dart';
import '../theme/app_shape.dart';
import '../theme/app_type.dart';
import '../widgets/ui/app_controls.dart';
import '../widgets/ui/app_pressable.dart';

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
              CupertinoIcons.trash,
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
  const EmptyLibrary({required this.onImport, super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: AppContentState(
      kind: AppContentStateKind.empty,
      icon: CupertinoIcons.book,
      title: '书房还没有书',
      description: '导入 EPUB、MOBI 或 TXT，开始你的私人书房。',
      actions: [
        AppButton(label: '导入电子书', pill: true, onPressed: onImport),
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
                          // Reading progress sits on the cover itself, so it is
                          // chrome over uncontrolled content: constant colours
                          // only, never a theme role.
                          if (percent > 0)
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      colors.constantBlack.withValues(alpha: 0),
                                      colors.constantBlack.withValues(
                                        alpha: 0.55,
                                      ),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(AppRadius.hairlineXs),
                                        child: LinearProgressIndicator(
                                          value: progress.clamp(0.0, 1.0),
                                          minHeight: 3,
                                          backgroundColor: colors.constantWhite
                                              .withValues(alpha: 0.25),
                                          valueColor: AlwaysStoppedAnimation(
                                            colors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$percent%',
                                      style: AppText.caption(
                                        colors.constantWhite,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
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

class DefaultCover extends StatelessWidget {
  final ImportedBook book;
  const DefaultCover({required this.book, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.c;
    final label = (book.coverText?.isNotEmpty ?? false)
        ? book.coverText!
        : book.format.name.toUpperCase();
    final isCustom = book.coverText?.isNotEmpty ?? false;
    return ColoredBox(
      // Artwork, not a surface: one flat brand fill instead of a gradient.
      color: colors.primary,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.x3),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: isCustom ? 6 : 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption(colors.primaryForeground).copyWith(
              fontSize: isCustom ? 14 : 11,
              fontWeight: isCustom ? FontWeight.w500 : FontWeight.w600,
              letterSpacing: isCustom ? 0 : 1.4,
            ),
          ),
        ),
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
                  CupertinoIcons.chevron_right,
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