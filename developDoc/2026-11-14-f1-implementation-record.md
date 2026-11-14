# F1 设计改造落地记录

> 日期：2026-11-14
> 方案：`2026-11-14-cherry-f1-implementation-plan.md`
> 偏离项：`design-fidelity-overrides.md`（9 条）
> 状态：**代码与闸门已完成**；真机视觉复核**未做**（当时无设备连接，见文末）

---

## 1. 做了什么

方案里的 8 步按提交顺序执行，每一步独立可回滚：

| # | 提交 | 内容 |
|---|---|---|
| 1 | `fae08eb` | 四个语义角色（`controlActive` / `link` / `destructiveForeground` / `secondaryForeground`）；dock 圆角 26.8 → 24；删除 18 个 `@Deprecated` 别名；手势窗口拆到 `AppGestureWindow` |
| 2 | `68278b4` | 几何对齐 `geometry.md`：行高下限 40、表头 40/4、分隔线 44-12、前导图标 16 foreground、值 foreground、chevron 20 muted；新增 `AppSelectRow` / `AppSwitchRow`；分隔线按压隐藏；conformance 闸门 |
| 3 | `0fe8361` | 设置页：内容区大标题、6 组并 3 组且前两组无 header、破坏性动作单独成组带 footer；`AppPage` 收归顶部间距 |
| 4 | `8816eea` | `CupertinoListTile` 14 → 0（6 个文件整页迁移） |
| 5 | `8b3abd3` `8563e68` | `CupertinoButton` 84 → 0；新增 `AppTextButton` |
| 6 | （图标提交） | `CupertinoIcons` 121 → 0；新增 `AppIcons` 令牌 + 自带 Lucide 字体 |
| 7 | `dc17b46` `d9174af` | 新增 `AppDialog` / `AppToast`；19 处 iOS 弹窗 → 0 |
| 8 | `b1fd4f1` `ec8a53e` `351f9c1` | 字号全部落到 13 级阶梯；`CupertinoColors` 17 → 1；conformance 扩到 19 条 |

## 2. 护栏现状（`tool/design_lint.ps1`，13 条 + 1 条阶梯检查）

| 规则 | 改造前 | 现在 | 性质 |
|---|---|---|---|
| widget 内颜色字面量 | 61 | 13 | 白名单 |
| 字体字号字面量 | 214 | 109 | 只能降 |
| **阶梯外字号** | — | **0** | **硬失败，无基线** |
| 圆角字面量 | 69 | 0 | 零基线 |
| 过重字重 | 12 | 5 | 白名单 |
| 阴影（token 外） | 10 | 6 | 白名单 |
| 缓入/回弹曲线 | 14 | 0 | 零基线 |
| `CupertinoButton` | 84 | 0 | 零基线 |
| `CupertinoListTile` | 14 | 0 | 零基线 |
| `CupertinoIcons` | 121 | 0 | 零基线 |
| `CupertinoColors` | 45 | 1 | 白名单 |
| iOS 弹窗 | 19 | 0 | 白名单 |
| 下限以下字号 | 0 | 0 | 零基线 |

一条规则值得单独说：**阶梯外字号是硬失败，没有基线可赖**。
「有多少个字面量」拦不住漂移——把 13 写成 15 时字面量个数不变。
「这个尺寸在不在阶梯上」才拦得住。

## 3. 闸门

- `flutter analyze`：**0 issue**（连改造前就存在的 `app.dart` `unnecessary_null_comparison` 也消掉了）
- `flutter test`：**393 项通过**
- `test/design_conformance_test.dart`：**19 条**，其中 2 条是 F1 覆盖项（`controlActive == primary`、实心按钮 `== primary`），`reason` 里写明覆盖表编号
- `tool/design_lint.ps1`：全绿
- `flutter build apk --debug`：成功，`assets/fonts/Lucide.ttf` 与 FontManifest 的 `Lucide` 条目都在包里

## 4. 计划外的两处判断

1. **Lucide 字体改为自带**。方案写的是「加依赖 `lucide_icons 0.257.0`（已验证可解析）」，
   但解析成功不代表能编译：该包 `LucideIconData extends IconData`，而本 SDK 已把 `IconData` 标为 `final`。
   `flutter analyze lib` 不报，只有在真正编译时炸（4 个测试直接 load 失败）。
   改为把 `.ttf` 与 ISC 许可入库、码点写进 `app_icons.dart`。详见覆盖表第 8 条。
2. **子页顶栏保留 `CupertinoNavigationBar`**，没有按方案 §4.2 换 `AppInlineHeader`。
   自绘顶栏要自己重做边缘返回手势、返回按钮 hit slop、hero 与大标题折叠——
   而这正是你要求「保留所有 Cupertino* 组件与边缘返回手势」的地方。详见覆盖表第 9 条。

## 5. 没做的

- **真机视觉复核**。方案 §10 要求「亮/暗 × textScale 1.0/2.0 × 320pt/720pt 四组真机截图」，
  但执行到这一步时 `adb devices` 为空（设备未连接）。代码与自动闸门都过了，
  **视觉判断仍然缺一次真机确认**：字号从 15/17/19/22/23/28 落到阶梯后，
  行高与换行会有 1pt 级的位移，测试抓不到「看起来挤了」。
  接上设备后应补：滚动书架、设置页、阅读器三套面板、写作编辑器。
- **6 处自绘 sheet 并入 `AppSheet`**（方案 §4.2 表格最后一行）。
  它们已经统一用 `AppRadius.sheetTop` 与同一套颜色，视觉差异很小，
  而迁移涉及键盘 inset 与底部按钮位置，属于「收益小、回归风险实在」的一类，
  留到有空闲真机窗口时再做。
