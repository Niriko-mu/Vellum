# 设计系统护栏：这些数字只允许下降，不允许上升。
#
# 用法（仓库根目录）：
#   pwsh -File tool/design_lint.ps1
#
# 每一行是「规则 / 当前基线」。改完一批 UI 后重跑，把下降后的数字写回基线。
$root = Join-Path $PSScriptRoot '..\lib'
$rules = @(
  @{ Name = 'widget 内颜色字面量'; Pattern = 'Color\(0x[0-9a-fA-F]{8}\)'; Baseline = 13; Files = @(
      'reader\reader_color_picker.dart',
      'reader\reader_controls.dart',
      'reader\reader_directory_panel_rendering.dart',
      'reader\reader_page_state_surface_rendering.dart',
      'reader\reader_paragraph.dart',
      'reader\reader_selection.dart',
      'reader\reader_settings_panel.dart',
      'reader\tts_bar.dart',
      'reader\reader_page_overlay.dart',
      'pages\writing_library_page.dart',
      'widgets\ui\app_controls.dart',
      'widgets\ui\app_pressable.dart',
      'app.dart'
    ) }
  # 「有多少个字面量」拦不住漂移，「有没有阶梯外的字号」才拦得住。
  # 阶梯外的字号由下面的阶梯检查逐条列出（硬失败，无基线）。
  @{ Name = '字体字号字面量'; Pattern = 'fontSize: *[0-9]+'; Baseline = 109 }
  @{ Name = '圆角字面量'; Pattern = 'BorderRadius\.circular\(\s*[0-9]'; Baseline = 0 }
  @{ Name = '过重字重'; Pattern = 'FontWeight\.(w700|w800|w900|bold)'; Baseline = 5 }
  @{ Name = '阴影（token 之外）'; Pattern = 'BoxShadow\('; Baseline = 6; Files = @(
      'reader\reader_color_picker.dart',
      'reader\reader_controls.dart',
      'reader\reader_page_overlay.dart',
      'reader\reader_paragraph.dart',
      'reader\reader_page_state_surface_rendering.dart',
      'reader\tts_bar.dart'
    ) }
  @{ Name = '缓入/回弹曲线'; Pattern = 'Curves\.(ease|bounce|elastic)'; Baseline = 0; Files = @() }
  @{ Name = 'CupertinoSwitch'; Pattern = 'CupertinoSwitch'; Baseline = 1 }
  @{ Name = 'CupertinoColors'; Pattern = 'CupertinoColors\.'; Baseline = 1; Files = @(
      'theme\vellum_theme.dart'
    ) }
  @{ Name = '下限以下字号'; Pattern = 'fontSize: *(10|11|12)\b'; Baseline = 0 }
  # 下面两条没有余量：基元之外不允许再出现第三种按钮或第三种列表行。
  @{ Name = 'CupertinoButton'; Pattern = 'CupertinoButton'; Baseline = 0 }
  @{ Name = 'CupertinoListTile'; Pattern = 'CupertinoListTile'; Baseline = 0 }
  # 用户看得见的文字里不许出现未插值的占位符。
  # 反斜杠转义的 \${...} 会原样显示成 "${...}"，格式化串没被翻译就是这个形状。
  @{ Name = '转义掉的插值'; Pattern = '\\\$\{'; Baseline = 0 }
  # 图标只能走 AppIcons：它是唯一的字形来源，换字体是一处改动。
  @{ Name = 'CupertinoIcons'; Pattern = 'CupertinoIcons\.'; Baseline = 0 }
  # 弹窗只能走 AppDialog / AppToast：iOS 弹窗在 Android 上是另一套语言。
  # 白名单里允许 1 处 —— app_dialog.dart 的文档注释解释了为什么不用它。
  @{ Name = 'iOS 弹窗'; Pattern = 'CupertinoAlertDialog|CupertinoDialogAction'; Baseline = 1; Files = @(
      'widgets\ui\app_dialog.dart'
    ) }
)

$failed = $false
foreach ($rule in $rules) {
  $files = if ($rule.ContainsKey('Files') -and $rule.Files -and $rule.Files.Count -eq 0) {
    Get-ChildItem -Recurse -File -Filter *.dart $root |
      Where-Object { $_.FullName -notmatch '\\theme\\' } |
      ForEach-Object { $_.FullName }
  } elseif ($rule.Files) {
    $rule.Files | ForEach-Object { Join-Path $root $_ } | Where-Object { Test-Path $_ }
  } else {
    Get-ChildItem -Recurse -File -Filter *.dart $root | ForEach-Object { $_.FullName }
  }

  $hits = 0
  if ($rule.ContainsKey('Files') -and $rule.Files -and $rule.Files.Count -gt 0) {
    foreach ($file in $files) {
      $hits += (Select-String -Path $file -Pattern $rule.Pattern -AllMatches -ErrorAction SilentlyContinue | Measure-Object).Count
    }
  } else {
    $hits = (Select-String -Path $files -Pattern $rule.Pattern -AllMatches -ErrorAction SilentlyContinue | Measure-Object).Count
  }

  $state = if ($hits -le $rule.Baseline) { 'OK  ' } else { 'FAIL' }
  if ($hits -gt $rule.Baseline) { $failed = $true }
  '{0} {1,-22} 当前 {2,3}  基线 {3,3}' -f $state, $rule.Name, $hits, $rule.Baseline
}

# 阶梯检查：字号必须来自 app_type.dart 的 13 级阶梯。
# 这一条没有基线——出现阶梯外的字号就是发明了一个尺寸。
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ladder = @(13, 14, 16, 18, 20, 24, 32, 40, 48, 60, 72, 96, 128)
$offLadder = @()
foreach ($file in (Get-ChildItem -Recurse -File -Filter *.dart $root)) {
  $hits = Select-String -Path $file.FullName -Pattern 'fontSize: *([0-9]+)' -AllMatches -ErrorAction SilentlyContinue
  foreach ($hit in $hits) {
    foreach ($m in $hit.Matches) {
      $size = [int]$m.Groups[1].Value
      if ($ladder -notcontains $size) {
        $rel = $file.FullName.Substring($repo.Length + 1)
        $offLadder += ('{0}:{1}  fontSize: {2}' -f $rel, $hit.LineNumber, $size)
      }
    }
  }
}
if ($offLadder.Count -gt 0) {
  $failed = $true
  Write-Output ''
  Write-Output '阶梯外的字号（改用 AppText 角色或 AppTypeStep）：'
  $offLadder | ForEach-Object { Write-Output ('  ' + $_) }
}

if ($failed) {
  Write-Output ''
  Write-Output '设计系统护栏：有指标超过基线。新增 UI 请使用 lib/widgets/ui 下的基元与 token。'
  exit 1
}
Write-Output ''
Write-Output '设计系统护栏：全部通过。'