import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';

void main() {
  final dir = Directory('developDoc/samples')..createSync(recursive: true);
  final archive = Archive()
    ..addFile(ArchiveFile.string('META-INF/container.xml',
        '<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>'));
  final items = StringBuffer();
  final spine = StringBuffer();
  final navPoints = StringBuffer();
  for (var i = 1; i <= 3; i++) {
    items.write('<item id="c$i" href="c$i.xhtml" media-type="application/xhtml+xml"/>');
    spine.write('<itemref idref="c$i"/>');
    navPoints.write('<navPoint><navLabel><text>第$i章 标题</text></navLabel>'
        '<content src="c$i.xhtml"/></navPoint>');
  }
  items.write('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');
  archive.addFile(ArchiveFile.string('OPS/book.opf',
      '<package><metadata><dc:title>EPUB巡检样本</dc:title><dc:creator>巡检作者</dc:creator></metadata>'
      '<manifest>$items</manifest><spine toc="ncx">$spine</spine></package>'));
  archive.addFile(ArchiveFile.string('OPS/toc.ncx',
      '<ncx><navMap>$navPoints</navMap></ncx>'));
  for (var i = 1; i <= 3; i++) {
    final body = List.generate(12, (p) =>
        '<p>这是 EPUB 第$i章的第${p + 1}段正文，用来验证渲染、分页与退出阅读页后的进度保存。'
        '中文标点，句号标点。测试文本长度足够形成多页内容。</p>').join();
    archive.addFile(ArchiveFile.string('OPS/c$i.xhtml',
        '<html><body><h1>第$i章 标题</h1>$body</body></html>'));
  }
  File('${dir.path}/inspect.epub').writeAsBytesSync(ZipEncoder().encode(archive));

  final text = utf8.encode(List.generate(20, (p) =>
      '<p>这是 MOBI 第${p + 1}段正文，用于验证移动端渲染与退出后阅读进度。</p>').join());
  final bytes = Uint8List(140 + text.length);
  final data = ByteData.sublistView(bytes);
  data.setUint16(76, 2, Endian.big);
  data.setUint32(78, 100, Endian.big);
  data.setUint32(86, 140, Endian.big);
  data.setUint16(100, 1, Endian.big);
  data.setUint32(104, text.length, Endian.big);
  data.setUint16(108, 1, Endian.big);
  data.setUint16(112, 0, Endian.big);
  data.setUint32(128, 65001, Endian.big);
  bytes.setRange(116, 120, [0x4d, 0x4f, 0x42, 0x49]);
  bytes.setRange(140, 140 + text.length, text);
  File('${dir.path}/inspect.mobi').writeAsBytesSync(bytes);
  stdout.writeln('regenerated with NCX');
}
