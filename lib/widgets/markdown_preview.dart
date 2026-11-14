import 'package:flutter/cupertino.dart';
import 'package:markdown/markdown.dart' as markdown;

import '../reader/reader_models.dart';
import '../reader/reader_paragraph.dart';
import '../services/book_importer.dart';
import '../services/html_text_pipeline.dart';
import '../theme/vellum_theme.dart';
import '../theme/app_colors.dart';

/// Renders a Markdown draft through the reader's own text pipeline:
/// `markdown` → HTML → reader markup → paragraphs. Everything happens on
/// device, so a preview needs no network and no HTML engine.
List<String> markdownPreviewParagraphs(String source) {
  final body = source.trim();
  if (body.isEmpty) return const [];
  return const HtmlTextPipeline()
      .convert(markdown.markdownToHtml(body), 'draft.md')
      .paragraphs;
}

/// Read-only preview of a draft body, styled like the reading page.
class MarkdownPreview extends StatefulWidget {
  const MarkdownPreview({
    required this.source,
    this.fontSize = 16.5,
    super.key,
  });

  final String source;
  final double fontSize;

  @override
  State<MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<MarkdownPreview> {
  late List<String> _paragraphs = markdownPreviewParagraphs(widget.source);

  @override
  void didUpdateWidget(covariant MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The body only changes between previews, so converting here keeps every
    // other rebuild free.
    if (oldWidget.source != widget.source) {
      _paragraphs = markdownPreviewParagraphs(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = context.c.mutedForeground;
    if (_paragraphs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            '还没有内容，切回编辑写点什么。',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 14, height: 1.5),
          ),
        ),
      );
    }
    // A shell book keeps ReaderParagraph's link/image lookups empty: a preview
    // has no jump targets and must never fetch a remote image.
    final book = ImportedBook(
      title: '',
      format: BookFormat.txt,
      paragraphs: _paragraphs,
    );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      itemCount: _paragraphs.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: ReaderParagraph(
          book: book,
          paragraph: _paragraphs[index],
          paragraphIndex: index,
          fontSize: widget.fontSize,
          fontFamily: VellumTheme.contentFontFamily,
          lineSpacing: ReaderLineSpacing.standard,
          fontWeight: ReaderFontWeight.regular,
          ink: context.c.foreground,
          showImage: false,
          showLinkAction: false,
          indentFirstLine: false,
          isChapterHeading: false,
          contextMenuBuilder: _previewToolbar,
        ),
      ),
    );
  }

  /// Platform copy/select toolbar — the reader-only actions (note, translate)
  /// make no sense for a draft.
  static Widget _previewToolbar(
    BuildContext context,
    EditableTextState editableTextState,
  ) => CupertinoAdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: editableTextState.contextMenuButtonItems,
  );
}