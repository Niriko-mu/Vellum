# 设计系统护栏：这些数字只允许下降，不允许上升。
#
# 用法（仓库根目录）：
#   pwsh -File tool/design_lint.ps1
#
# 每一行是「规则 / 当前基线」。改完一批 UI 后重跑，把下降后的数字写回基线。
$root = Join-Path $PSScriptRoot '..\lib'
$rules = @(
  @{ Name = 'widget 内颜色字面量'; Pattern = 'Color\(0x[0-9a-fA-F]{8}\)'; Baseline = 14; Files = @(
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
  @{ Name = '字体字号字面量'; Pattern = 'fontSize: *[0-9]+'; Baseline = 165 }
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
  @{ Name = 'CupertinoColors'; Pattern = 'CupertinoColors\.'; Baseline = 24 }
  @{ Name = '下限以下字号'; Pattern = 'fontSize: *(10|11|12)\b'; Baseline = 0 }
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

if ($failed) {
  Write-Output ''
  Write-Output '设计系统护栏：有指标超过基线。新增 UI 请使用 lib/widgets/ui 下的基元与 token。'
  exit 1
}
Write-Output ''
Write-Output '设计系统护栏：全部通过。'