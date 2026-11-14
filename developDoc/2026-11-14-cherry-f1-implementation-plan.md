# Vellum 对齐 Cherry Studio：F1 保真度 + 保留浮空 dock 的实施计划

> 依据：`C:\Users\Omnip\Downloads\vellum-restyle-plan.md`（下称"原方案"）+ `apple-like-skill` 的
> `references/geometry.md`、`references/roles.md`、`reference/test/spec_test.dart`
> 已核定：原方案的基线表与当前代码 **逐项吻合**（ListTile 14、Button 84、Icons 120、
> fontSize 161、CupertinoColors 24、AppSection 10 / AppRow 23）。
> 你的两个决定：**F1（保留暖纸 + terracotta）**、**保留浮空 dock（声明为偏差）**。

---

## 0. 目标与成功标准

原方案的目标是"一套语言、一次收口，并让偏差可被测试发现"。按 F1 落地后：

1. **几何全部对齐** geometry.md：行 40 下限 / 自然 48、表头 40 距块 4、分隔线 44/12 且按压隐藏、
   前导 16、尾随 foreground、chevron 20 muted。
2. **组件语言收口**：`CupertinoListTile` 14 → 0，`CupertinoButton` 84 → 0（系统 chrome 除外），
   产品图标换描边集。
3. **偏差被声明而不是被掩盖**：F1 的品牌覆盖表 + dock 覆盖条目进仓库，
   conformance test 对每条偏差有对应的显式断言。
4. **护栏会失败**：`tool/design_lint.ps1` 基线归 0 + 例外白名单（带理由）。

**不做**：不改调色板取值、不改阅读器纸张与正文排版、不改动效的既有行为语义（见 §7 待确认项）。

---

## 1. F1 的具体含义（与原方案 F2 的差异）

原方案 P1 是"换中性色板 + 绿强调"。F1 下 **P1 的取值替换全部跳过**，只做三件事：

### 1.1 保留的取值（不动）

| 角色 | 保留值 | 说明 |
|---|---|---|
| `background` | `#F5F3EF` / `#0F0E0D` | 暖纸底 |
| `primary` | `#8F4A2E` / `#E39B76` | terracotta，5.95:1 / 7.69:1 |
| `foreground / mutedForeground / border` | 现值 | |
| `destructive` | `#B3261E` / `#FF6B63` | 6.54:1 / 6.29:1，已达标，不换 `#FC0035` |
| 阅读纸张 `readerWhite/Sepia/...` | 现值 | 用户数据，豁免 |

### 1.2 新增角色（结构对齐必须，取值映射到现有品牌）

`app_colors.dart` 新增 4 个必填字段（两套主题 + `copyWith` + `lerp` 都要补）：

| 新角色 | Light | Dark | 为什么必须有 |
|---|---|---|---|
| `controlActive` | `= primary`（`#8F4A2E`） | `= primary`（`#E39B76`） | 开关"开"的语义角色。**当前代码直接读 `primary`**，等于让开关和强调色共用一个角色；加一层后组件不再知道品牌色 |
| `link` | `= primary` | `= primary` | 文本按钮/链接角色；当前散用 `primary` |
| `destructiveForeground` | `#FFFFFF` | `#FFFFFF` | 实心删除按钮上的字；当前用 `constantWhite`（那是"不受控内容 chrome"的豁免角色，语义不对） |
| `secondaryForeground` | `#171717` | `#EDEDED` | `secondary` 上的文字；当前直接读 `foreground`，两者在暗色下不同层 |

`sidebar`：Vellum 没有宽屏左栏，**不加**（避免造一个没人用的角色）。

### 1.3 删除

- `vellum_theme.dart` 里 12 个 `@Deprecated` 别名（`shellPaper/shellCard/shellInk/shellMuted/shellLine`
  及 dark 组）——迁移调用点后删除。当前已无调用（上轮已全部改成 `context.c.*`），只是残留声明。
- 保留 `VellumTheme.accent / darkAccent`：它们是品牌常量的**公开读法**，测试与字体预览依赖它。

---

## 2. 品牌覆盖表（要进仓库）

落 `developDoc/design-fidelity-overrides.md`，每条写"是什么 / 为什么 / 何时复核"：

| # | 偏离项 | Cherry 标准 | Vellum 取值 | 理由 |
|---|---|---|---|---|
| 1 | 页面底 | `#F5F5F5` 中性 | `#F5F3EF` 暖纸 | 产品气质（"安静的书房"），已过对比度校验 |
| 2 | `primary` | 绿 `#107D32` | terracotta `#8F4A2E` | 品牌资产；作为文字色 5.95:1 达标 |
| 3 | `controlActive` | 固定绿 `#24B242` | `= primary` | 不引入第二强调色；开关状态另有**轨道形状**作非颜色线索 |
| 4 | 实心按钮填充 | `foreground`（黑/白） | `primary` | 主操作是品牌动作；一屏只允许一个 filled |
| 5 | 底部导航 | 标准 tab bar 49pt | **浮空 dock**（64pt 胶囊，radius 24） | 你指定；磨砂仅在胶囊区域，实测 0 丢帧 |
| 6 | 关闭曲线 | 3 曲线（无 dismiss） | 保留 `dismissCurve/dismiss` | 见 §7 待确认项；`settle` 反演是缓入，用作退场是错误的 |

**复核条件**：任一条与 `references/geometry.md` 或 `roles.md` 的对应条目再次分叉时，
先改本表再改代码（原顺序反了才会漂移）。

---

## 3. P2 · 几何与基元（可直接照改）

| # | 文件 | 现状 | 改为 |
|---|---|---|---|
| 1 | `theme/app_shape.dart:76-79` | `rowMinHeight = x11`(44)、`rowMinHeightLeading = x14`(56) | 都 **`x10`(40)**；行高由内容撑起 → 单行自然 48 |
| 2 | `app_shape.dart:35` | `AppRadius.dock = 26.8`（8×3.35） | **`24.0`**（8×3），注释写明是已声明的额外档 |
| 3 | `app_shape.dart` | 无 `pageTopGap` | 新增 `pageTopGap = x2`(8) |
| 4 | `widgets/ui/app_section.dart` 表头 | `minHeight: x8`(32)、bottom `x2`(8) | **`x10`(40)**、**`x1`(4)** |
| 5 | `app_section.dart` 分隔线 | 左 `x3`(12)、右 0 | 有前导 **左 44 / 右 12**；无前导 **12/12** |
| 6 | `app_section.dart` 前导图标 | `size: 20`、`mutedForeground` | **16**、**`foreground`** |
| 7 | `app_section.dart:227` 尾随值 | `mutedForeground` | **`foreground`** |
| 8 | `app_section.dart` chevron | `foregroundTertiary` | **`mutedForeground`**（20 不变） |
| 9 | `app_section.dart` chevron 语义 | `showChevron` 由页面手传 | **由行契约推导**：`onTap != null && value == null` → 右 chevron；有 value → 不显示 |
| 10 | `app_section.dart` 新增 | 无 | `AppSelectRow`（value + `chevron_down`）、`AppSwitchRow`（**整行可点**，开关只作指示） |
| 11 | `app_controls.dart:58` 开关 | on = `colors.primary` | **`colors.controlActive`** |
| 12 | `app_controls.dart` `filled` | `primary` 填充 | **`primary` 保留（F1 覆盖第 4 条）**，但标签改读 `primaryForeground` |
| 13 | `app_controls.dart` `destructive` 标签 | `constantWhite` | **`destructiveForeground`** |
| 14 | `app_page.dart` | 页面各自塞 `SizedBox(x4)` | `AppPage` 统一 `pageTopGap`，页面删除手写间距 |

### 分隔线按压隐藏（需要 section 级协调）

照搬参考实现的 `_SectionScope` 写法（`reference/lib/primitives/app_section.dart:40,162`）：

- `AppSection` 持有一个 `ValueNotifier<int?> _pressedRow`；
- 每行包 `_SectionScope(index, pressed)`，按下时写 `index`；
- 分隔线 `_SectionSeparator` 订阅：`pressed == 本行 || pressed == 上一行` → 颜色 alpha 0。

这让"按下时上下两条线一起消失"，不是只隐藏下面一条（后者会让行看起来上边框消失）。

---

## 4. P3 · 结构（设置页 + 其余页面）

### 4.1 设置页：大标题 + 无标题分组

现状（`settings_page.dart`）：
- `CupertinoNavigationBar(middle: Text('设置'))` —— 导航栏标题
- 6 个 `AppSection`，**每组都有 header**（外观/字体管理/工具/阅读数据/软件更新/存储管理）

改为：

```
[内容区，无导航栏标题]
设置                       ← 32/40 semibold，AppPage 给 8 顶部间距

[分组 1 · 无 header]       外观 / 字体管理 / 工具                 24
[分组 2 · 无 header]       阅读数据 / 软件更新                     24
[分组 3 · footer「危险操作」] 占用空间 / 清空书库 / 清除阅读记录      ← 破坏性动作单独成组
```

- header 只在"确实需要区分"时出现；每块都加 header 就是标签墙；
- `存储管理` 里的破坏性项拆到第 3 组，用 `footer` 警示，而不是和"占用空间"混在一起；
- 所有"value + 可点"的行改 `AppSelectRow`（value + chevron-down）——否则用户看不出能点。

### 4.2 其余页面

| 页面 | 改动 |
|---|---|
| 首页/书库/写作列表 | 大标题 32/40（已是）；卡片 14.4 + 暗色发丝边；无阴影（已是） |
| 统计/备份/TTS 等子页 | `AppInlineHeader`（16/24 semibold + 返回），替代 `CupertinoNavigationBar(middle:)` |
| 所有 sheet | 统一 `AppSheet`（已有）；把剩余 6 处自绘 sheet 收进来 |
| alert | 新增 `AppAlertDialog`（当前 19 处 `showCupertinoDialog` 在 Android 上弹 iOS 样式） |

---

## 5. P4 · 覆盖收口（按文件整页迁移）

### 5.1 CupertinoListTile 14 处 → 0

| 文件 | 处数 | 动作 |
|---|---|---|
| `backup_settings_page.dart` | 6 | `AppSection + AppSelectRow/SwitchRow` |
| `tts_settings_page.dart` | 3 | 同上 |
| `book_picker_sheet.dart` | 2 | `AppMenuRow` / `AppSection` 单选行 |
| `book_batch_import_page.dart` | 1 | 同上 |
| `notes_import_sheet.dart` | 1 | 同上 |
| `unassociated_notes_sheet.dart` | 1 | 同上 |

### 5.2 CupertinoButton 84 处 → 0（分批）

按原方案 P4 清单，先阅读器面板（11+10）、再 sheets（6+5+5），再其余。每文件内**整页替换**，
不页内混搭。允许保留：`CupertinoNavigationBar` 的返回（系统 chrome）。

---

## 6. P5 · 图标 + 护栏

### 6.1 图标换描边集

- 加依赖 `lucide_icons 0.257.0`（已验证可解析）；
- 120 处 `CupertinoIcons` → lucide；先建映射表（`book/pencil/gear/trash/search/chevron/plus/...`），
  缺字形的保留 `CupertinoIcons` 并进白名单；
- 白名单文件：系统 chrome（导航栏返回、阅读器顶栏返回）。

**爆点**：54 个测试断言引用了 `CupertinoIcons.xxx`。换图标必须同步改测试的 finder。
所以这一步放**最后**，先做几何/结构/覆盖，图标单独一个提交。

### 6.2 护栏归零

`tool/design_lint.ps1` 当前允许 161 字号 / 24 CupertinoColors / 13 颜色字面量——等于把漂移写进基线。
改为基线 0 + 白名单（每项带理由）：

| 规则 | 基线 | 白名单 |
|---|---|---|
| `Color(0x` | 0 | `theme/`（token）、`reader/` 的纸张取墨与调色器、封面 chrome |
| `fontSize:` | 0 | `reader/` 正文排版（用户字号是计算值） |
| `BorderRadius.circular(<数字>)` | 0 | 无（已 0） |
| `CupertinoListTile` / `CupertinoButton` | 0 | 系统 chrome |
| `CupertinoIcons` | 0 | 白名单文件 |
| `FontWeight.w700+` | 0 | 阅读器正文的粗体标记 |
| `Curves.ease*/bounce*/elastic*` | 0 | 无（已 0） |

新增**结构规则**：`AppSection` 的 `children` 里出现非行组件的包裹层 → 失败
（会破坏 44 缩进判定，这是上一轮的漂移原因）。

---

## 7. 动效：与原方案的唯一分歧（需要你点头）

原方案 §6.1 要**删除** `dismissCurve` 与 `dismiss`，关闭改用 `settle` 反向 + `fast`。

**我的异议**：`settle` 是减速曲线，**反演后是缓入**——用作退场正好是要避免的"界面犹豫了一下"。
上一轮你选了"面板从底部拉出"，我据此做的进/出分流（进 settle 250 / 出 dismissCurve 180）
是正确的，且 **conformance test 不会因此失败**（spec 只断言 settle/overshoot/linear 存在
与三档时长，不检查"恰好 3 条曲线"）。

**建议**：保留，作为覆盖表第 6 条声明。如果你坚持原方案，我按删除执行，
但要接受"关闭变成缓入"的手感回退。

**其余照做**：把 8 个手势窗口从 `AppMotion` 拆到独立 `AppGestureWindow`（它们不是动画时长）。

---

## 8. Conformance test（闸门）

复制 `reference/test/spec_test.dart` → `test/design_conformance_test.dart`，需要**真实改写**而非只换 import：

| 原断言 | Vellum 适配 |
|---|---|
| `AppColors.light.toMap()` | 给 `AppColors` 加 `toMap()`，或测试改为直接比对字段 |
| `controlActive == 0xFF24B242` | **改为** `controlActive == primary` + 注释指向覆盖表第 3 条（F1） |
| `button fill == foreground` | **改为** `== primary`（覆盖表第 4 条） |
| `AppSectionRow` | 改名 `AppRow` |
| `AppSectionSelectRow` | 新基元 `AppSelectRow` |
| `Icons.chevron_right / expand_more / cloud_outlined` | 换成 lucide 图标（与 §6.1 同步） |
| `AppSpec.sectionHeaderMinHeight` | Vellum 用 `AppSpace`，测试改引用；或加 `AppSpec` 别名 |
| 行 48 / 表头 40 / 分隔线 44/12 / chevron 20 muted / value foreground | **不改，必须真通过** |

**验收口径**：14 条里除 2 条 F1 覆盖项外全部真绿；不接受"为了通过而放宽断言"。

---

## 9. 提交顺序（每步可独立回滚）

| # | 提交 | 内容 | 闸门 |
|---|---|---|---|
| 1 | `feat(design): 新增语义角色 + dock 圆角归 8 倍数` | controlActive/link/destructiveForeground/secondaryForeground；dock 26.8→24；删 deprecated 别名；`AppGestureWindow` 拆分 | analyze + test |
| 2 | `chore(design): 对齐 geometry 数值` | 行 40 / 表头 40 距 4 / 分隔线 44-12 / 前导 16 foreground / value foreground / chevron muted | conformance 行几何 4 条绿 |
| 3 | `feat(design): 行语法 + SelectRow/SwitchRow + 分隔线按压隐藏` | chevron 推导、`_SectionScope`、两个新行 | conformance 全绿 + 设置页无"看不出能点"的行 |
| 4 | `feat(design): 设置页大标题与无标题分组` | 结构重排 + `AppPage.pageTopGap` | 截图对比 |
| 5 | `refactor(design): 覆盖收口（6 个 tile 文件）` | P4 前半 | `CupertinoListTile` = 0 |
| 6 | `refactor(design): 覆盖收口（reader 面板与 sheets）` | 其余 `CupertinoButton` | 覆盖率再降 |
| 7 | `chore(design): 图标换描边集` | 120 处 + 54 个测试 finder | `CupertinoIcons` 白名单外 = 0 |
| 8 | `chore(design): lint 基线归零 + 覆盖表` | `design_lint.ps1`、`design-fidelity-overrides.md` | lint 0/0 |

---

## 10. 验收清单

- [ ] `design-fidelity-overrides.md` 已入库（6 条，每条带理由与复核条件）
- [ ] conformance test 14 条：12 条真通过 + 2 条 F1 覆盖项
- [ ] `CupertinoListTile` = 0；`CupertinoButton` = 0（白名单除外）；`CupertinoIcons` 白名单外 = 0
- [ ] `fontSize:` 白名单外 = 0；`BorderRadius.circular(<数字>)` = 0
- [ ] 行 40 下限 / 自然 48 / 表头 40 距块 4 / 分隔线 44-12 且按压隐藏
- [ ] 设置页：无"每组都有 header"、无"value 行没 chevron"、无 56 行高
- [ ] 亮/暗 × textScale 1.0/2.0 × 320pt/720pt 四组真机截图
- [ ] 阅读器纸张/正文颜色未变
- [ ] `flutter analyze` 无新增；`flutter test` 全绿；`design_lint` 0

---

## 11. 风险

| 风险 | 处理 |
|---|---|
| 54 个测试断言引用 `CupertinoIcons` | 图标单独一个提交，先改代码再一次性改 finder；不混进几何提交 |
| 行高 56→48 改变既有布局 | `settings_layout_test`、`reader_panel_overflow_test` 可能失败——这是**设计意图变化**，更新断言而非回退数值 |
| lucide 缺字形 | 先跑映射表，缺的保留 `CupertinoIcons` 进白名单（带理由），不硬造图标 |
| F1 覆盖表变成"永远不看的文档" | 覆盖表 6 条各自对应 conformance test 里一条显式断言；改代码不改表 → 测试失败 |
| 一次性大改难回滚 | 按 §9 的 8 个提交推进，每步跑闸门 |

---

## 12. 需要你先点头的一件事

**§7 的动效分歧**：原方案要删 `dismissCurve/dismiss`、关闭改用 `settle` 反向。
我建议保留并写进覆盖表（理由：反演减速曲线 = 缓入，做退场是错的；且不破坏 conformance test）。
若你同意，我按"保留"执行；若坚持原方案，我照删——但请接受关闭手感回退。
