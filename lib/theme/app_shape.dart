import 'package:flutter/widgets.dart';

/// Shape scale. Base 8; every other step is a multiplier, so the whole scale
/// moves together. A new radius is a change to this file, never a local number
/// in a widget.
abstract final class AppRadius {
  /// Badge corners.
  static const double hairlineXs = 2;

  /// Inner chips, small controls.
  static const double sm = 4.8;

  /// Thumbnails, cover tiles. The only card corner below [lg], because a book
  /// cover is a physical object and wants a sharper corner than a UI card.
  static const double md = 6.4;

  /// Fields, small cards.
  static const double lg = 8;

  /// Default button, input.
  static const double xl = 11.2;

  /// Grouped section block.
  static const double grouped = 14.4;

  /// Cover tile stack, floating control container.
  static const double xl2 = 17.6;

  /// Menu panel, sheet top corner.
  static const double xl3 = 20.8;

  /// The floating bottom dock: 8 x 3.
  ///
  /// A declared extra step (see design-fidelity-overrides.md #5). The capsule
  /// needs a rounder corner than [xl3] because it is thumb-height rather than
  /// content-height — a shallower corner on a 64pt capsule reads as a rectangle
  /// with clipped ends — but it still belongs to the base-8 scale rather than
  /// sitting off it at 26.8.
  static const double dock = 24;

  /// Chips, tags, switch, avatar.
  static const double pill = 9999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get groupedAll => BorderRadius.circular(grouped);
  static BorderRadius get xl2All => BorderRadius.circular(xl2);
  static BorderRadius get xl3All => BorderRadius.circular(xl3);
  static BorderRadius get pillAll => BorderRadius.circular(pill);

  /// Sheet presentation: top corners only, the bottom runs off screen.
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(xl3),
  );
}

/// Spacing ladder: 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 44 / 56 / 64.
abstract final class AppSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x11 = 44;
  static const double x14 = 56;
  static const double x16 = 64;

  /// Page gutter, owned by the page shell. Rows carry no outer margin.
  static const double pageGutter = x4;

  /// Gap between the navigation chrome and the first thing on the page,
  /// owned by [AppPage] so a page never writes its own leading spacer.
  static const double pageTopGap = x2;

  /// Gap between two grouped sections.
  static const double sectionGap = x6;

  /// Row height floor. Not a ceiling: a single-line row is 16/24 text plus 12
  /// top and bottom padding = 48 naturally, and a two-line row grows to 72.
  /// A fixed height would clip at large text sizes.
  static const double rowMinHeight = x10;

  /// Grouped section header height.
  static const double sectionHeaderMinHeight = x10;

  /// Separator inset when rows carry a leading glyph: 16 padding + 16 glyph +
  /// 12 gap, so the hairline starts where the label does.
  static const double separatorInsetAfterLeading = x4 + x4 + x3;

  /// Separator inset when rows have no leading glyph.
  static const double separatorInset = x3;

  /// Reading measure cap on tablets and desktop windows.
  static const double contentMaxWidth = 720;

  /// Sidebar width in the wide window class.
  static const double sidebarWidth = 280;

  // -------------------------------------------------------- floating dock --
  // The bottom dock floats over the page instead of owning a strip of it, so
  // the page needs a matching reservation or its last row sits under the dock.

  /// Height of the dock capsule itself (icons + labels, no insets).
  ///
  /// 54, not 64: at 64 the capsule reads as a bar with icons in it rather than
  /// as a floating pill, and it eats room the page needed. The label sits on
  /// the type scale's floor, so the capsule only has to carry an icon and one
  /// line of text.
  static const double dockHeight = 54;

  /// Distance from the bottom safe area to the dock's underside.
  static const double dockBottomGap = 10;

  /// Side inset of the dock from the window edge.
  static const double dockSideInset = 20;

  /// Total vertical space a scrolling page must leave free at its end: the dock
  /// plus both gaps plus the home indicator.
  static double dockReserve(double bottomInset) =>
      dockHeight + dockBottomGap * 2 + bottomInset;
}
