import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/app_shape.dart';

/// Window class follows the width actually available, scaled by the user's text
/// size, never the device identity.
enum AppWindowClass { compact, wide }

AppWindowClass appWindowClassOf(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final scaler = MediaQuery.textScalerOf(context).scale(16) / 16;
  return size.width / math.max(scaler, 0.01) >= 720
      ? AppWindowClass.wide
      : AppWindowClass.compact;
}

/// The page shell. It owns the horizontal gutter, the reading measure and the
/// bottom inset; rows inside it carry no outer margin, so a gutter can never be
/// applied twice.
class AppPage extends StatelessWidget {
  const AppPage({
    required this.child,
    this.padding,
    this.maxWidth = AppSpace.contentMaxWidth,
    this.safeArea = true,
    this.background,
    this.scrollable = false,
    this.controller,
    super.key,
  });

  final Widget child;

  /// Extra padding *inside* the gutter. Use it for section rhythm, never to
  /// re-create the gutter.
  final EdgeInsetsGeometry? padding;

  final double maxWidth;
  final bool safeArea;
  final Color? background;

  /// Wraps the child in a [ListView] so a page of sections scrolls and keeps its
  /// offset; `List<Widget>` children are expected in that case.
  final bool scrollable;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);

    Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter).add(
        EdgeInsets.only(bottom: insets.bottom + AppSpace.x6),
      ),
      child: child,
    );

    if (scrollable && child is List) {
      content = ListView(
        controller: controller,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter)
            .add(EdgeInsets.only(bottom: insets.bottom + AppSpace.x6)),
        children: [
          for (final item in child as List) item,
        ],
      );
    } else if (padding != null) {
      content = Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter)
            .add(padding!),
        child: child,
      );
    }

    Widget body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: content,
      ),
    );

    if (safeArea) body = SafeArea(top: false, bottom: false, child: body);

    if (background == null) return body;
    return ColoredBox(color: background!, child: body);
  }
}
