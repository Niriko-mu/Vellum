import 'package:flutter/cupertino.dart';

/// Quiet surfaces for the notes-style writing area; reader papers stay separate.
abstract final class WritingStyle {
  static bool isDark(BuildContext context) =>
      CupertinoTheme.brightnessOf(context) == Brightness.dark;

  static Color background(BuildContext context) =>
      isDark(context) ? const Color(0xff151412) : const Color(0xfff4f3f0);

  static Color paper(BuildContext context) =>
      isDark(context) ? const Color(0xff211f1c) : const Color(0xfffffefa);

  static Color field(BuildContext context) =>
      isDark(context) ? const Color(0xff2b2824) : const Color(0xffeae8e3);
}
