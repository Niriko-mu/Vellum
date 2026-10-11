import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme/vellum_theme.dart';
import 'reader_chrome.dart';
import 'reader_controls.dart';
import 'reader_font_picker.dart';
import 'reader_models.dart';
import 'reader_page_overlay.dart';
import 'reader_page_surface.dart';
import 'reader_page_gesture_layer.dart';
import 'reader_selection.dart';
import 'tts_audio_handler.dart';
import 'tts_bar.dart';
import 'reader_page_state.dart';
import 'reader_page_state_pagination.dart';
import 'reader_page_state_gestures.dart';

Widget renderReaderPage(ReaderPageState state, BuildContext context) =>
    state.renderReaderPage(context);

extension ReaderPageSurfaceRendering on ReaderPageState {
  ReaderPageSurface readerSurface() => ReaderPageSurface(
    book: widget.book,
    readingMode: readingMode,
    scrollAnchor: scrollAnchor,
    scrollController: scrollController,
    pageController: pageController,
    pageCount: pageCount,
    pages: pages,
    currentPage: currentPage,
    showBookTitle: !pager.isAnchored,
    sideInset: ReaderPageState.readerSideInset,
    topInset: ReaderPageState.readerTopInset,
    bottomInset: ReaderPageState.readerBottomInset,
    fontSize: fontSize,
    fontFamily: readerFontFamily,
    lineSpacing: lineSpacing,
    fontWeight: readerFontWeight,
    ink: readerInk,
    tocParagraphs: tocParagraphs,
    paragraphKeys: paragraphKeys,
    highlights: highlights,
    spokenSentence: spokenSentence,
    searchHighlight: searchHighlight,
    noteCountFor: noteCountFor,
    contextMenuBuilder: contextMenuForParagraph,
    onOpenNotes: openNotesForParagraph,
    onJumpToParagraph: jumpToParagraph,
    onBookmarkPull: handleBookmarkPull,
    onRestorePage: restorePageWhenReady,
    onPageChanged: handleSurfacePageChanged,
  );

  Widget renderReaderPage(BuildContext context) {
    if (readingMode == ReadingMode.page) {
      ensurePages(context);
    } else {
      restoreScrollPositionWhenReady();
    }
    return CupertinoPageScaffold(
      backgroundColor: backgroundFor(context),
      navigationBar: null,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          // System/edge back: chrome first, then leave the reader.
          if (showControls) {
            refresh(() => showControls = false);
            return;
          }
          final navigator = Navigator.of(context);
          if (navigator.canPop()) navigator.pop();
        },
        child: SafeArea(
          child: Stack(
            children: [
              paperLayer(context),
              Localizations.override(
                context: context,
                delegates: const [DefaultMaterialLocalizations.delegate],
                child: SelectionArea(
                  onSelectionChanged: (content) {
                    lastSelectedText = content?.plainText.trim() ?? '';
                  },
                  contextMenuBuilder: (context, selectableRegionState) {
                    final selected = lastSelectedText.trim();
                    final buttonItems = <ContextMenuButtonItem>[
                      // Keep the platform copy action (SelectionArea handles it).
                      ...selectableRegionState.contextMenuButtonItems,
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'Bing 查询',
                          onPressed: () {
                            selectableRegionState.hideToolbar();
                            openSelectionService(selected, translate: false);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: 'DeepL 翻译',
                          onPressed: () {
                            selectableRegionState.hideToolbar();
                            openSelectionService(selected, translate: true);
                          },
                        ),
                      if (selected.isNotEmpty)
                        ContextMenuButtonItem(
                          label: '笔记',
                          onPressed: () async {
                            selectableRegionState.hideToolbar();
                            await showAddNoteSheet(
                              context,
                              bookId: bookId,
                              bookTitle: widget.book.title,
                              paragraphIndex: currentParagraph,
                              selectedText: selected,
                              notesLibrary: notesLibrary,
                            );
                            await loadNotes();
                          },
                        ),
                    ];
                    return CupertinoAdaptiveTextSelectionToolbar.buttonItems(
                      anchors: selectableRegionState.contextMenuAnchors,
                      buttonItems: buttonItems,
                    );
                  },
                  child: ReaderGestureLayer(
                    onPointerDown: (event) {
                      readerPointerDownAt = DateTime.now();
                      readerPointerDownPosition = event.position;
                      bookmarkPullInProgress = false;
                      bookmarkPullArmed = false;
                      bookmarkPullHandled = false;
                      pageBeforePointerDown = currentPage;
                      pointerLooksLikeSelection = false;
                      selectionHoldTimer?.cancel();
                      // 400 ms was short enough that a careful page-turn press
                      // often armed selection first; hold longer before the
                      // gesture is treated as a select.
                      selectionHoldTimer = Timer(
                        const Duration(milliseconds: 750),
                        () {
                          pointerLooksLikeSelection = true;
                        },
                      );
                    },
                    onPointerMove: handleReaderPointerMove,
                    onPointerCancel: (_) {
                      selectionHoldTimer?.cancel();
                      readerPointerDownAt = null;
                      readerPointerDownPosition = null;
                      pointerLooksLikeSelection = false;
                      bookmarkPullArmed = false;
                      bookmarkPullHandled = false;
                      if (bookmarkPullInProgress) {
                        restorePageAfterBookmarkPull();
                        bookmarkPullInProgress = false;
                      }
                      if (dragTurn) {
                        endDragTurn();
                      }
                      if (pullDownDistance != 0) {
                        refresh(() => pullDownDistance = 0);
                      }
                    },
                    onPointerUp: (event) {
                      selectionHoldTimer?.cancel();
                      handleReaderPointerUp(context, event);
                    },
                    child: readerSurface(),
                  ),
                ),
              ),
              if (pullDownDistance > 8) bookmarkPullIndicator(context),
              if (coverFromPage != null && coverToPage != null)
                ReaderCoverTurnOverlay(
                  fromPage: coverFromPage!,
                  toPage: coverToPage!,
                  animation: coverAnim,
                  dragTurn: dragTurn,
                  dragCommitted: dragCommitted,
                  pageSurface: coverPageSurface,
                ),
              if (eyeCare != ReaderEyeCare.off)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: const Color(
                        0xffd9a441,
                      ).withValues(alpha: eyeCare.opacity),
                    ),
                  ),
                ),
              // Fanqie BottomIndicator: page + battery only when chrome is hidden.
              if (!showControls)
                ReaderStatusBar(
                  pageLabel: pageProgress,
                  batteryLabel: batteryText,
                  batteryLevel: batteryLevel < 0 ? null : batteryLevel,
                  surface: backgroundFor(context),
                ),
              if (!showControls)
                ReaderRunningHead(
                  chapterLabel: chapterLabel,
                  surface: backgroundFor(context),
                ),
              if (!showControls)
                ReaderReadingTimePill(
                  sessionSeconds: sessionSeconds,
                  todaySeconds: todaySeconds,
                  surface: backgroundFor(context),
                ),
              if (listening && !showControls)
                TtsBar(
                  playing: ttsHandler?.isPlaying ?? false,
                  positionLabel: ttsLabel,
                  speed: ttsSpeed,
                  subtitle: spokenSentence,
                  onPlayPause: () {
                    final handler = ttsHandler;
                    if (handler == null) return;
                    handler.isPlaying ? handler.pause() : handler.play();
                  },
                  onPrevious: () => ttsHandler?.skipToPrevious(),
                  onNext: () => ttsHandler?.skipToNext(),
                  onCycleSpeed: cycleTtsSpeed,
                  onClose: stopListening,
                ),
              if (isCurrentViewBookmarked)
                Semantics(
                  label: '当前阅读页面已添加书签',
                  child: BookmarkRibbon(
                    surface: backgroundFor(context),
                    progress: 1,
                    armed: false,
                    alreadyBookmarked: true,
                    label: '',
                    pinned: true,
                    showLabel: false,
                  ),
                ),
              if (bookmarkNotice != null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .92, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  child: SafeArea(
                    key: ValueKey(bookmarkNotice),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 42),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: VellumTheme.cardOf(context),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 9,
                            ),
                            child: Text(
                              bookmarkNotice!,
                              style: TextStyle(
                                color: VellumTheme.inkOf(context),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // Fanqie ReaderMenu: Stack overlay (not Dialog), top bar -44dp /
              // bottom bar height, both 300ms. Font picker stays wired via
              // onShowFonts → existing FontPickerSheet.
              ReaderMenu(
                visible: showControls,
                bookTitle: widget.book.title,
                bookmarked: isCurrentViewBookmarked,
                // Fanqie TopBar exit: leave the reader route. Progress is
                // flushed in dispose()/didChangeAppLifecycle.
                onBack: () {
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  } else {
                    refresh(() => showControls = false);
                  }
                },
                // Tap outside only collapses chrome — not an exit.
                onDismiss: () => refresh(() => showControls = false),
                // Listening runs through the app-wide handler; null on platforms
                // without speech support hides the action.
                onListen: ttsHandler == null ? null : startListening,
                listening: listening,
                onToggleBookmark: toggleBookmarkAtCurrentPosition,
                progress: progress,
                chapterCount: chapters.length,
                currentChapterIndex: chapterIndexFor(activeParagraph) < 0
                    ? 0
                    : chapterIndexFor(activeParagraph),
                chapterTitle: chapterLabel,
                canSeek: canSeekProgress,
                onSeekProgress: jumpToProgress,
                onSeekChapter: jumpToChapter,
                progressSummary: progressSummary,
                onContinueReading: () {
                  refresh(() => showControls = false);
                  jumpToParagraph(
                    resumeParagraphIndex,
                    preloadPreviousPage: true,
                  );
                },
                onJumpToChapter: (paragraph, {required restorePosition}) {
                  refresh(() => showControls = false);
                  jumpToParagraph(
                    paragraph,
                    restoreChapter: restorePosition,
                    preloadPreviousPage: true,
                  );
                },
                fontSize: fontSize,
                readerFontWeight: readerFontWeight,
                lineSpacing: lineSpacing,
                background: paper,
                readingMode: readingMode,
                pageTurnStyle: pageTurnStyle,
                brightness: brightness,
                eyeCare: eyeCare,
                keepScreenOn: keepScreenOn,
                volumeKeys: volumeKeys,
                chapters: chapterEntries(),
                paragraphs: widget.book.paragraphs,
                pageLabelForParagraph: pageLabelForParagraph,
                onJumpToSearchHit: jumpToSearchHit,
                chapterPageLabels: chapterPageLabels(),
                bookmarks: [
                  for (final bookmark in bookmarks)
                    MapEntry(
                      bookmark,
                      bookmarkSummary(widget.book.paragraphs, bookmark),
                    ),
                ],
                notes: notes,
                currentParagraph: activeParagraph,
                onJumpToParagraph: (paragraph) {
                  refresh(() => showControls = false);
                  jumpToParagraph(paragraph);
                },
                onRemoveBookmark: removeBookmark,
                onRemoveNote: removeNote,
                onFontSize: (value) {
                  refresh(() {
                    fontSize = value;
                  });
                  scheduleSave();
                },
                onReaderFontWeight: (value) {
                  refresh(() => readerFontWeight = value);
                  saveTimer?.cancel();
                  saveState();
                },
                onLineSpacing: (value) {
                  refresh(() => lineSpacing = value);
                  saveTimer?.cancel();
                  saveState();
                },
                onBackground: applyPaper,
                onReadingMode: (value) {
                  setReadingMode(value);
                },
                onPageTurnStyle: (value) {
                  refresh(() => pageTurnStyle = value);
                  saveTimer?.cancel();
                  saveState();
                },
                onBrightness: (value) {
                  refresh(() => brightness = value);
                  platform.setBrightness(value);
                  scheduleSave();
                },
                onEyeCare: (value) {
                  refresh(() => eyeCare = value);
                  saveTimer?.cancel();
                  saveState();
                },
                onKeepScreenOn: (value) {
                  refresh(() => keepScreenOn = value);
                  platform.setKeepScreenOn(value);
                  saveTimer?.cancel();
                  saveState();
                },
                onVolumeKeys: (value) {
                  refresh(() => volumeKeys = value);
                  syncVolumeKeys();
                  saveTimer?.cancel();
                  saveState();
                },
                onShowFonts: showFontPicker,
                onToggleUiTheme: widget.onToggleUiTheme,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showFontPicker() {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => ReaderFontPickerSheet(
        surface: backgroundFor(context),
        installedFonts: widget.installedFonts,
        activeFamily: readerFontFamily,
        onSelectSystemFont: (family) {
          Navigator.pop(ctx);
          refresh(() {
            readerFontFamily = family;
            pagination.invalidateLayout();
          });
          saveState();
        },
        onSelectImportedFont: (font) async {
          if (widget.onActivateFont == null) return;
          await widget.onActivateFont!(font.name);
          if (!mounted || !ctx.mounted) return;
          Navigator.pop(ctx);
          refresh(() {
            readerFontFamily = font.family;
            pagination.invalidateLayout();
          });
          saveState();
        },
      ),
    );
  }

  void changePage(BuildContext context, int delta) {
    if (!pageController.hasClients) return;
    var totalPages = pageCount;
    if (totalPages <= 0) return;
    final live = pageController.hasClients
        ? pageController.page?.round()
        : null;
    var base = (live ?? requestedPage).clamp(0, totalPages - 1).toInt();
    if (coverFromPage != null) base = coverToPage ?? base;
    if (slideBusy) base = requestedPage.clamp(0, totalPages - 1).toInt();

    // An anchored deep jump deliberately starts at local page zero.  If the
    // reader asks for the previous page there, materialise a bounded prefix
    // before calculating the target; otherwise the old clamp below would turn
    // the request into a no-op and make the chapter home feel locked.
    if (delta < 0 && base == 0 && !coverAnim.isAnimating && !slideBusy) {
      final prepared = preparePreviousPage();
      if (prepared != null) {
        base = prepared;
        totalPages = pageCount;
      }
    }
    final target = (base + delta).clamp(0, totalPages - 1).toInt();
    if (target == base && !coverAnim.isAnimating && !slideBusy) {
      // A fast reader can consume the last currently materialised page before
      // the asynchronous slice has rebuilt the PageView. A forward tap at
      // that boundary is a useful retry signal, so kick the same extension
      // path instead of silently dropping the gesture.
      if (delta > 0) maybeExtendPagination();
      return;
    }
    onPageTurned();

    if (pageTurnStyle == PageTurnStyle.none) {
      refresh(() {
        requestedPage = target;
        currentPage = target;
      });
      jumpToPageExact(target);
      maybeExtendPagination();
      scheduleSave();
      return;
    }

    if (pageTurnStyle == PageTurnStyle.slide) {
      startSlideTurn(target);
      return;
    }

    // Cover (and default): queue rapid taps instead of dropping them.
    if (coverAnim.isAnimating) {
      pendingPageDelta += delta;
      return;
    }
    startCoverTurn(base, target);
  }

  void startSlideTurn(int target) {
    if (!pageController.hasClients) return;
    if (slideBusy) {
      requestedPage = target;
      pageController.jumpToPage(requestedPage);
    }
    slideBusy = true;
    refresh(() => requestedPage = target);
    pageController
        .animateToPage(
          target,
          // 180ms easeOutCubic: snappy tap-to-turn. Fanqie's slide mode uses a
          // short custom-Scroller fling; long durations feel laggy on tap.
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() {
          if (!mounted) return;
          refresh(() {
            currentPage = target;
            requestedPage = target;
          });
          slideBusy = false;
          // Slide turns suppress PageView.onPageChanged while animating.
          // Extend an anchored window from the committed page so the reader
          // can continue past the current PageView itemCount.
          maybeExtendPagination();
          scheduleSave();
        });
  }

  void startCoverTurn(int from, int to) {
    coverFromPage = from;
    coverToPage = to;
    // Measure the destination page before the animation starts so the
    // overlay never shows a half-paginated page that reflows mid-turn.
    if (!pager.fullyPaginated && to >= pager.pageCount) {
      pager.paginateUntilPages(to + 1);
    }
    // Keep PageView on [from] during the overlay so the underlying page does
    // not re-layout mid-animation (avoids visible “reflow” under the cover).
    dragCommitted = false;
    refresh(() {
      requestedPage = to;
    });
    coverAnim
      ..reset()
      ..forward().whenComplete(() {
        if (!mounted) return;
        finishCoverTurn(to);
      });
  }

  void finishCoverTurn(int to) {
    coverJumping = true;
    jumpToPageExact(to);
    refresh(() {
      currentPage = to;
      requestedPage = to;
    });
    // Cover turns keep PageView on the previous page until the overlay settles,
    // so its onPageChanged callback is intentionally ignored. Start the next
    // pagination slice from the committed page instead.
    maybeExtendPagination();
    // Drop the overlay one frame after the jump so the user never sees
    // PageView rebuild/layout under the cover.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      refresh(() {
        coverFromPage = null;
        coverToPage = null;
      });
      coverJumping = false;
      scheduleSave();
      final pending = pendingPageDelta;
      pendingPageDelta = 0;
      if (pending != 0) {
        // Re-enter the normal path so a queued backwards turn can request a
        // bounded predecessor page at an anchored window boundary.
        changePage(context, pending);
      }
    });
  }

  Widget coverPageSurface(BuildContext context, int page) {
    if (page < 0 || page >= pageCount) return const SizedBox.expand();
    // Same paper stack as the live page (underlay + image). Painting only a
    // solid colour here made the background pop every cover-style turn.
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: paperSurface(context)),
        Padding(
          padding: EdgeInsets.fromLTRB(
            ReaderPageState.readerSideInset,
            ReaderPageState.readerTopInset,
            ReaderPageState.readerSideInset,
            ReaderPageState.readerBottomInset,
          ),
          // selectable:true matches the PageView builder exactly. Rendering the
          // overlay with selectable:false used SelectableText vs Text and let
          // the two widgets lay out differently — the page visibly "settled"
          // (paragraph spacing shifted) the moment the animation ended.
          // The overlay is already wrapped in IgnorePointer.
          child: readerSurface().buildPage(context, page),
        ),
      ],
    );
  }
}
