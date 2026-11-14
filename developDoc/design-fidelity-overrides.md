# 设计保真度覆盖表（F1）

> 对应规范：`apple-like-skill/references/geometry.md`、`roles.md`
> 保真度：**F1** —— 保留 VELLUM 的暖纸底与 terracotta 品牌色，几何 / 图标 / 动效对齐。
> 规则：任何偏离都要在这里占一行，写明**是什么 / 为什么 / 何时复核**。
> 与规范再次分叉时，**先改本表再改代码** —— 顺序反了才会漂移。

---

## 覆盖条目

| # | 偏离项 | Cherry 标准 | VELLUM 取值 | 理由 |
|---|---|---|---|---|
| 1 | 页面底 | `#F5F5F5` 中性灰 | `#F5F3EF` 暖纸 / `#0F0E0D` | 产品气质（"安静的书房"）。已校验：`foreground` 15.5:1、`mutedForeground` 6.3:1 |
| 2 | `primary` | 绿 `#107D32` / `#00CA50` | terracotta `#8F4A2E` / `#E39B76` | 品牌资产。作为**文字色** 5.95:1 / 7.69:1，均过 4.5 线 |
| 3 | `controlActive` | 固定绿 `#24B242`（两主题同值） | `= primary`（随主题） | 不引入第二个强调色。开关"开"另有**非颜色线索**：轨道由 `borderSelected` 变满色，拇指从左侧移到右侧 |
| 4 | 实心按钮填充 | `foreground`（黑 / 白） | `primary` | 主操作是品牌动作，不是"最黑的东西"。一屏只允许一个 `filled` |
| 5 | 底部导航 | 标准 tab bar（高 49 + inset） | **浮空 dock**：高 64、圆角 24（8×3） | 产品指定。磨砂仅限胶囊区域（`BackdropFilter` sigma 24），实测滚动 239 帧 0 丢帧 |
| 6 | 关闭曲线 | 3 条曲线（无 dismiss） | 保留 `dismissCurve` + `dismiss` 180ms | `settle` 是减速曲线，**反演后是缓入**——用它做退场正好是要避免的"界面犹豫了一下"。进/出分流是有意的 |
| 7 | 图标"实心/描边"两态 | 选中态用实心字形 | **只有描边一态**（Lucide 无实心字形） | Lucide 是纯描边集，与规范要的 2px 描边一致。选中态改由**颜色 + dock 滑块**承担：dock 有滑动指示器，开关有拇指位移，书签有"已加书签"语义标签。代价是少了非颜色的形状线索，故 dock 的选中项另加字重差 |
| 8 | 图标字体来源 | 依赖 `lucide_icons` pub 包 | **自带 `assets/fonts/Lucide.ttf`** | 0.257.0（最新）里 `LucideIconData extends IconData`，而本 SDK 已把 `IconData` 标为 `final`，该包**无法编译**。字体与 ISC 许可一并入库，码点集中在 `lib/theme/app_icons.dart` |

---

## 不受覆盖影响的（必须真通过）

以下条目**不允许**偏离，conformance test 逐条断言：

- 行高：最小 40，单行自然 48（16/24 + 12 + 12）
- 表头：高 40，距块 4，侧缩进 12
- 分隔线：有前导图标 左 44 / 右 12；无前导 12 / 12；按压时本行与其上一行一起隐藏
- 前导图标：16，`foreground`
- 尾随值：16/24，`foreground`，右对齐，最大 62% 宽
- chevron：20，`mutedForeground`，左侧间隔 8
- 圆角阶梯：8 的倍数（4.8 / 6.4 / 8 / 11.2 / 14.4 / 17.6 / 20.8）
- 图标：只经 `AppIcons` 取字形，`CupertinoIcons` 零引用；字号 16（行内）/ 20（chevron）/ 24（dock）
- 字号阶梯：13 级严格递增，行高 ≥ 字号
- 动效：`settle` / `overshoot` 为 `Cubic`，`fast` 200 / `base` 250 / `slow` 350
- 两套主题声明的角色集合完全一致

---

## 复核触发条件

出现下列任一情况时，逐条重读本表：

1. 规范里的 `geometry.md` / `roles.md` 更新；
2. 新增一个 `AppColors` 角色（可能意味着第 3 条的边界要重画）；
3. 有人问"为什么我们的开关不是绿的"——答案必须能在第 3 条找到，而不是重新讨论。
