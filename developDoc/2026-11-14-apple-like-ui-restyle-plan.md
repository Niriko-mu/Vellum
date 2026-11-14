# VELLUM 视觉体系改造方案（Apple-like 重构）

> 日期：2026-11-14
> 范围：`lib/` 全部界面层（主题、页面、阅读器 chrome、浮层）
> 参考：`D:\Projects\InnovativeSpace\mobile-UI-design-rules\apple-like-skill`
> 状态：**已被取代（2026-11-14）** —— 本文是第一阶段的全量方案稿。
> 实际执行按其收敛版 `2026-11-14-cherry-f1-implementation-plan.md`（F1 保真度）推进，
> 偏离项见 `design-fidelity-overrides.md`，落地记录见
> `2026-11-14-f1-implementation-record.md`。
> 保留本文的原因只有一个：第 0 节的量化基线（61 个颜色字面量、69 处圆角、214 处 fontSize…）
> 是"改造前长什么样"的唯一记录，后续对比要用。

---

## 0. 结论摘要

VELLUM 现在**不是"风格不对"，而是"没有风格层"**。

- 只有一个 `CupertinoThemeData`，但真正的视觉决策分散在 **4 套并行的表面常量**里：
  `VellumTheme.shell*`（应用壳）、`VellumTheme.paper/card/ink`（旧纸张，仍被引用）、
  Fanqie `reader*`（阅读器）、`WritingStyle.*`（写作页）。
- 量化：**61** 个颜色字面量、**45** 处 `CupertinoColors.*`、**69** 处 `BorderRadius.circular()` 落在 **17 个不同圆角**、
  **214** 处 `fontSize:` 落在 **17 个不同字号**、**12** 处 `FontWeight.w700`、**10** 个 `BoxShadow`、**14** 处 `Curves.ease*`。
- 三个"卡片白"同时存在：`#FFFDF8` / `#FFFEFA` / `#FFFFFF`；三个"页面底"：`#F7F3ED` / `#F4F3F0` / shell 默认。
- 平均每 5 行 Dart 就有一个视觉决定写在 widget 里，所以"改一次风格" = 改 40 个文件。

**改造方向不是把 VELLUM 变成 iOS 仿制品**，而是把它现在只有一半的 Apple-like 结构补齐：

| 维度 | 现状 | 目标 |
|---|---|---|
| 颜色 | 13 个静态常量 + 每页自带 | 1 个 `AppColors` ThemeExtension，widget 里零字面量 |
| 圆角 | 17 档（2…999） | 8 基数 9 档 + 纸张隐喻例外 |
| 字号 | 17 档（10…34），w300–w700 | 13 级阶梯 + 3 权重（400/500/600） |
| 表面 | 卡片套卡片，几乎每个容器都有 border | 默认一个连续表面；表面/边框必须"挣得位置" |
| 阴影 | 10 处，用途不明 | 3 个 token：浮层 / 单个填充主按钮 / 填充搜索框 |
| 动效 | `easeOutCubic`/`easeInOut` 混用 | `settle` / `overshoot` / `linear`，200/250/350 |
| 无障碍 | 设置页把文字缩放**锁死在 1.2** | 2.0 下不裁剪、不塌行 |

**工作量**：约 6 个批次、22 个工作项；主题层 1 天、基元 1 天、逐页 3–4 天、阅读器 chrome 1 天。
**风险最高点**：不是样式，是 `lib/pages/settings_page.dart:462` 的
`MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2)` —— 它把整个设置页的文字缩放掐死了，
是当前唯一的"硬伤"，必须在迁移第一批就拆掉。

---

## 1. 现状审计（带证据）

### 1.1 主题层：一个主题，四套真相

`lib/theme/vellum_theme.dart` 有 228 行，其中 **8–65 行是 13 个静态颜色常量**，**143–228 行是 9 个静态 getter**：

```dart
static Color inkOf(BuildContext c)        → shellDarkInk / shellInk
static Color mutedOf(BuildContext c)      → shellDarkMuted / shellMuted
static Color cardOf(BuildContext c)       → shellDarkCard / shellCard
static Color lineOf(BuildContext c)       → shellDarkLine / shellLine
static Color shellOf(BuildContext c)      → shellDarkPaper / shellPaper
static Color accentOf(BuildContext c)     → darkAccent / accent
static Color softAccentOf(BuildContext c) → accent @ 12%
```

这套 API 本身不算错（它已经是 skill 所说"一个 AppTheme 静态读取 extension"的雏形），问题在**它之外还有三套**：

| 表面来源 | 位置 | 页面底 | 卡片底 |
|---|---|---|---|
| 应用壳 | `VellumTheme.shell*` | `#F7F3ED` | `#FFFDF8` |
| 旧纸张（仍在 import 中使用） | `VellumTheme.paper/card/ink` | `#F7E4CF` | `#FFF8EF` |
| 阅读器 | `readerWhite/Sepia/...` | 7 种纸张 | — |
| 写作页 | `WritingStyle.*`（`writing_style.dart` 仅 16 行、3 个字面量） | `#F4F3F0` | `#FFFEFA` |

`lib/pages/writing_style.dart` 整个文件就是三个 `Color(0xff......)` —— 这正是 skill 点名拒绝的
"the same role holding different values in different files"。

### 1.2 颜色字面量与 `CupertinoColors`

```
Color(0xAARRGGBB)          61 处 / 11 个文件   （37 处在 theme 里，24 处散落在 widget）
CupertinoColors.xxx        45 处 / 21 个文件
Colors.*                    0 处   ← 项目没有引 Material 颜色，这点是干净的
withOpacity(...)            0 处   ← 已统一 withValues，这点也是干净的
```

散落的 24 处里，`reader_selection.dart` 占 10 处、`book_widgets.dart` 占 12 处 `CupertinoColors`。
按 skill 的四类豁免，**只有约 6 处能留下**（封面叠字、图片上遮罩、按纸张亮度取墨、构建脚本），其余全要走 token。

### 1.3 圆角：17 档

```
2(2) 3(2) 4(3) 6(2) 8(3) 9(4) 10(15) 12(4) 14(5) 15(1) 16(8) 18(8) 20(2) 22(3) 24(1) 28(1) 999(1)
```

同一屏出现 4–6 个圆角是常态：

- `reading_stats_page.dart` 一页里 22 / 18 / 16 / 6 / 4 五种；
- `book_widgets.dart` 一页里 10（外框）/ 9（内剪裁）/ 14（按钮）/ 4（缩略图）四种；
- 底层弹层分裂：6 个 sheet 用 `Radius.circular(16)`、`reader_font_picker.dart` 用 12、
  `update_sheet.dart` 用 20。

### 1.4 字体：17 档 + 6 种权重写法

```
10(4) 11(24) 12(58) 13(47) 14(22) 15(12) 16(14) 17(10) 18(6) 19(4) 20(2) 22(2) 23(1) 24(1) 28(3) 30(1) 34(3)

w600(53) w400(6) w700(12) w500(3) w300(2) regular(3)
```

- `12` 与 `13` 并用了 105 次，肉眼几乎不可分辨，却让"元信息"出现两种口径。
- `w700` 12 处全部是"标题"：`writing_library_page.dart:198`（34/w700/letterSpacing −1）、
  `reading_stats_page.dart:155`（30/w700）、`book_widgets.dart` 的 `DefaultCover`。
  skill 的结论是"w700 是给层级问题打的补丁"——层级该用字号和间距解决。
- `letterSpacing: -1` / `letterSpacing: 2.2`（`home_page.dart` 的 `VELLUM` 字标）是两个特例；
  只有品牌字标保留 letterSpacing 是合理的，正文字距一律 0。

### 1.5 表面与边框

- `reading_stats_page.dart` 几乎每个区块都是一个独立卡片：`今日` 块、`最近 7 天` 块、以及
  **每本书一行一个** `Container(color: cardOf, border: lineOf, radius: 16~22)`（3 本书就是 5 个）。
  这就是 skill 说的 "never wrap every section in a card" —— 统计页本该是一条连续表面上的若干分组。
- `home_page.dart` 的"最近加入"块：一个圆角卡里放 `Divider(indent: 74)` —— 已经摸到了
  "分组内发丝线"的正确写法，但外层又多了一圈 16 圆角 border，等于把分组又包了一层。
- 几乎每个可点区域都是 `CupertinoButton`，`pressedOpacity` 默认 .4 —— **按压淡出**取代了
  skill 要求的 pressed fill。行类交互应该是整行 `foreground@5%` 填充，而不是让内容变透明。

### 1.6 阴影：10 处，用途混杂

| 位置 | 现在 | 判定 |
|---|---|---|
| `book_widgets.dart` 删除按钮 | blur 10 / y2 | 删（`constantBlack@42` 圆盘已经够） |
| `book_widgets.dart` 封面卡 | blur 12 / y6 | 删（书封本身就是内容） |
| `home_page.dart` 继续阅读卡 | blur 18 / y8 | 删（层级用字号/间距） |
| `writing_library_page.dart` FAB | accent blur 20 | 收进 `shadowXs` |
| `reader_controls.dart` / `reader_color_picker.dart` / `reader_page_overlay.dart` / `tts_bar.dart` | 浮层 | 收进 `shadowOverlay` |
| `reader_paragraph.dart` / `reader_page_state_surface_rendering.dart` | 纸页立体感 | 删或降为发丝线 |

10 → 3。

### 1.7 动效

`Curves.easeOutCubic`（8 处）、`Curves.easeOut`（3 处）、`Curves.easeInOut`（2 处）、
`Curves.easeOutQuad`（1 处）混用；时长 120 / 160 / 200 / 220 / 250 / 300 / 350 共七种。
`reader_chrome.dart` 的书签条用 120ms，比 skill 的 `fast`(200) 还短 —— 靠"快"制造灵敏感的典型反模式。

### 1.8 无障碍硬伤（必须优先）

1. `settings_page.dart:462`：`MediaQuery.withClampedTextScaling(min:1, max:1.2)` 包住整个设置页。
   系统字号放大到 2.0 时这一页**仍是 1.2**。skill 明确要求 2.0 不裁剪 —— 这里是直接不允许放大。
2. `reader_chrome.dart` 页眉 `ink.withValues(alpha: .38)`：实测 `#999999` on `#F6F6F6` = **2.64:1**，
   低于正文 4.5:1，也低于图形 3:1。
3. `reader_chrome.dart` 状态条 `alpha: .55` = 4.65:1（勉强及格）；`reader_panel_common.dart` 的
   12px 标签 + `.55` 同样贴着及格线。
4. `book_widgets.dart` 的 chevron `muted.withValues(alpha: .7)` = **2.81:1**，图形对比度不及格。
5. 19 处 `showCupertinoDialog` 里，至少 6 处承载的是"一次操作的结果"（"已导出…"、"导入失败"、
   "字体导入结果"）—— 按 skill 的反馈归属表，这些应该是 toast / inline，alert 只留给
   "必须读的文字或必须做的决定"。

### 1.9 逐页 finding

| 页面 | 主要问题 | 处置 |
|---|---|---|
| 首页 `home_page.dart` | 28px/w600 大标题 + 16 圆角卡 + 阴影 + 卡内 Divider | 大标题 32；去阴影；分组=一个连续块 |
| 书库 `library_page.dart` | 搜索 18 边距、chip 12px/16 圆角自成一档、网格 14 边距、空搜索态是裸 `Text` | 统一 16 gutter + pill chip + `AppContentState` |
| 写作 `writing_library_page.dart` | 34/w700/`letterSpacing:-1`、卡片 20 圆角、FAB 彩色阴影、空态 28 圆角容器 | 32/w600/0、14.4 圆角、`shadowXs` |
| 设置 `settings_page.dart` | 字号锁 1.2；`CupertinoSwitch`；行内 40% 宽度上限 | 拆 clamp、换 `AppSwitch`、尾值 62% |
| 统计 `reading_stats_page.dart` | 每个区块一张卡（今日/7 天/每本书）、5 种圆角、30/w700 数字、柱状图双色 | 一个表面 + 3 个分组；柱状图单色 |
| 阅读器 chrome | 44dp 顶栏、alpha 派生色、120ms 动画、`easeOutCubic` | 保留 Fanqie 版式（产品决策），只换色与动效 |
| 8 个 sheet | 顶圆角 12/16/20 三套；无 grabber；footer 各自实现 | 收敛到一个 `AppSheet` 规格 |

---

## 2. 目标设计语言

### 2.1 保留什么（VELLUM 的差异性）

skill 的参考色是绿色单强调。VELLUM 的 terracotta 是品牌资产，不该换掉。做如下映射：

| skill 角色 | VELLUM 对应 | 说明 |
|---|---|---|
| `controlActive`（固定绿，开关填充） | **不发绿**，用 `primary` | 开关状态另有轨道形状作非颜色线索 |
| `primary`（强调动作、选中、可调进度） | **terracotta**（调深） | 一个屏只有一个 terracotta 元素 |
| `brand`（仅 logo 画稿） | VELLUM 字标、默认封面 | 封面渐变 → 改为纯色（去装饰性渐变） |
| 正文中性灰 | **暖中性**（不是纯灰） | "羊皮纸"气质靠色温，不靠饱和度 |

**这是本方案最重要的一条**：把 terracotta 从"到处都有的装饰色"降级为"承载信息的强调色"。
现状里 accent 出现在：进度条、百分比、文件夹选中 chip、统计柱、图标底色、空态图标、FAB、书签……
按 skill，**一屏只允许一个**。

### 2.2 颜色（`AppPalette` → `AppColors`）

语义角色表（L/D，附实测对比度）：

| 角色 | Light | Dark | 用途 |
|---|---|---|---|
| `background` | `#F5F3EF` | `#0F0E0D` | 页面底 |
| `backgroundSubtle` | `#FAF8F5` | `#151311` | 内嵌区、浅色模式侧栏 |
| `card` | `#FFFFFF` | `#1B1917` | 分组块、列表块 |
| `popover` | `#FFFFFF` | `#1B1917` | 菜单、sheet |
| `foreground` | `#1C1B18` | `#EDEBE6` | 主文字、前导图标（L 15.5:1 / D 14.7:1） |
| `mutedForeground` | `#5C5954` | `#A3A099` | 次文字、chevron、说明（L 6.3:1 / D 6.7:1） |
| `foregroundTertiary` | `#8C8880` | `#8A8681` | 三级（L 3.5:1 仅限大字号/非文本） |
| `primary` | `#8F4A2E` | `#E39B76` | 强调动作、选中、进度（L 5.95:1 / D 7.69:1） |
| `primaryForeground` | `#FFFFFF` | `#0F0E0D` | 主按钮上的字 |
| `secondary` | black 5% | white 7% | 中性填充、chip 底、图标盘 |
| `secondaryActive` | black 10% | white 13% | 按下态 |
| `border` | black 8.1% | white 9% | 默认发丝线 |
| `borderSubtle` | black 5% | white 7% | 最淡分隔 |
| `borderStrong` | black 21% | white 24% | 控件描边 |
| `borderSelected` | black 44% | white 54% | 选中 chip 描边、开关关闭轨道 |
| `destructive` | `#B3261E` | `#FF6B63` | 删除（L 6.54:1 / D 6.29:1） |
| `success` | `#107D32` | `#00CA50` | 状态 |
| `warning` | `#8A5300` | `#FF9300` | 状态 |
| `info` | `#1F5FA8` | `#47A8FF` | 状态 |
| `scrim` | black 40% | black 40% | 遮罩 |
| `constantBlack/White` | `#000/#FFF` | 同 | 不受控内容上的 chrome |

关键改动：

1. **`primary` 从 `#A95C46` 降到 `#8F4A2E`**。`#A95C46` 在 `#F5F3EF` 上是 **4.40:1**，
   作为文字色不达 4.5 —— 而它现在正被当作"已读 42%"的正文色用。
2. **`mutedForeground` 从 `#756C65` 提到 `#5C5954`**。字号降到 13 之后必须补对比度。
3. **新增 `foregroundTertiary`**。现在所有"更淡的灰"都是 `muted.withValues(alpha: .7/.8)` 现场调的，
   实测掉到 2.8:1。给一个固定档，只用于非文本图形。
4. **删除 `softAccentOf`**（accent@12%）。淡彩是"用颜色分区"的典型，进度条底改用 `border`。

例外（写进代码注释，否则会被后来者当成欠债删掉）：

| 例外 | 归属 | 说明 |
|---|---|---|
| `readerWhite/Sepia/Mint/Blue/Night/...` | 用户数据（upstream of tokens） | 纸张色是**持久化的用户选择**，不是主题角色 |
| `readerInkFor(paper)` | upstream of tokens（按亮度取墨） | 产出**就是**色彩决策，读回 token 是循环 |
| 封面上的字与进度条 | chrome over uncontrolled content | 背景是图片，只能用 `constantBlack/White` |
| `DefaultCover` 的纯色底 | artwork | 品牌画稿；但必须从渐变改为纯色 |

### 2.3 形状

基准 8，其它档位是倍数：

| Token | 值 | 用途 |
|---|---|---|
| `AppRadius.sm` | 4.8 | 小控件、内层 chip |
| `AppRadius.md` | 6.4 | 缩略图、封面瓦片 |
| `AppRadius.lg` | 8 | 输入框、卡片 |
| `AppRadius.xl` | 11.2 | 默认按钮 |
| `AppRadius.grouped` | 14.4 | **分组块**（设置 / 统计 / 最近加入） |
| `AppRadius.xl2` | 17.6 | 封面瓦片、浮动容器 |
| `AppRadius.xl3` | 20.8 | 菜单面板、**sheet 顶部圆角** |
| `AppRadius.pill` | 9999 | chip、标签、开关、头像 |

- 现有 `circular(16)` 全部落到 `grouped(14.4)` 或 `xl3(20.8)`，不再有 16。
- 现有 `circular(10)`（15 处，最多）落到 `xl(11.2)` 或 `lg(8)`。
- **纸质例外**：书籍封面瓦片 = 书是实物，需要更锐的角 → 封面统一 `md(6.4)`，
  在 token 注释里写明"这是唯一低于 lg 的卡片角，因为它是拟物对象"。比现在的 9/10/4 三种好得多。

### 2.4 字体

13 级阶梯，索引即无障碍台阶：

```dart
const AppTypeSequence = <(double, double)>[
  (13, 18), (14, 20), (16, 24), (18, 28), (20, 26), (24, 32), (32, 40),
  (40, 48), (48, 56), (60, 72), (72, 96), (96, 128), (128, 128),
];
// xs, sm, base, lg, xl, 2xl, 3xl, 4xl, 5xl, 6xl, 7xl, 8xl, 9xl
```

产品角色映射（这就是 VELLUM 要落到 TextTheme 的槽位）：

| 角色 | 档位 | 权重 | 现状 |
|---|---|---|---|
| 页面大标题 | `3xl` 32/40 | semibold | 首页 28、写作 34、主题 34 → 全部 32 |
| 分组标题 | `base` 16/24 | semibold | `CupertinoListSection.header` 默认口径 |
| 行标题 | `base` 16/24 | regular | `CupertinoListTile.title` |
| 行副标题/说明 | `sm` 14/20 | regular | 现在混用 11/12/13 |
| 元信息/计数 | `xs` 13/18 | regular | 现在 10/11/12 |
| 按钮标签 | `base` | medium | — |
| 分组页脚 | `sm` | regular | — |

- **10/11/12 三个字号全部消灭**：最小 13。这是"元信息可读"的下限。
- **w700 → w600**（12 处）；w500 只用于按钮；w300 只用于阅读器正文的"细体"选项（内容排版，豁免）。
- 品牌字标 `VELLUM` 保留 `letterSpacing: 2.2` —— 写成一行注释作为唯一例外。

### 2.5 间距

4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 / 64。

现状的重点是**重复 gutter**：

| 位置 | 现在 | 问题 |
|---|---|---|
| `library_page.dart` 搜索 18 / 网格 14 / chip 18 | 三套 | 页面 gutter 必须 16，由 list 拥有，行不带外边距 |
| `home_page.dart` `ListView(20,12,20,28)` | 20 | → 16 |
| `writing_library_page.dart` 24 / 20 | 24 | → 16 |
| `settings_page.dart` `insetGrouped` 默认 | 20 | 由 `AppSection` 统一 16 |

### 2.6 表面与边框

**一个连续表面**是默认态。加表面/边框要先过这一问：

> 它表达的是选中、可交互、警示，还是一种间距表达不了的"真实分组"？

按现状对照：

- 统计页 6 张卡 → **1 个表面 + 3 个分组 + 发丝线**。
- 首页"继续阅读"卡有交互，可以留表面，但**去掉阴影和外边框**。
- 书库网格：书封是内容（图片），不需要"外框 + 阴影 + 内剪裁"三重包裹。
- 空态：图标不要放在彩色圆盘里（`softAccentOf`）—— 用 `secondary` 盘，或不用盘。

发丝线：`1 / devicePixelRatio`、`border`、从内容边缘内缩 12（有前导图标时 44）。

### 2.7 动效

```dart
settle    = Cubic(0.22, 1.00, 0.36, 1.00)   // 默认：改变已有东西的尺寸/位置
overshoot = Cubic(0.34, 1.25, 0.64, 1.00)   // 从无到有（sheet、toast、菜单）
linear    = Curves.linear                    // 进度循环
fast = 200 / base = 250 / slow = 350
```

替换清单：

- `easeOutCubic`(8) → `settle`
- `easeOut` / `easeOutQuad`(4) → `settle`
- `easeInOut`(2) → 删除或 `settle`（skill：ease-in 读作"界面犹豫了一下"）
- 120ms（书签条）、160ms（设置面板 `AnimatedSize`）→ 200ms
- 所有 `AnimatedContainer` 只动 transform / opacity / color，不动 padding 与高度

**reduced motion**：一个 `motionDuration(context, d)` 工具函数读 `MediaQuery.disableAnimationsOf`，
保证关掉动效后状态仍完整、可操作。

---

## 3. Token 层设计（落地骨架）

在 `lib/theme/` 下新增五个文件，**`vellum_theme.dart` 变成组装点**：

```
lib/theme/
  app_palette.dart    ← 原始色阶（字面量只允许出现在这里）
  app_colors.dart     ← AppColors ThemeExtension（语义角色，全 required）
  app_shape.dart      ← AppRadius / AppSpace
  app_type.dart       ← AppType 阶梯 + 角色映射
  app_motion.dart     ← AppMotion 曲线/时长 + reduceMotion 工具
  vellum_theme.dart   ← 组装 ThemeData + 访问器（旧 getter 保留为 @Deprecated 转发）
```

```dart
// app_colors.dart
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background, required this.backgroundSubtle,
    required this.card, required this.popover,
    required this.foreground, required this.mutedForeground,
    required this.foregroundTertiary,
    required this.primary, required this.primaryForeground,
    required this.secondary, required this.secondaryActive,
    required this.border, required this.borderSubtle,
    required this.borderStrong, required this.borderSelected,
    required this.destructive,
    required this.success, required this.warning, required this.info,
    required this.scrim, required this.constantBlack, required this.constantWhite,
  });
  // ... fields
  static const light = AppColors(/* 上表 L 列 */);
  static const dark = AppColors(/* 上表 D 列 */);

  @override
  AppColors copyWith({ /* 全字段 */ }) => AppColors(/* ... */);

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) => AppColors(
    background: Color.lerp(background, other!.background, t)!,
    // ... 每一个字段都要实现
  );
}
```

访问器（替代 9 个静态 getter，保持调用点极短）：

```dart
extension VellumColors on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColors>()!;
}
// 用法：context.c.primary
```

**迁移期兼容**：`VellumTheme.inkOf(context)` 等 9 个方法保留，内部改为转发到 `context.c`，
标 `@Deprecated('改用 context.c.*')`，第 6 批统一删除 —— 这样 40 个文件可以分批改而不至于一次性编译不过。

**为什么用 `Theme.of` 而不是 `CupertinoTheme.of`**：`CupertinoThemeData` 没有 extension 槽位。
做法是把 App 从 `CupertinoApp(theme:)` 改为 `MaterialApp` 外壳 + `ThemeData(useMaterial3: true)`，
并在 `builder` 里继续挂 `CupertinoTheme`，从而照常使用 `CupertinoPageScaffold / NavigationBar / ListTile`。

> 这是一个结构性决定，两条路：
> **(a) 换 `MaterialApp` 外壳**（推荐）：一次性成本，换来标准 token 层。
> 　　Material 只提供 `ThemeExtension` 与 `MaterialLocalizations`，`Cupertino*` 组件与
> 　　`CupertinoPageRoute` 边缘返回手势照常工作；`useMaterial3` 的卡片/阴影 idiom 我们不用。
> **(b) 自建 `InheritedWidget` 包 token**：不动 App 类型，但与 skill 的
> 　　`Theme.of().extension` 惯例分叉，后续每加一个基元都要多写一层。

---

## 4. 组件基元（新建 8 个，收敛重复实现）

| 组件 | 替代现状 | 规格要点 |
|---|---|---|
| `AppPage` | 各页自己的 `SafeArea + padding` | 16 gutter；底部 `viewPadding.bottom + 24`；宽屏 `maxWidth 720` |
| `AppSection` | `CupertinoListSection.insetGrouped` + 6 处手写卡片 | 14.4 连续圆角、`Clip.antiAlias`、表头 40/12、行 44/56、发丝线内缩 12 |
| `AppRow` | `CupertinoListTile` + 手写 Row | 前导 16 图标 + 12 gap；尾值 **max 62%** 省略；按下 `foreground@5%` |
| `AppSwitch` | `CupertinoSwitch`（3 处） | 44×24；开 `primary`、关 `borderSelected`；白拇指 + 30% 黑环 |
| `AppButton` | `CupertinoButton` 的 color/borderRadius 自由组合 | 变体 default / secondary / tonal / ghost / destructive；**一个表面只允许一个 default** |
| `AppChip` | `_folderChip` 与其它筛选 | pill；`secondary` 底；选中 `secondaryActive` + `borderSelected` |
| `AppContentState` | 5 处空态 + 3 处错误态 | loading/empty/error 三态一个组件；错误带重试；说明可选中 |
| `AppSheet` | 8 个 sheet 各自实现 | 顶角 20.8；grabber 36×5；footer 继承 sheet 底；`popover` 与页面 `background` 区分 |

`AppToast` 排在批次 5（需要先把 6 处"结果型 alert"改成 toast）。

---

## 5. 逐页改造方案

### 5.1 首页 `home_page.dart`（255 行 → 约 200 行）

现状：`VELLUM` 字标导航栏 + 28px 大标题「继续阅读」+ 16 圆角带阴影卡 + 28 间距 + 「最近加入」分组。

目标结构：

```
[安全区]
  32/40 semibold  继续阅读                       ← 与书库/写作同一档大标题
  ┌ grouped 14.4 块（无边框、无阴影）─────────────┐
  │ 78×112 封面    书名 16/24                      │
  │                作者 · EPUB · 1234 段（13/xs）  │
  │                ── 进度条（border 底 + primary 3pt）
  │                已读 42%   ← 13/xs muted，不染色 │
  └────────────────────────────────────────────────┘
  24
  分组标题「最近加入」16/semibold        右侧 "12 本" 13/muted
  ┌ grouped 块 ─────────────────────────────────── ┐
  │ 行  (42×58 封面) 书名 16 · 元信息 13 · chevron  │
  └────────────────────────────────────────────────┘
```

关键改动：

1. 大标题 28 → **32/40 semibold**（`titleLarge` 槽）。
2. 继续阅读卡的 `boxShadow` 与 `Border.all` **删除**。
3. "已读 42%" 从 `accent` + `w600` 改为 `mutedForeground` + regular —— 进度条已经承载"进度"，
   文字再染色就是双重编码（skill：数字不因为是好消息就变绿）。
4. 进度条底 `softAccentOf` → `border`；高 4 → 3；圆角 `circular(3)` → 1.5。
5. 卡内 `Divider(indent: 74)` 思路正确，但 indent 应由 `AppSection` 按"行内缩 12 + 缩略图宽 + gap"计算。
6. 页脚「安静地读一本书」保留（产品语气），降为 `xs` muted 并移到分组页脚。

### 5.2 书库 `library_page.dart`（443 行 → 约 380 行）

1. **gutter 统一 16**：搜索 `(18,12,18,4)` → `(16,12,16,4)`；网格 `(14,8,14,28)` → `(16,8,16,24+inset)`。
2. **搜索框**：`CupertinoSearchTextField` 默认 8 圆角 → `pill`（skill：默认搜索框必 pill，高 40）。
3. **文件夹 chip**：12px 字 / 16 圆角 → `xs(13)/pill`；选中用 `secondaryActive` + `borderSelected` 描边，
   不再用 accent 填充（这一屏的 accent 落点应留给进度）。
4. **网格卡片**：三层包裹（`Border.all` + `BoxShadow` + `ClipRRect(9)`）→ 一层 `ClipRRect(6.4)`，
   去掉阴影；书封底部进度条保留（chrome over content 豁免），但 10px 数字 → 13/xs。
5. **删除按钮**：`onCover` 变体的 `BoxShadow` 删；保留 `constantBlack@42` 圆盘 + 白图标。
6. **空搜索态**（裸 `Text`）→ `AppContentState.empty`，带"清除搜索"作为下一步动作。
7. **列数断点** 2/3/4/5/6 保留（合理的内容栅格），但 `childAspectRatio` 改为按
   `mainAxisExtent` 计算，避免文字缩放时封面被压扁（skill Phase 6/9）。

### 5.3 写作 `writing_library_page.dart`（454 行 → 约 400 行）

1. **大标题**：34 / w700 / `letterSpacing: -1` → **32 / w600 / 0**。
2. **卡片**：20 圆角 → `grouped(14.4)`；`WritingStyle.paper` → `context.c.card`（删掉 `writing_style.dart`）。
3. **FAB**：彩色 `BoxShadow(blur 20)` → `shadowXs`；24 圆角 → pill + 56 尺寸 + `primary` 填充。
4. **空态**：28 圆角容器 + accent 图标 → `AppContentState`，图标盘 `secondary`。
5. **搜索框**：14 圆角 → `pill`。
6. `mainAxisExtent: 226 * scale` 这种"自己乘缩放"要删 —— 高度应由内容与 `textScaler` 自然撑开。

### 5.4 设置 `settings_page.dart`（801 行 → 约 550 行）

这是**收益最大**的一页，也最容易做错。

1. **拆掉 `MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2)`**（462 行）。
   拆掉后会暴露行高问题，所以必须同时做第 2 条。
2. **`CupertinoListTile` → `AppSection` + `AppRow`**：行高从固定改为 `ConstrainedBox(minHeight: 56/44)`，
   文字放大时行自然变高。
3. **`CupertinoSwitch`（2 处）→ `AppSwitch`**。
4. **尾值宽度**：现在是 `MediaQuery.sizeOf(context).width * .4`，改为行内 62% 上限，由 `AppRow` 计算。
5. **`_info(context, …)` 这个 overflow 补丁可以整体删除** —— `AppRow` 从设计上就不会溢出。
6. **分组数保持 6**（外观 / 字体 / 工具 / 阅读数据 / 软件更新 / 存储管理），但组间间距由 `AppSection` 统一 24。
7. **`_showUpdateDialog`（3 处）**：语义是"一次操作的结果"，改 toast。
8. 设置页是"每行都有 leading 图标"的页面，符合 skill 的"只在每行都有时用图标"，**保留**，
   但图标统一 20pt stroke + `mutedForeground`。

### 5.5 阅读统计 `reading_stats_page.dart`（323 行 → 约 280 行）

1. 逐区块的卡片 → **1 个 `background` 表面 + 3 个 `card` 分组块**（今日 / 最近 7 天 / 按书籍），
   书行合并成「按书籍」这一组内的连续行。
2. 圆角 22/18/16 → 统一 `grouped(14.4)`；块内不再有边框。
3. 数字 30/w700 → `2xl 24/32 semibold`（它不是页面标题，不该用 32）。
4. 柱状图：双色（`accent` / `accent@35%`）→ **单色 `primary` + 今日用 `foreground`**，
   靠 `xs` 标签区分，不靠颜色区分。
5. 进度条底 `accent@12%` → `border`。
6. 每本书的行：独立卡片 → 合并进一个分组块的连续行 + 发丝线。
7. 顶栏"重置"的 `CupertinoColors.destructiveRed` → `context.c.destructive`。

### 5.6 阅读器 chrome（`reader_chrome.dart` / `reader_controls.dart` / `reader_panel_common.dart`）

**版式不改**：44dp 顶栏、左对齐章节名、页码/电量底条是 Fanqie 的产品决策，属于产品规格而非设计系统债务。
只改三件事：

1. **对比度**
   - 页眉 `ink@.38` → `readerTertiaryInk(paper)`，目标 ≥ 4.5:1（文本）。当前 2.64:1 不合格。
   - 状态条 `.55` → `.68`（4.65 → 约 5.9:1）。
   - `reader_panel_common.dart` 的 12px 行标签 → 13/xs 且 `.72`。
2. **动效**：120ms → 200ms `settle`；`easeOutCubic / easeOut` → `settle`；
   `AnimatedSwitcher` 的 `ScaleTransition` 改 `FadeTransition`（浮层里缩运动会抖）。
3. **派生色收敛**：chrome 里散落至少 9 处 `ink.withValues(alpha: .xx)`，
   收敛为 `ReaderInk.text / secondary / tertiary / hairline` 四个函数，各钉死最低 alpha。

`reader_settings_panel.dart`（20 个 `fontSize`）是字号最密处：把行标签、分组标题、数值标签
分别映射到 `xs / sm / base`，面板内**只允许 3 个字号**。

### 5.7 八个 sheet 与 19 处 alert

- sheet 统一为 `AppSheet`：顶角 **20.8**（不是 12/16/20 三套）、grabber、`popover` 底、
  footer 继承 sheet 底 + 底部内边距 = `inset + 8`。
- 反馈归属重排：

| 场景 | 现在 | 应该 |
|---|---|---|
| 导出成功「已导出 N 条笔记…」 | alert | toast |
| 导入失败（可重试） | alert | inline `AppContentState.error` + 重试 |
| 字体导入结果 | alert | toast（失败明细另开 sheet） |
| 清空书库 / 删除书籍 / 重置统计 | alert | **保留**（必须做的决定） |
| 「格式无效」 | alert | inline 字段错误 |

---

## 6. 迁移路线（6 批，每批可独立提交）

### 批次 0 — 护栏（0.5 天）
加 `tool/design_lint.ps1`：跑 8 条 grep 门，**白名单 = 今天的所有命中数**，只降不升。
这样后续每一批都能"看到数字变小"，新代码也不会被写脏。

### 批次 1 — Token 层（1 天）
1. 新增五个 theme 文件。
2. `VellumTheme` 改写为构造 `ThemeData(useMaterial3: true)` + `extensions: [AppColors.light/dark]`。
3. `app.dart` 从 `CupertinoApp` 换 `MaterialApp` 外壳，`builder` 里挂 `CupertinoTheme`。
4. 旧 9 个 getter 改 `@Deprecated` 转发 → **全项目仍能编译**。

**门**：`flutter analyze` 0 error；`Color(0x` 命中数仍 ≤ 61（本批不动 widget）。

### 批次 2 — 基元（1 天）
1. 写 `AppPage / AppSection / AppRow / AppSwitch / AppButton / AppChip / AppContentState / AppSheet`。
2. 每个基元配 pump 测试：浅/深 × `textScaler 1.0/2.0`。

### 批次 3 — 三个主页面（1.5 天）
**设置 → 首页 → 书库**（设置收益最大，先做可当样板）。

**门**：这三个文件 `fontSize:` = 0、`Color(0x` = 0、`circular(<数字>)` = 0。
**核心验收**：`textScaler 2.0` 下设置页不裁剪、不塌行。

### 批次 4 — 其余页面（1.5 天）
写作 → 统计 → 备份/TTS/导入页 → 12 个 sheet。

**门**：全项目 `BoxShadow` 10 → 3；`CupertinoSwitch` = 0；sheet 顶角只剩一个值。

### 批次 5 — 阅读器 chrome（1 天）
只改色 / 动效 / 对比度，不动版式。

**门**：chrome 内 alpha 派生色收敛到 4 个函数；页眉对比度 ≥ 4.5。

### 批次 6 — 收尾（0.5 天）
1. 删除 `writing_style.dart`、`VellumTheme.paper/card/ink/softAccentOf`、9 个 `@Deprecated` getter。
2. 白名单清零，`design_lint` 从"只降不升"变成"必须为 0"。
3. 写 `developDoc/2026-11-xx-ui-design-system.md`：固化 token 表与例外条款。

**回滚点**：批次 1 结束是一个完整可发布态（只换底座、视觉不变）；批次 3 结束是第二个。

---

## 7. 验收清单

代码门（每批都跑）：

- [ ] `flutter analyze` 0 error / 0 新增 lint
- [ ] widget 内 `Color(0x` 命中数 = 白名单（逐批下降）
- [ ] widget 内 `fontSize:` = 0（阅读正文除外，属内容域）
- [ ] widget 内 `BorderRadius.circular(<数字>)` = 0
- [ ] `FontWeight.w700` 及以上 = 0
- [ ] `BoxShadow` 只出现在 3 个 token 定义处
- [ ] `Curves.ease(out|inOut|OutQuad)...` = 0（`Curves.linear` 除外）
- [ ] `CupertinoSwitch` = 0；`CupertinoColors` 仅剩豁免处

视觉 / 无障碍门（批次 3、4、5 各跑一次）：

- [ ] 浅色 + 深色双主题，覆盖每个被改动的表面
- [ ] `textScaler` 1.0 / 1.5 / 2.0：标题不裁、行不塌、按钮不掉字
- [ ] 断点 360 / 560 / 820 / 1120 旋转不丢滚动位置、不重建页面
- [ ] 每屏"一个主对象"，眼睛第一落点清楚
- [ ] 被改动的交互在 `disableAnimations` 下有完整形态
- [ ] 对比度实测：正文 ≥ 4.5、图形/边框 ≥ 3.0（本方案已给出关键配对数值，实施时逐条复核）

---

## 8. 风险与取舍

| 风险 | 影响 | 缓解 |
|---|---|---|
| `CupertinoApp` → `MaterialApp` 外壳 | 主题/locale 行为变化，`CupertinoPageRoute` 手势需回归 | 批次 1 单独提交，整体回归 4 个 tab + 阅读器 |
| 拆掉设置页 1.2 缩放上限 | 暴露既有行高问题 | 与 `AppSection` 同批做，先做一个页面的 golden |
| 纸张色不在 token 内 | 会被后来者当欠债删掉 | `app_palette.dart` 顶部注释写死"用户数据，不是主题角色" |
| accent 全局降级 | 观感"变灰" | 每屏保留**一个** primary 落点（进度条 / 选中行 / 主按钮），评审时逐屏确认 |
| 封面圆角 9/10 → 6.4 | 书封观感变化 | 只改封面瓦片；列表缩略图保持 `sm(4.8)` |

**明确不做**：

- 不改阅读器版式（44dp 顶栏、页码条、翻页方式）—— 这是产品规格。
- 不改网格列数策略 —— 这是内容栅格。
- 不引入绿色 `controlActive` —— VELLUM 的开关用 `primary`，品牌色已能表达"开"，
  且轨道形状差异是非颜色线索。
- 不做"仅 Android 用 Material" —— skill 的第一硬性规则是一套身份。

---

## 附录 A：文件级改动清单

| 文件 | 动作 | 优先级 |
|---|---|---|
| `lib/theme/app_palette.dart` | **新建** | P0 |
| `lib/theme/app_colors.dart` | **新建** | P0 |
| `lib/theme/app_shape.dart` | **新建** | P0 |
| `lib/theme/app_type.dart` | **新建** | P0 |
| `lib/theme/app_motion.dart` | **新建** | P0 |
| `lib/theme/vellum_theme.dart` | 重写 | P0 |
| `lib/app.dart` | 换外壳；tab bar 收 token；导入遮罩 20 → `xl3` | P0 |
| `lib/widgets/app_*.dart`（8 个） | **新建** | P0 |
| `lib/pages/settings_page.dart` | 大改（拆 clamp、换基元、toast） | P1 |
| `lib/pages/home_page.dart` | 中改 | P1 |
| `lib/pages/library_page.dart` | 中改 | P1 |
| `lib/pages/writing_library_page.dart` | 中改；删 `writing_style.dart` | P1 |
| `lib/pages/reading_stats_page.dart` | 大改（6 卡 → 3 分组） | P2 |
| `lib/pages/book_widgets.dart` | 中改（去阴影/边框/渐变） | P2 |
| `lib/pages/*_sheet.dart`（8 个） | 收敛到 `AppSheet` | P2 |
| `lib/reader/reader_chrome.dart` | 对比度 + 动效 | P3 |
| `lib/reader/reader_panel_common.dart` | 字号 / 对比度 | P3 |
| `lib/reader/reader_controls.dart` | 阴影 token + 动效 | P3 |
| `lib/reader/reader_settings_panel.dart` | 20 处字号 → 3 档 | P3 |
| `lib/reader/reader_selection.dart` | 10 个字面量 → 纸张墨色函数 | P3 |
| `lib/reader/reader_color_picker.dart` | 遵守"仅数据色可字面量" | P3 |
| `lib/pages/writing_style.dart` | **删除** | P4 |
| 9 个 `@Deprecated` getter | **删除** | P4 |

## 附录 B：立即可执行的前 10 个改动

按"改动小 / 效果大"排序：

1. `settings_page.dart` 删除 `withClampedTextScaling`。
2. 三处阴影删/收（`home_page.dart` 继续阅读卡、`book_widgets.dart` 封面卡、`writing_library_page.dart` FAB）。
3. 全局 `10 / 11 / 12` 号字 → `13`。
4. 全局 `w700` → `w600`。
5. `circular(16)` → `14.4`；`circular(10)` → `11.2`。
6. `accent #A95C46` → `#8F4A2E`；`darkAccent #D8896C` → `#E39B76`。
7. `softAccentOf` 的所有用处 → `border` 或 `secondary`。
8. `reader_chrome.dart` 页眉 `.38` → `.60`；状态条 `.55` → `.68`。
9. `writing_library_page.dart` 的 `34/w700/-1` → `32/w600/0`。
10. 6 个 sheet 的 `Radius.circular(16)` → `20.8`。
