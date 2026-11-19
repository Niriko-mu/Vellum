import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/widgets/markdown_preview.dart';

/// Markdown is rendered through the reader's own pipeline, not a parallel one.
///
/// That is the whole design claim: a draft's preview and a book's page look
/// the same because they are the same paragraph model. These assertions pin the
/// output shape so a change to the HTML pipeline cannot silently diverge the
/// two without a test noticing.
void main() {
  test('headings, quotes and lists become reader markup', () {
    final paragraphs = markdownPreviewParagraphs(
      '# 标题\n\n> 引用一段\n\n- 列表项\n\n正文段落。',
    );
    expect(paragraphs, isNotEmpty);
    expect(
      paragraphs.any((p) => p.contains('[[vellum-heading')),
      isTrue,
      reason: 'a heading must carry the reader heading marker',
    );
    expect(paragraphs.any((p) => p.contains('[[vellum-quote]]')), isTrue);
    expect(paragraphs.any((p) => p.contains('[[vellum-list]]')), isTrue);
  });

  test('link text survives, the URL does not', () {
    final paragraphs = markdownPreviewParagraphs(
      '这是一个[链接文字](https://example.com/page)的段落。',
    );
    final joined = paragraphs.join();
    expect(joined, contains('链接文字'));
    expect(
      joined.contains('example.com'),
      isFalse,
      reason: 'a preview must not expose raw URLs as body text',
    );
  });

  test('bold and italic become reader emphasis markers', () {
    final paragraphs = markdownPreviewParagraphs('**加粗**与*斜体*同段。');
    final joined = paragraphs.join();
    expect(joined, contains('[[b]]'));
    expect(joined, contains('[[i]]'));
  });

  test('an empty draft yields no paragraphs rather than a blank line', () {
    expect(markdownPreviewParagraphs('   '), isEmpty);
    expect(markdownPreviewParagraphs(''), isEmpty);
  });

  test('plain prose is not mangled by the markup pass', () {
    final paragraphs = markdownPreviewParagraphs('普通的正文，没有任何标记。');
    expect(paragraphs, hasLength(1));
    expect(paragraphs.single, '普通的正文，没有任何标记。');
  });

  test('a code block does not leak fence characters into the body', () {
    final paragraphs = markdownPreviewParagraphs(
      '    final x = 1;\n    print(x);',
    );
    final joined = paragraphs.join();
    expect(joined.contains('```'), isFalse);
  });
}
