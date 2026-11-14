import 'package:flutter/widgets.dart';

/// The icon set, as a token.
///
/// Two reasons this exists instead of using `LucideIcons` directly:
///
/// 1. **Named by meaning, not by picture.** A row that means "this opens a
///    document" asks for `AppIcons.docText`; swapping the underlying set is
///    then one file, not 121 call sites.
/// 2. **Stroke, not fill.** Lucide is a 2pt-stroke 24-grid set, which is the
///    weight the geometry spec asks for. The previous set carried filled
///    variants; the fill cue is replaced by colour plus the dock's indicator,
///    recorded in `developDoc/design-fidelity-overrides.md`.
///
/// Sizes come from `AppSpace`: 16 for a row's leading glyph, 20 for a
/// trailing chevron, 24 for a dock tab. Never a literal.
abstract final class AppIcons {
  /// 搜索
  static const IconData search = IconData(0xf4ad, fontFamily: 'Lucide');

  /// 书
  static const IconData book = IconData(0xf1af, fontFamily: 'Lucide');

  /// 文档
  static const IconData docText = IconData(0xf2d3, fontFamily: 'Lucide');

  /// 新增
  static const IconData add = IconData(0xf45e, fontFamily: 'Lucide');

  /// 已加书签
  static const IconData bookmarkFill = IconData(0xf1b4, fontFamily: 'Lucide');

  /// 勾选
  static const IconData checkmarkAlt = IconData(0xf1ee, fontFamily: 'Lucide');

  /// 展开
  static const IconData chevronDown = IconData(0xf1f5, fontFamily: 'Lucide');

  /// 右尖角。三个名字同一字形：`chevronRight` 是规范叫法，另两个是已有
  /// 调用点在用的旧名，收敛时只改这一处。
  static const IconData chevronRight = IconData(0xf1fb, fontFamily: 'Lucide');

  static const IconData chevronForward = chevronRight;

  static const IconData rightChevron = chevronRight;

  /// 返回
  static const IconData chevronBack = IconData(0xf1f9, fontFamily: 'Lucide');

  /// 向上
  static const IconData chevronUp = IconData(0xf1fd, fontFamily: 'Lucide');

  /// 设置
  static const IconData gear = IconData(0xf4b9, fontFamily: 'Lucide');

  /// 设置（备选）
  static const IconData gearAlt = IconData(0xf4ba, fontFamily: 'Lucide');

  /// 设置（选中）
  static const IconData gearSolid = IconData(0xf4b9, fontFamily: 'Lucide');

  /// 图片
  static const IconData photo = IconData(0xf365, fontFamily: 'Lucide');

  /// 图片（相框）
  static const IconData photoOnRectangle = IconData(0xf365, fontFamily: 'Lucide');

  /// 电量空
  static const IconData battery0 = IconData(0xf18e, fontFamily: 'Lucide');

  /// 电量低
  static const IconData battery25Percent = IconData(0xf191, fontFamily: 'Lucide');

  /// 电量中
  static const IconData battery75Percent = IconData(0xf192, fontFamily: 'Lucide');

  /// 电量满
  static const IconData batteryFull = IconData(0xf190, fontFamily: 'Lucide');

  /// 书签
  static const IconData bookmark = IconData(0xf1bd, fontFamily: 'Lucide');

  /// 统计
  static const IconData chartBar = IconData(0xf187, fontFamily: 'Lucide');

  /// 成功
  static const IconData checkmarkCircleFill = IconData(0xf1f1, fontFamily: 'Lucide');

  /// 已选中
  static const IconData checkMarkCircledSolid = IconData(0xf1f1, fontFamily: 'Lucide');

  /// 已校验
  static const IconData checkmarkSeal = IconData(0xf179, fontFamily: 'Lucide');

  /// 未选中
  static const IconData circle = IconData(0xf20b, fontFamily: 'Lucide');

  /// 清除
  static const IconData clear = IconData(0xf59e, fontFamily: 'Lucide');

  /// 关闭
  static const IconData xmark = IconData(0xf59e, fontFamily: 'Lucide');

  /// 失败
  static const IconData xmarkCircleFill = IconData(0xf59f, fontFamily: 'Lucide');

  /// 删除
  static const IconData delete = IconData(0xf546, fontFamily: 'Lucide');

  /// 移除
  static const IconData trash = IconData(0xf546, fontFamily: 'Lucide');

  /// 安全
  static const IconData lockShield = IconData(0xf3ae, fontFamily: 'Lucide');

  /// 深色主题
  static const IconData moon = IconData(0xf3eb, fontFamily: 'Lucide');

  /// 浅色主题
  static const IconData sunMax = IconData(0xf50f, fontFamily: 'Lucide');

  /// 低亮
  static const IconData sunMin = IconData(0xf510, fontFamily: 'Lucide');

  /// 编辑
  static const IconData pencil = IconData(0xf43d, fontFamily: 'Lucide');

  /// 添加
  static const IconData plusCircle = IconData(0xf45f, fontFamily: 'Lucide');

  /// 音量
  static const IconData speaker1 = IconData(0xf584, fontFamily: 'Lucide');

  /// 音量（大）
  static const IconData speaker2 = IconData(0xf585, fontFamily: 'Lucide');

  /// 字体
  static const IconData textformat = IconData(0xf554, fontFamily: 'Lucide');

  /// 界面字体
  static const IconData textformatSize = IconData(0xf3df, fontFamily: 'Lucide');

  /// 导入
  static const IconData trayArrowDown = IconData(0xf36a, fontFamily: 'Lucide');

  /// 归档
  static const IconData archivebox = IconData(0xf130, fontFamily: 'Lucide');

  /// 刷新
  static const IconData arrow2Circlepath = IconData(0xf480, fontFamily: 'Lucide');

  /// 刷新
  static const IconData refresh = IconData(0xf480, fontFamily: 'Lucide');

  /// 下载
  static const IconData arrowDownCircle = IconData(0xf140, fontFamily: 'Lucide');

  /// 导入文件
  static const IconData arrowDownDoc = IconData(0xf2bc, fontFamily: 'Lucide');

  /// 导出文件
  static const IconData arrowUpDoc = IconData(0xf2c6, fontFamily: 'Lucide');

  /// 上一段
  static const IconData backwardEnd = IconData(0xf4d6, fontFamily: 'Lucide');

  /// 下一段
  static const IconData forwardEnd = IconData(0xf4d7, fontFamily: 'Lucide');

  /// 书（选中）
  static const IconData bookSolid = IconData(0xf1af, fontFamily: 'Lucide');

  /// 笔记
  static const IconData chatBubbleText = IconData(0xf3ce, fontFamily: 'Lucide');

  /// 时间
  static const IconData clock = IconData(0xf221, fontFamily: 'Lucide');

  /// 云端
  static const IconData cloud = IconData(0xf22e, fontFamily: 'Lucide');

  /// 云端下载
  static const IconData cloudDownload = IconData(0xf288, fontFamily: 'Lucide');

  /// 云端上传
  static const IconData cloudUpload = IconData(0xf562, fontFamily: 'Lucide');

  /// 文件
  static const IconData doc = IconData(0xf2a5, fontFamily: 'Lucide');

  /// 更多
  static const IconData ellipsis = IconData(0xf3ed, fontFamily: 'Lucide');

  /// 警告
  static const IconData exclamationmarkCircleFill = IconData(0xf10b, fontFamily: 'Lucide');

  /// 显示
  static const IconData eye = IconData(0xf29c, fontFamily: 'Lucide');

  /// 隐藏
  static const IconData eyeSlash = IconData(0xf29d, fontFamily: 'Lucide');

  /// 文件夹
  static const IconData folder = IconData(0xf2f8, fontFamily: 'Lucide');

  /// 信息
  static const IconData infoCircle = IconData(0xf36e, fontFamily: 'Lucide');

  /// 收起键盘
  static const IconData keyboardChevronCompactDown = IconData(0xf379, fontFamily: 'Lucide');

  /// 链接
  static const IconData link = IconData(0xf397, fontFamily: 'Lucide');

  /// 列表
  static const IconData listBullet = IconData(0xf39b, fontFamily: 'Lucide');

  /// 定位
  static const IconData locationFill = IconData(0xf3c0, fontFamily: 'Lucide');

  /// 暂停
  static const IconData pause = IconData(0xf438, fontFamily: 'Lucide');

  /// 播放
  static const IconData play = IconData(0xf457, fontFamily: 'Lucide');

  /// 帮助
  static const IconData questionCircle = IconData(0xf359, fontFamily: 'Lucide');

  /// 调节
  static const IconData sliderHorizontal3 = IconData(0xf4db, fontFamily: 'Lucide');

  /// 导入
  static const IconData squareArrowDown = IconData(0xf287, fontFamily: 'Lucide');

  /// 书库
  static const IconData squareStack3dUp = IconData(0xf387, fontFamily: 'Lucide');

  /// 书库（选中）
  static const IconData squareStack3dUpFill = IconData(0xf387, fontFamily: 'Lucide');

  /// 新建文稿
  static const IconData textBadgePlus = IconData(0xf2c8, fontFamily: 'Lucide');

  /// 计时
  static const IconData timer = IconData(0xf53a, fontFamily: 'Lucide');
}
