# VELLUM 大书导入卡死排查

## 根因

大书导入的解析本身在 `compute` worker 中执行，但原流程随后把完整的 `ImportedBook` 返回 UI isolate，再通过 `BookLibrary.saveBookContent` 把同一份段落、图片和目录复制进 writer isolate。EPUB/MOBI 大书的正文对象很大，两次 SendPort 拷贝会长时间占用主线程；桌面端的 `FilePicker` 还使用 `withData: true`，会在 worker 启动前先在 UI isolate 读取整文件。

## 修复

- 文件选择改为 `withData: false`，优先使用文件路径；worker 直接读取源文件。
- 解码、内容 ID 计算、TXT 源文件/目录持久化和 EPUB/MOBI 内容 JSON 写入合并到同一个后台 worker。
- worker 只返回 `asIndexShell()`：标题、作者、格式、段落计数、封面和 TXT 目录；正文不再跨 isolate 返回。
- 内容 JSON 的后续读取也改为 worker 读取路径并解析，避免 UI 先取得整份 raw JSON。
- 写入使用临时文件完成后替换，避免半写入内容被书库索引看到。
- 书架索引更新继续只写轻量元数据，不重新编码其他书籍正文。

## 验证

- 新增大 TXT seek 导入测试：确认返回对象不含段落、源文件完整写入、临时文件不残留。
- 新增 EPUB inline 导入测试：确认内容 JSON 写入完整、返回对象只含书架元数据、临时文件不残留。
- `flutter analyze lib` 通过。
- `flutter test` 326 项全部通过。
- Android 模拟器实测导入 30,000 段与 100,000 段 EPUB：两者均进入阅读页，后者显示约 27,000 页并可继续翻页，无 ANR、进程退出或主线程无响应。
- 测试书籍和阅读记录已从模拟器书库删除，原有《哈利·波特》《围城》数据保留；APK、测试 EPUB、UI dump 和构建目录已清理。
- 未执行 Git 操作，也未修改其他项目。

## 兼容性

已有书籍内容 JSON、TXT source/catalog sidecar、书库索引、阅读状态和备份格式保持不变。旧书仍由现有加载路径读取，新导入只改变工作 isolate 的传输方式和写入时机。
