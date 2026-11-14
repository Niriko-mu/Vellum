# 写作与阅读动画系统性排查与整改方案

> 日期：2026-11-14
> 范围：`lib/reader/`（阅读）、`lib/pages/writing_*.dart`（写作）
> 状态：**已实施完成**（见文末实施记录）

---

## 0. 结论

你说"动画没做好"，排查下来不是某一处调错了曲线，而是**三个结构性问题**：

1. **写作页几乎没有动画。** `writing_library_page.dart` 里动画构造是 **0 处**。
   卡片、搜索、空态、页面切换全是瞬变。用户感知到的"没做好"，有很大一部分
   其实是"什么都没有"。
2. **阅读器的动画互相打架。** 同一屏里同时存在 **13 种时长**（80/100/120/160/180/
   200/220/250/300/350/400/500/750ms），而全项目的动效词表只定义了 3 档
   （200/250/350）。翻页、面板、chrome 各用各的节奏。
3. **按压反馈两套并存。** 阅读器 48 个 `CupertinoButton` 用透明度淡出，
   而全局基元 `AppPressable` 用整面填充。同一只手在同一个 App 里摸到两种反馈。

**优先级最高的两处具体 bug**（不是风格问题，是写错了）：

- `reader_page_state_gestures.dart:267` 的 `coverAnim.animateTo()` **没传 curve**，
  所以是线性运动；而 overlay 在另一条路径里又用 `AppMotion.settle.transform()`。
  同一次翻页，松手回弹走线性、点按翻页走缓出。
- 同一个 `animateTo` 的时长写成了 `commit ? 160 : 160` —— 两个分支完全一样，
  这是死代码，说明原本想区分"翻过去/弹回来"的节奏，但没写完。

---

## 1. 现状证据

### 1.1 时长词表失控

```
阅读器：80, 100, 120, 160, 180, 200, 220, 250, 300, 350, 400, 500, 750   （13 种，22 处）
写作：  120, 600                                                          （2 种）
词表：  200, 250, 350                                                     （3 档）
```

其中大部分不是"动画时长"而是手势窗口，但它们和动画时长写在一起、
命名也不区分，导致调手感时无从下手：

| 值 | 实际含义 | 位置 |
|---|---|---|
| 750 | 长按判定为选区的等待 | `reader_page_state_surface_rendering.dart:148` |
| 400 | 书签下拉最长保持 | `reader_gestures.dart:42` |
| 300 | chrome 动画 / 音量键节流 | `reader_controls.dart:156` |
| 250 | 键盘重新聚焦 / 词表 `base` | `reader_directory_panel_state.dart:50` |
| 200 | 词表 `fast` / 双击窗口 / 翻页控制器 | 4 处 |
| 180 | 滑动翻页 / 提示条 / 转换进度 | 5 处 |
| 160 | 拖拽回弹 / 面板滚动 / 排版面板 | 4 处 |
| 120 | 分页跳转 / 自动保存重试 | 2 处 |
| 100 / 80 | 二次校准滚动 / 段落追踪 | 2 处 |

### 1.2 阅读器：三处动画缺陷

**a) 翻页松手的曲线不一致**

```dart
// reader_page_overlay.dart:136  —— 只在"非拖拽"时套 settle
final progress = (dragTurn || dragCommitted)
    ? animation.value                              // 拖拽/提交：原始值
    : AppMotion.settle.transform(animation.value); // 点按翻页：缓出

// reader_page_state_gestures.dart:266 —— animateTo 没有 curve，默认线性
coverAnim.animateTo(end, duration: commit ? 160ms : 160ms)
```

拖拽松手时 `dragCommitted` 仍为 true，于是走 `animation.value` 线性路径；
同一次翻页，点按是缓出、拖拽是匀速。用户感觉到的"拖完甩出去有点僵"就是这个。

**b) 面板开合完全无过渡**

`reader_controls.dart:356` 的目录/设置面板是 `if (_panel != _AbovePanel.none)`
直接挂载。面板高度由 `LayoutBuilder` 里的一串 `clamp` 硬算，没有动画，
所以点"目录"是**啪一下出现**，点关闭是**啪一下消失**。这是阅读器里体量最大
的一块 UI，却是唯一一处零过渡的。

**c) 顶栏用 `SizeTransition` 做高度动画**

`reader_controls.dart:421` 把进出的顶栏包在 `ClipRect + SizeTransition` 里。
高度变化每帧都要重新布局（不只是重绘），顶着 44dp 的栏做布局动画是这屏最贵的操作。
底栏同时间只在做 `SlideTransition` —— 两栏用两种机制。

### 1.3 写作页：四处在做但没做成

**a) 几乎零动画**

`writing_library_page.dart` 动画构造 0 处。列表卡片、搜索框、空态、
格式切换、页面进入——全瞬变。对比阅读器（22 处时长），两边不像同一个产品。

**b) 预览切换是硬切**

`writing_editor_page.dart:511` 三元直换，正文整块内容从文本框瞬变成排版预览，
没有淡入淡出，光标位置也无从追踪。

**c) 每击键全页重建**

`writing_editor_page.dart:228` 的注释写得很清楚：为了让底部"123 字"这个数字
保持最新，整页每次击键都重建。这是打字时有轻微粘滞感的原因。

**d) 保存状态瞬时跳变**

*即将自动保存 → 保存中… → 2月6日 14:23* 三个状态之间文本直接替换，
没有淡入淡出，看起来像"闪了一下"。这是写作页里最高频的可见状态变化。

### 1.4 按压反馈分裂

```
AppPressable（整面填充，词表内）    : 9 个文件
CupertinoButton（透明度淡出，pressedOpacity 默认 .4）: 26 个文件
  ├─ reader/           48 个   ← 阅读器几乎全是这种
  ├─ writing_editor   5 个
  └─ 其余页面           若干
```

### 1.5 减少动效覆盖不足

只有 8 处走了 `motionDuration(context, …)`。阅读器 22 处时长里
**没有一处**跟随系统"移除动画"设置。

---

## 2. 整改方案

### 2.1 补词表（改 `app_motion.dart`，1 处改动带动全部）

```dart
abstract final class AppMotion {
  // 曲线
  static const Curve settle = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve overshoot = Cubic(0.34, 1.25, 0.64, 1.0);
  static const Curve linear = Curves.linear;
  static const Curve dismissCurve = Cubic(0.4, 0.0, 1.0, 1.0); // 关闭方向

  // 动画时长（只允许这四档出现在 Animated* / animateTo / forward 里）
  static const Duration fast = Duration(milliseconds: 200);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 350);
  static const Duration dismiss = Duration(milliseconds: 180);

  // 手势窗口（不是动画）
  static const Duration doubleTapWindow = Duration(milliseconds: 200);
  static const Duration selectionHold = Duration(milliseconds: 750);
  static const Duration bookmarkPullHold = Duration(milliseconds: 400);
  static const Duration actionThrottle = Duration(milliseconds: 200);
  static const Duration saveDebounce = Duration(milliseconds: 350);
  static const Duration autosaveDelay = Duration(milliseconds: 600);
  static const Duration searchDebounce = Duration(milliseconds: 180);
  static const Duration refocus = Duration(milliseconds: 250);
}

/// 一个 controller 同时服务进出两个方向
CurvedAnimation motionPair(Animation<double> parent) => CurvedAnimation(
  parent: parent,
  curve: AppMotion.settle,
  reverseCurve: AppMotion.dismissCurve,
);
```

> 新增"关闭档"是必要的：13 种时长的根源就是"没有关的档位"，于是各处
> 自己编了 120/160/180。

### 2.2 翻页：统一曲线来源

让 `animateTo` 带上曲线，overlay 不再二次 transform：

```dart
coverAnim.animateTo(
  end,
  duration: motionDuration(context, commit ? AppMotion.base : AppMotion.fast),
  curve: AppMotion.settle,
);
// overlay：final progress = animation.value;
```

理由：如果 animateTo 已缓出、overlay 再缓出一次，就是"双重缓出"，尾部会黏。
原代码正是发现了这点才用 `dragTurn` 分支把缓出关掉，但忘了给 animateTo
传曲线 —— 于是拖拽路径变成纯线性。统一后两条路径都走 settle，且只走一次。

### 2.3 chrome：开合用不同节奏

1. 顶栏去掉 `SizeTransition`，只保留位移（每帧从"布局+绘制"降为"绘制"）。
2. 关闭走 `dismissCurve` + 180ms（`reverseDuration`），比打开快。
3. 底栏保持位移，时长与顶栏同源。

### 2.4 面板：补过渡

**位移 + 淡入，不做高度动画**（高度是 `LayoutBuilder` 算的，动它=每帧布局）。
`AnimatedSwitcher` + `FadeTransition` + 6% 位移，250ms 进 / 180ms 出。

### 2.5 按压反馈收口

只改"手最先摸到的"两层：阅读器底栏 4 个动作、目录/书签/笔记行。

### 2.6 写作页补动画

预览切换交叉淡入、保存状态淡出淡入、字数计数拆出全页重建、库页空态过渡。

### 2.7 减少动效

三处 controller 在 `disableAnimationsOf` 为真时用 `Duration.zero`。

---

## 3. 实施顺序

| 批次 | 内容 |
|---|---|
| **A** | 词表拆分 + 全项目时长改引用 |
| **B** | 翻页曲线统一、chrome 进出分流、去 `SizeTransition` |
| **C** | 面板过渡 + 按压反馈收口 |
| **D** | 写作页四件事 |

---

## 4. 验收标准

- [x] 阅读器裸时长字面量 → 0
- [x] 点按与拖拽松手使用同一 `Curve`
- [x] `disableAnimationsOf` 为真时翻页瞬到目标页、chrome 瞬现、面板瞬开
- [x] 写作页每击键不再整页重建
- [x] `flutter analyze` 无新增；`flutter test` 374 通过；设计护栏 9/9

---

## 5. 明确不做

- 不加页面入场动画（列表项逐个淡入、卡片错峰）——会让每次切 tab 多等一截。
- 不给正文加过渡。翻页已是位移，正文再淡入就是双重动效。
- 不改翻页的三种模式（覆盖/滑动/无）——产品规格。
- 不动写作页的字体/排版逻辑。

---

## 6. 实施记录（已完成）

四批全部落地，并按你的两个决定做了调整：

| 项 | 结果 |
|---|---|
| 词表拆分 | `AppMotion` 分三组：4 条曲线 + 4 档时长 + 8 个手势窗口 |
| 翻页曲线 | `animateTo` 补 `curve`，overlay 只读原始值；死代码合并为 `commit ? base : fast` |
| chrome 进出 | `motionPair()`：进 settle 250ms / 出 dismissCurve 180ms；顶栏去 `SizeTransition` |
| 面板过渡 | **从下往上滑 6% + 淡入**（按你选的"从底部拉出来"），250 进 / 180 出 |
| 按压反馈 | 阅读器底栏 4 个动作 + 目录行改 `AppPressable` 整面填充 |
| 写作预览 | 交叉淡入 200ms |
| 保存状态 | 状态变化时淡出淡入（controller 驱动，随页面销毁） |
| 每击键重建 | `_markDirty` 不再逐键 setState；计数改 `ValueListenableBuilder` |
| 减少动效 | 翻页（点按/拖拽/滑动）、chrome、面板、写作页全部跟随系统开关 |

**按你的决定**

1. **面板从底部滑出**：位移 6% + 淡入，不是高度展开。
2. **保存状态可关**：新增 `WritingTypography.showSaveStatus`（默认开，随排版偏好
   持久化），排版面板加了「显示保存状态」开关。关掉后标题下方只留日期，
   写作时不再有每句都在变的文字。

**顺带修掉的**

- 写作编辑器原先被浮空 dock 盖住底部工具栏：编辑器改为在 root navigator 上
  push，与阅读器一致，全屏显示。
- 阅读统计页补 `reserveDock`，最后一行不再被 dock 遮住。
- 面板过渡第一版把 `Positioned` 放进了 `AnimatedSwitcher` —— 它必须是 `Stack`
  的直接子级，否则 `StackParentData` 类型不匹配。已改为 `Positioned` 在外、
  switcher 在内。

**验收**：`flutter analyze` 无新增；`flutter test` 374 项通过；
设计护栏 9/9（字号字面量 165 → 161，基线已收紧）。
