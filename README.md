# Vellum

English_version:[README_EN.md](README_EN.md)

一个以阅读为核心的本地电子书应用：安静的「数字书房」，Cupertino-first，数据只存在本机。

---

## 用户指南

### 书库

- 导入 **EPUB / MOBI / TXT**
- 书架 **三列网格**，支持 **搜索**（书名 / 封面文字 / 格式）
- **自定义文件夹**：新建、重命名、删除；长按书籍可移入/移出
- **长按编辑封面**：上传图片，或用自定义文字生成封面
- 索引与正文分文件存储，启动只读轻量索引

### 阅读

- **上下滚动** / **左右翻页** 两种模式
- 翻页效果：覆盖 / 平移 / 无动画；点击左右翻页、中间唤出控件
- 进度条可拖动；目录、书签、**划线笔记** 快速跳转
- 目录面板内 **全文搜索**：输入两个字即扫描全书正文，结果**按章节分组**，每条显示命中片段
  （关键词高亮）、上一行上下文、段落号与所在页码，同段多次命中会标注次数；顶栏显示
  「N 段 · M 处」并可用上下按钮在结果间逐条跳转，点按某条直达正文，**并在该段落里高亮搜索词**
  （**翻页或滚动离开即取消**，不残留在无关文字上）。输入停顿后才扫描，超长书籍（实测 60 万段）
  输入与扫描都不卡顿
- 字号、行距、字重、**亮度**、**护眼**、背景色、系统/导入 TTF 字体
- 富文本：粗体、斜体、下划线、标题层级、引用、居中
- 选中文字：**划线**、复制、Bing 查询、DeepL 翻译、笔记（划线/笔记都可在正文中以高亮显示）
- 页脚显示 **当前章节 + 本章进度 + 剩余阅读时间**、全书进度与电量
- **屏幕常亮**、**音量键翻页**（可在阅读设置里开关）
- 顶栏一键加/取消书签；下拉阅读页面也可加书签
- 阅读进度与书签自动保存
- 目录阅读进度按章节独立保存：没有历史断点的章节从章节首页进入，跳出后返回可恢复该章离开位置

### 写作

- 本地文稿列表：新建、导入（`.md` / `.txt` / `.markdown`）、长按删除
- **输入自动保存**，无需手动点保存；底部实时统计 **字数 / 词数**
- 导出到所选位置（Markdown 或纯文本）
- **Markdown 本地预览**：编辑区一键切到渲染视图（标题、粗体、斜体、列表、引用、链接文字），
  完全在本机用阅读页的排版管线渲染，不联网、不加载远程图片
- **排版设置全局生效**（所有文稿共用）：字体（含导入 TTF，与阅读页同一选择器）、字号、字重、小说模式
- **小说模式**（纯文本稿）：开启后自动「段首两格 + 段间空行」，回车即开新段；Markdown 稿下自动失效

### 工具与设置

- **MOBI / EPUB 转 TXT**：独立二级页，可选择保存位置
- 深浅色主题
- 字体管理（导入 / 启用 / 删除）
- **阅读笔记导入 / 导出**：导出为 JSON；导入支持 Vellum 备份的 JSON，以及
  `# 书名` + `> 划线` + 批注行的 Markdown / 纯文本。自动按「导出记录中的书籍 ID → 书名（含
  《》标点折叠、唯一包含匹配）」关联书籍；**无法确定时不会乱猜**——可在导入前手动选书，或先存为
  「未关联笔记」，之后在设置里逐条关联
- **应用内更新**：设置页显示**当前版本号**；进入 APP 自动检测（可关闭），发现新版本后按机型架构
  选择安装包，应用内下载并调起系统安装器；更新仓库可自定义（`owner/repo` 或完整 URL）
- 存储占用与清理
- **数据备份**：本地 ZIP（可选 AES-256-GCM 加密）与对象存储云备份，兼容腾讯云 COS、阿里云 OSS；访问密钥只保存在系统安全存储
- 阅读页显示本次与今日阅读计时，统计页提供目标、近 7 日趋势和按书籍明细
- **Android 继续阅读小组件**：从桌面一键打开 VELLUM 并回到首页的最近阅读卡片

### 暂不支持

- 预览里的代码块按普通段落渲染（不保留缩进与等宽字体）
- DRM 加密电子书
- KF8 / AZW3 专有排版（按经典 MOBI7 解析）

---

## 开发者指南

### 目录结构

```
lib/
  main.dart                 入口
  app.dart                  VellumApp + LibraryShell
  vellum.dart               公共导出
  pages/                    首页、书库、设置、转 TXT、封面编辑、写作
  reader/                   阅读页、分页、段落、手势、控制栏
  services/                 MOBI/EPUB/HTML 解析、书库存储、导入、更新
  theme/ util/ widgets/     主题与工具
```

### 环境

- Flutter stable（Dart SDK `^3.12.2`）
- Android / Windows 等 Flutter 支持的平台

### 依赖（国内可加速）

```bat
tool\pub_get_mirror.bat
```

脚本只设置当前会话的 `PUB_HOSTED_URL` 与 `FLUTTER_STORAGE_BASE_URL`，不改全局环境。

Android Gradle 依赖已使用阿里云 / 腾讯云镜像配置。

### 常用命令

```bat
flutter pub get
flutter analyze
flutter test
flutter run
```

### 构建

```bat
flutter build apk --release
flutter build apk --release --split-per-abi
:: 或
flutter build appbundle --release
```

说明：当前 release 仍使用 debug 签名，便于自测；上架前请配置正式 keystore。

**但 debug 签名也不是随便哪个都行。** Android 的 debug key 是构建机上「第一次构建时现场生成」
的，所以 GitHub 的每个 runner 拿到的都是**不同**的密钥。用新密钥签出的包无法覆盖安装到用旧密钥
签出的包上，读者更新时只会看到「应用未安装」——为了让从 GitHub 下载的人能持续更新，必须把同一份
debug keystore 固定下来：

1. 取本机（也就是历史 release 用的那份）密钥，转成一行 base64：
   ```bat
   certutil -encodehex -f "%USERPROFILE%\.android\debug.keystore" keystore.b64 0x40000001
   :: 或 Git Bash： base64 -w0 ~/.android/debug.keystore > keystore.b64
   ```
2. 仓库 **Settings → Secrets and variables → Actions → New repository secret**，名字填
   `VELLUM_DEBUG_KEYSTORE_BASE64`，值粘贴上一步的内容。
3. 之后每次发版，工作流会先还原这份密钥再构建；日志里的
   `Report the signing certificate` 步骤会打印实际签名证书的 SHA-256，可用来核对。

如果没配这个 secret，工作流仍会出包（不至于卡死手工发版），但会在日志里打一条警告，并且
**已有安装无法覆盖更新**。

### 更新包命名

应用内更新按机型架构区分安装包，文件名必须是 `Vellum-V<版本>-<abi>.apk`：

| 文件名 | 适用 |
|--------|------|
| `Vellum-V1.0.8-arm64-v8a.apk` | 绝大多数手机（推荐） |
| `Vellum-V1.0.8-armeabi-v7a.apk` | 较老的 32 位机型 |
| `Vellum-V1.0.8-x86_64.apk` | x86 平板 / 模拟器 |
| `Vellum-V1.0.8-universal.apk` | 无法识别架构时的回退包 |

应用会读取设备的 `SUPPORTED_ABIS`，把匹配的包排到最前并标「推荐」；装错架构系统会提示「应用未安装」。

版本号以 `pubspec.yaml` 的 `version` 为准，与设置页「当前版本」一致。`version` 形如
`1.1.0+16`：前面的 `1.1.0` 是 versionName，「当前版本」与更新比较都取它；后面的 `16` 是
versionCode，**必须随每次发版递增**，否则 Android 会按降级安装拒绝（用户看到「应用未安装」）。
CI 直接读这里的 `+N`，不再用 Actions 的 run number（它按仓库计数，和版本号没有关系）。

应用内更新的默认仓库是 `github.com/niriko-mu/Vellum`，也就是本仓库 Release 所在位置。可在
设置 → 更新仓库 改成 `owner/repo`、`github.com/owner/repo` 或 `gitee.com/owner/repo`。

### CI / 发布

| 工作流 | 触发 | 作用 |
|--------|------|------|
| `.github/workflows/build.yml` | 手动 | 测试 + 构建 APK/AAB |
| `.github/workflows/release.yml` | 手动或推送 `v*` tag | 打 tag、按 ABI 构建并发布 GitHub Release |

Release 会产出 3 个按 ABI 拆分的 APK（`--split-per-abi`）加 1 个 universal 包，并统一重命名为上表的名字。

手动发版：**Actions → Release → Run workflow**，可指定 tag（默认取 `pubspec.yaml` 的 `version`）。

推送 tag：

```bat
git tag v1.0.8
git push origin v1.0.8
```

## 许可

见 [LICENSE](LICENSE)。
