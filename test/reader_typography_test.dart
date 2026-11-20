import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_markup.dart';

/// Two things Chinese body typography has to get right, and both are cheap to
/// get subtly wrong: a heading that shouts, and an indent that is not quite two
/// characters wide.
void main() {
  group('chapter headings stay quiet', () {
    test('a level-1 heading is only modestly larger than the body', () {
      final scale = ReaderMarkup.headingFontScale(1);
      expect(
        scale,
        lessThan(1.35),
        reason: 'a heading marks a change of topic, not a change of volume',
      );
      expect(
        scale,
        greaterThan(1.0),
        reason: 'it must still read as a heading',
      );
    });

    test('deeper levels form a descending ramp ending near the body size', () {
      final scales = [
        1,
        2,
        3,
        4,
        5,
      ].map(ReaderMarkup.headingFontScale).toList();
      for (var i = 1; i < scales.length; i++) {
        expect(scales[i], lessThan(scales[i - 1]));
      }
      expect(scales.last, greaterThan(1));
      expect(scales.last, lessThan(1.1));
    });
  });

  group('first-line indent', () {
    test('CJK prose is indented by two full-width characters', () {
      final prefix = ReaderMarkup.indentPrefixFor('这是一段中文正文，用来确认缩进宽度。');
      expect(prefix.length, 2);
      // U+3000 IDEOGRAPHIC SPACE is a full-width blank; two of them is the
      // Chinese convention. Two ASCII spaces would be half as wide.
      expect(prefix, '\u3000\u3000');
    });

    test('Latin prose is indented by one em', () {
      final prefix = ReaderMarkup.indentPrefixFor(
        'This is a paragraph of English prose used to pick the indent width.',
      );
      expect(prefix, '\u2003');
    });

    test('a source that already indents itself is not indented twice', () {
      expect(
        ReaderMarkup.alreadyHasFirstLineIndent('\u3000\u3000开头已有缩进'),
        isTrue,
      );
      expect(ReaderMarkup.alreadyHasFirstLineIndent('没有缩进的开头'), isFalse);
    });
  });
}
