import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import 'reader_gestures.dart';
import 'reader_models.dart';
import 'reader_selection.dart';
import 'tts_audio_handler.dart';
import '../services/tts_text.dart' show sentenceAt;

import 'reader_page_state.dart';
import 'reader_page_state_pagination.dart';
import 'reader_page_state_surface_rendering.dart';

extension ReaderPageGestures on ReaderPageState {
  Widget bookmarkPullIndicator(BuildContext context) {
    final threshold = ReaderGestures.bookmarkPullThreshold;
    final progress = (pullDownDistance / threshold).clamp(0.0, 1.2);
    final armed = pullDownDistance >= threshold;
    final already = isCurrentViewBookmarked;
    final label = already
        ? (armed ? '松开取消书签' : '下拉取消书签')
        : (armed ? '松开添加书签' : '下拉添加书签');
    return BookmarkRibbon(
      surface: backgroundFor(context),
      progress: progress,
      armed: armed,
      alreadyBookmarked: already,
      label: label,
    );
  }

  Color backgroundFor(BuildContext context) =>
      background ??
      (CupertinoTheme.of(context).brightness == Brightness.dark
          ? VellumTheme.readerNight
          : VellumTheme.readerWhite);
  bool isScrollIdle() => true;
  void handleReaderPointerMove(PointerMoveEvent event) {
    final down = readerPointerDownPosition;
    if (down == null) return;
    // Only treat a clear intentional slide as "dismiss chrome". A 18px
    // threshold made every careful tap near a button feel broken.
    if (showControls) {
      final dx = event.position.dx - down.dx;
      final dy = event.position.dy - down.dy;
      if (dx * dx + dy * dy > 72 * 72) {
        refresh(() => showControls = false);
      }
    }
    final atTop =
        readingMode != ReadingMode.scroll ||
        (!scrollController.hasClients || scrollController.offset <= 2);
    if (!atTop) {
      if (pullDownDistance != 0) {
        refresh(() => pullDownDistance = 0);
      }
      return;
    }
    final dy = event.position.dy - down.dy;
    final dx = event.position.dx - down.dx;
    // A deliberate downward bookmark pull owns this gesture. Interrupt the
    // PageView as soon as the vertical intent is clear so a slight diagonal
    // movement cannot turn the page underneath the bookmark interaction.
    if (readingMode == ReadingMode.page &&
        !pointerLooksLikeSelection &&
        dy > 18 &&
        dy > dx.abs() * 1.25) {
      bookmarkPullInProgress = true;
      restorePageAfterBookmarkPull();
    }
    // Once a turn drag is active, keep following the finger even if the
    // long-press selection timer fires — freezing mid-swipe left the page
    // stuck in the middle of the screen.
    if (readingMode == ReadingMode.page &&
        (dragTurn || !pointerLooksLikeSelection) &&
        !bookmarkPullInProgress &&
        !coverJumping &&
        !slideBusy) {
      updateDragTurn(dx);
    }
    // Bookmark pull is vertical; a turn drag must not also rebuild the page
    // for a meaningless `pullDownDistance` tick (that was drag stutter).
    if (dragTurn || bookmarkPullInProgress) return;
    final next = dy > 0 ? dy : 0.0;
    if ((next - pullDownDistance).abs() > 0.5) {
      refresh(() => pullDownDistance = next);
    }
  }

  void restorePageAfterBookmarkPull() {
    if (readingMode != ReadingMode.page ||
        !pageController.hasClients ||
        pageCount <= 0) {
      return;
    }
    final page = pageBeforePointerDown.clamp(0, pageCount - 1);
    pageController.jumpToPage(page);
    if (currentPage != page) {
      refresh(() {
        currentPage = page;
        requestedPage = page;
      });
    }
  }

  /// Begin/update a finger-driven page turn. Progress maps 1:1 to drag
  /// distance so the overlay follows the hand instead of playing a canned
  /// animation only after release.
  ///
  /// Updates write straight into [coverAnim] (the overlay's listenable) and
  /// skip the page-level [setState]: a full rebuild per pointer-move is what
  /// made the turn stutter mid-drag. Only the start/reverse paths need a
  /// rebuild, to mount or retarget the overlay.
  void updateDragTurn(double dx) {
    const intent = 10.0;
    if (!dragTurn) {
      if (dx.abs() < intent) return;
      var totalPages = pageCount;
      if (totalPages <= 0) return;
      var from = currentPage.clamp(0, totalPages - 1);
      var to = dx < 0 ? from + 1 : from - 1;
      if (to < 0 && dx > 0) {
        // Rightward drags from the first page of an anchored deep window need
        // the same bounded predecessor materialisation as screen taps.
        final prepared = preparePreviousPage();
        if (prepared == null) return;
        totalPages = pageCount;
        from = prepared;
        to = from - 1;
      }
      if (to < 0 || to >= totalPages) return;
      if (!pager.fullyPaginated && to >= pager.pageCount - 1) {
        pager.paginateUntilPages(to + 2);
      }
      coverAnim.stop();
      dragTurn = true;
      dragCommitted = false;
      dragFromPage = from;
      dragToPage = to;
      dragProgress = 0;
      dragLastTravel = 0;
      dragLastMicros = DateTime.now().microsecondsSinceEpoch;
      dragVelocity = 0;
      coverFromPage = from;
      coverToPage = to;
      requestedPage = to;
      coverAnim.value = 0;
      refresh(() {});
      return;
    }
    var from = dragFromPage;
    var to = dragToPage;
    if (from == null || to == null) return;
    final width = MediaQuery.sizeOf(context).width;
    final span = width == 0 ? 1.0 : width;
    // +travel = moving toward [to].
    var travel = (to > from ? -dx : dx);
    // Finger crossed back through the origin: reverse the turn target so the
    // page tracks the hand instead of pinning progress at 0.
    if (travel < -intent && dragProgress <= 0.02) {
      final oldFrom = from;
      from = to;
      to = oldFrom;
      dragFromPage = from;
      dragToPage = to;
      coverFromPage = from;
      coverToPage = to;
      requestedPage = to;
      travel = -travel;
      dragLastTravel = travel;
      refresh(() {});
    }
    final p = (travel / span).clamp(0.0, 1.0);
    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - dragLastMicros) / 1e6;
    if (dt > 0) {
      dragVelocity = (travel - dragLastTravel) / dt;
    }
    dragLastTravel = travel;
    dragLastMicros = now;
    dragProgress = p;
    // The overlay listens to [coverAnim]; assigning value notifies it and
    // repaints just the turn layer, not the whole reader page.
    if (coverAnim.value != p) {
      coverAnim.value = p;
    }
  }

  void cancelDragTurn() {
    dragCommitted = false;
    dragTurn = false;
    dragFromPage = null;
    dragToPage = null;
    dragProgress = 0;
    dragVelocity = 0;
    coverFromPage = null;
    coverToPage = null;
  }

  /// Release a finger-driven turn: finish past ~38% (or a fast flick),
  /// otherwise spring back. Always settles — never parks the overlay
  /// mid-screen.
  void endDragTurn() {
    if (!dragTurn) return;
    final from = dragFromPage;
    final to = dragToPage;
    final progress = dragProgress;
    final velocityTravel = dragVelocity;
    dragTurn = false;
    if (from == null || to == null) {
      cancelDragTurn();
      return;
    }
    final flick = velocityTravel > 700;
    final commit = progress >= 0.38 || (flick && progress > 0.05);
    // A committed drag is a page turn like any other.
    if (commit) onPageTurned();

    if (!commit && progress <= 0.01) {
      cancelDragTurn();
      refresh(() {
        currentPage = from;
        requestedPage = from;
      });
      return;
    }

    if (pageTurnStyle == PageTurnStyle.none && commit) {
      cancelDragTurn();
      refresh(() {
        currentPage = to;
        requestedPage = to;
      });
      jumpToPageExact(to);
      scheduleSave();
      return;
    }

    // Keep dragCommitted on for the whole settle so the overlay reads
    // raw controller value (no curve jump at release).
    coverFromPage = from;
    coverToPage = to;
    requestedPage = commit ? to : from;
    coverAnim.stop();
    coverAnim.value = progress.clamp(0.0, 1.0);
    dragCommitted = true;
    refresh(() {});

    final end = commit ? 1.0 : 0.0;
    if (coverAnim.value == end) {
      dragCommitted = false;
      if (commit) {
        finishCoverTurn(to);
      } else {
        cancelDragTurn();
        refresh(() {
          currentPage = from;
          requestedPage = from;
        });
      }
      return;
    }

    coverAnim
        .animateTo(
          end,
          duration: commit
              ? const Duration(milliseconds: 160)
              : const Duration(milliseconds: 160),
        )
        .whenCompleteOrCancel(() {
          if (!mounted) return;
          if (dragTurn) return; // a newer drag took over
          dragCommitted = false;
          if (commit && coverAnim.isCompleted) {
            finishCoverTurn(to);
            return;
          }
          cancelDragTurn();
          refresh(() {
            currentPage = commit ? to : from;
            requestedPage = commit ? to : from;
          });
        });
  }

  void handleReaderPointerUp(BuildContext context, PointerUpEvent event) {
    final pressedAt = readerPointerDownAt;
    final pressedPosition = readerPointerDownPosition;
    final selectionGesture =
        pointerLooksLikeSelection ||
        (lastSelectedText.isNotEmpty && pullDownDistance > 0);
    final wasBookmarkPull = bookmarkPullInProgress;
    if (wasBookmarkPull) restorePageAfterBookmarkPull();
    bookmarkPullInProgress = false;
    final wasDragTurn = dragTurn;
    if (wasDragTurn) {
      endDragTurn();
    }
    readerPointerDownAt = null;
    readerPointerDownPosition = null;
    pointerLooksLikeSelection = false;
    if (pullDownDistance != 0) {
      refresh(() => pullDownDistance = 0);
    }
    // Drag-turn already resolved the gesture — do not also fire a tap/swipe.
    if (wasDragTurn) return;
    final size = MediaQuery.sizeOf(context);
    final beginsAtScrollTop =
        readingMode != ReadingMode.scroll ||
        (!scrollController.hasClients || scrollController.offset <= 2);
    final action = ReaderGestures.resolvePointerUp(
      downAt: pressedAt,
      downPosition: pressedPosition,
      upPosition: event.position,
      mode: readingMode,
      beginsAtScrollTop: beginsAtScrollTop,
      isIdle: isScrollIdle(),
      screenWidth: size.width,
      screenHeight: size.height,
      selectionGesture: selectionGesture,
    );
    dispatchTap(action, event.position);
  }

  /// While a listen session is armed, single taps wait out the double-tap
  /// window (200 ms, the reference reader's
  /// `key_audio_reader_double_click_interval_time`) so a second tap can speak
  /// the tapped sentence; otherwise the action runs immediately.
  void dispatchTap(ReaderTapAction action, Offset upPosition) {
    final listenArmed = ttsHandler?.hasBook ?? false;
    if (!listenArmed || action == ReaderTapAction.none) {
      runTap(action);
      return;
    }
    final pending = pendingTapPos;
    if (tapTimer != null &&
        pending != null &&
        (upPosition - pending).distance < 24) {
      tapTimer!.cancel();
      tapTimer = null;
      pendingTapPos = null;
      pendingTapAction = null;
      speakSentenceAt(upPosition);
      return;
    }
    tapTimer?.cancel();
    pendingTapPos = upPosition;
    pendingTapAction = action;
    tapTimer = Timer(const Duration(milliseconds: 200), () {
      tapTimer = null;
      final deferred = pendingTapAction;
      pendingTapAction = null;
      pendingTapPos = null;
      if (deferred != null) runTap(deferred);
    });
  }

  void runTap(ReaderTapAction action) {
    switch (action) {
      case ReaderTapAction.none:
        break;
      case ReaderTapAction.toggleBookmark:
        performBookmarkPullToggle();
      case ReaderTapAction.toggleControls:
        refresh(() => showControls = !showControls);
      case ReaderTapAction.previousPage:
        changePage(context, -1);
      case ReaderTapAction.nextPage:
        changePage(context, 1);
    }
  }

  /// Double-tap listen: find the paragraph under the tap, ask its text layer
  /// for the character offset, and speak the containing sentence.
  void speakSentenceAt(Offset global) {
    final handler = ttsHandler;
    if (handler == null || !handler.hasBook) return;
    for (final key in paragraphKeys.values) {
      final paragraphContext = key.currentContext;
      if (paragraphContext == null) continue;
      final root = paragraphContext.findRenderObject();
      if (root is! RenderBox || !root.attached) continue;
      RenderBox? textBox;
      void hunt(RenderObject node) {
        if (textBox != null) return;
        if (node is RenderBox &&
            (node is RenderParagraph || node is RenderEditable)) {
          textBox = node;
          return;
        }
        node.visitChildren(hunt);
      }

      hunt(root);
      final box = textBox;
      if (box == null) continue;
      final origin = box.localToGlobal(Offset.zero);
      final local = global - origin;
      if (local.dy < -4 || local.dy > box.size.height + 4) continue;
      // SelectableText renders through RenderEditable (global hit test);
      // plain Text.rich through RenderParagraph (local).
      final position = box is RenderParagraph
          ? box.getPositionForOffset(local)
          : (box as RenderEditable).getPositionForPoint(global);
      final plain = box is RenderParagraph
          ? box.text.toPlainText()
          : (box as RenderEditable).plainText;
      final span = sentenceAt(plain, position.offset);
      if (span == null) continue;
      final sentence = plain.substring(span.start, span.end).trim();
      if (sentence.isEmpty) continue;
      handler.speakSentence(sentence);
      return;
    }
  }

  EditableTextContextMenuBuilder contextMenuForParagraph(int paragraphIndex) =>
      createReaderSelectionToolbar(
        bookId: bookId,
        bookTitle: widget.book.title,
        currentParagraph: () => paragraphIndex,
        notesLibrary: notesLibrary,
        onHighlight: toggleHighlight,
        onNoteSaved: loadNotes,
      );

  void handleSurfacePageChanged(int index) {
    if (bookmarkPullInProgress || coverJumping || slideBusy) return;
    onPageTurned();
    refresh(() {
      currentPage = index;
      requestedPage = index;
    });
    maybeExtendPagination();
    scheduleSave();
  }
}
