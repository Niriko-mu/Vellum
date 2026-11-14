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
    this.child,
    this.sections,
    this.padding,
    this.maxWidth = AppSpace.contentMaxWidth,
    this.safeArea = true,
    this.background,
    this.scrollable = false,
    this.controller,
    this.reserveDock = false,
    super.key,
  }) : assert(
         child != null || sections != null,
         'AppPage needs either a child or a list of sections',
       );

  final Widget? child;

  /// Page sections, stacked in order and scrollable. Use it for a page made of
  /// grouped blocks; use [child] for anything else.
  final List<Widget>? sections;

  /// Extra padding *inside* the gutter. Use it for section rhythm, never to
  /// re-create the gutter.
  final EdgeInsetsGeometry? padding;

  final double maxWidth;
  final bool safeArea;
  final Color? background;

  /// Wraps the content in a scroll view so a long page keeps its offset.
  final bool scrollable;
  final ScrollController? controller;

  /// Leaves room at the end of the page for the floating dock.
  ///
  /// The dock hovers over the content instead of owning a strip of it, so
  /// without this the last row scrolls under it and becomes untappable.
  final bool reserveDock;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewPaddingOf(context);

    // Leave room for the floating dock plus the home indicator. The dock
    // reserve already accounts for the gap below it, so adding the inset twice
    // would push the last row a whole dock further up than needed.
    final bottom = reserveDock
        ? AppSpace.dockReserve(insets.bottom)
        : insets.bottom + AppSpace.x6;
    // The page owns the gap between the chrome and its first element. A page
    // that writes its own leading spacer is how the rhythm drifted before.
    final top = AppSpace.pageTopGap;
    final gutter = padding == null
        ? const EdgeInsets.symmetric(
            horizontal: AppSpace.pageGutter,
          ).add(EdgeInsets.only(top: top, bottom: bottom))
        : const EdgeInsets.symmetric(horizontal: AppSpace.pageGutter)
              .add(padding!)
              .add(EdgeInsets.only(top: top, bottom: bottom));

    final Widget content;
    if (sections != null) {
      content = ListView(
        controller: controller,
        padding: gutter,
        children: sections!,
      );
    } else if (scrollable) {
      content = SingleChildScrollView(
        controller: controller,
        padding: gutter,
        child: child,
      );
    } else {
      content = Padding(padding: gutter, child: child);
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
