/// Common reader contract for disk-backed, bounded paragraph lists.
abstract interface class LazyParagraphs implements List<String> {
  Future<void> prefetchAroundParagraph(int index);
  bool isParagraphCached(int index);
  int blockEndForParagraph(int index);
  int get totalCharacters;
  int charactersBefore(int index);
  void close();
}
