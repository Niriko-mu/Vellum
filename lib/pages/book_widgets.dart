import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show LinearProgressIndicator;

import '../services/book_importer.dart';
import '../theme/vellum_theme.dart';

/// Destructive affordance shared by the grid cover and the list row.
///
/// Cover variant is a dark glass disc so it stays legible on any artwork;
/// row variant is a soft red disc that sits cleanly on the paper surface.
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
    final size = onCover ? 32.0 : 34.0;
    final iconSize = onCover ? 15.0 : 17.0;
    final background = onCover
        ? CupertinoColors.black.withValues(alpha: .42)
        : CupertinoColors.systemRed.withValues(alpha: .12);
    final iconColor = onCover
        ? CupertinoColors.white
        : CupertinoColors.systemRed;
    return CupertinoButton(
      padding: EdgeInsets.all(onCover ? 7 : 8),
      // Comfortable 44pt-class target without growing the visual disc.
      minimumSize: Size(size + 14, size + 14),
      pressedOpacity: .55,
      onPressed: onPressed,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(
            color: onCover
                ? CupertinoColors.white.withValues(alpha: .28)
                : CupertinoColors.systemRed.withValues(alpha: .22),
            width: 1,
          ),
          boxShadow: onCover
              ? [
                  BoxShadow(
                    color: CupertinoColors.black.withValues(alpha: .28),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Icon(
          CupertinoIcons.trash,
          color: iconColor,
          size: iconSize,
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
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: VellumTheme.softAccentOf(context),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.book,
              size: 34,
              color: VellumTheme.accentOf(context),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            '书库是空的',
            style: TextStyle(
              fontFamily: VellumTheme.fontFamily,
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: VellumTheme.inkOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '导入 EPUB、MOBI 或 TXT，开始你的私人书房。',
            textAlign: TextAlign.center,
            style: TextStyle(color: VellumTheme.mutedOf(context), height: 1.4),
          ),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            borderRadius: BorderRadius.circular(14),
            onPressed: onImport,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text('导入电子书'),
            ),
          ),
        ],
      ),
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
    final muted = VellumTheme.mutedOf(context);
    final accent = VellumTheme.accentOf(context);
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
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: onTap,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: VellumTheme.lineOf(context),
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: CupertinoColors.black.withValues(alpha: .06),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      position: DecorationPosition.foreground,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
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
                            // Fanqie shows reading progress on the cover itself.
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
                                        CupertinoColors.black.withValues(
                                          alpha: 0,
                                        ),
                                        CupertinoColors.black.withValues(
                                          alpha: .55,
                                        ),
                                      ],
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                          child: LinearProgressIndicator(
                                            value: progress.clamp(0.0, 1.0),
                                            minHeight: 3,
                                            backgroundColor: CupertinoColors
                                                .white
                                                .withValues(alpha: .25),
                                            valueColor: AlwaysStoppedAnimation(
                                              accent,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$percent%',
                                        style: const TextStyle(
                                          color: CupertinoColors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
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
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: LibraryDeleteButton(onPressed: onDelete, onCover: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: VellumTheme.inkOf(context),
              fontFamily: VellumTheme.fontFamily,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            metaLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11),
          ),
          if (percent > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '已读 $percent%',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    final label = (book.coverText?.isNotEmpty ?? false)
        ? book.coverText!
        : book.format.name.toUpperCase();
    final isCustom = book.coverText?.isNotEmpty ?? false;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            VellumTheme.accentOf(context).withValues(alpha: .88),
            VellumTheme.accentOf(context).withValues(alpha: .62),
          ],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: isCustom ? 6 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: isCustom ? 14 : 11,
          fontWeight: FontWeight.w700,
          letterSpacing: isCustom ? 0 : 1.4,
          height: 1.3,
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
  Widget build(BuildContext context) => CupertinoButton(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    onPressed: onTap,
    child: Row(
      children: [
        CoverThumb(book: book, width: 42, height: 58, radius: 4),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: VellumTheme.inkOf(context),
                  fontFamily: VellumTheme.fontFamily,
                  fontSize: 16,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (book.author.trim().isNotEmpty) book.author.trim(),
                  book.format.name.toUpperCase(),
                  '${book.paragraphCount} 段',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: VellumTheme.mutedOf(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (onDelete != null)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: LibraryDeleteButton(onPressed: onDelete!),
          )
        else
          Icon(
            CupertinoIcons.chevron_right,
            size: 16,
            color: VellumTheme.mutedOf(context).withValues(alpha: .7),
          ),
      ],
    ),
  );
}

class CoverThumb extends StatelessWidget {
  const CoverThumb({
    super.key,
    required this.book,
    required this.width,
    required this.height,
    this.radius = 6,
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
        border: Border.all(color: VellumTheme.lineOf(context)),
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
