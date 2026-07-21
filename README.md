# 拾页 Shiye

> 一款本地优先的 Flutter 阅读器，记录每一次翻页与停留。

拾页提供沉浸式阅读、立体书架和本地书籍导入体验。当前版本专注 Android 平台。

[下载最新 Android APK](https://github.com/LYF-023015/shiye-reader/releases/latest)

## v1.1.0 · P0 可用性更新

- 阅读数据迁移到 Android 应用私有支持目录，避免临时目录被系统清理。
- 数据写入增加临时文件原子替换、备份恢复、旧版数据迁移和错误提示。
- 精确保存章节及章节内阅读位置，重启后恢复到上次阅读位置附近。
- 导入时增加进度遮罩、文件异常提示和重复书籍处理。
- 重复书籍可选择替换、保留两本或取消。
- 支持删除书籍，并同步清理阅读进度、书签、批注和阅读记录。
- 书架新增最近阅读、最近导入和书名排序。
- 暂时移除不可完整阅读的 PDF 导入入口，当前明确支持 TXT 和无 DRM EPUB。

## 界面预览

![书架](qa/qa-library-final.png)

![书籍展厅](qa/qa-showroom-final.png)

![阅读记录](qa/qa-history-dark.png)

## 功能

- 书架：CoverFlow 浏览、搜索、阅读进度与封面替换。
- 书籍展厅：可交互的 3D 书籍模型和书籍详情。
- 本地导入：支持 TXT 和无 DRM EPUB；TXT 包含 UTF-8、UTF-16、GBK 解码，EPUB 可提取元数据、正文和内嵌封面。
- 阅读器：目录、进度、书签、文本批注及多种排版和护眼设置。
- 阅读记录：按日期与阅读时长生成统计与热力图。
- 本地存储：书架、阅读进度、书签、批注和设置均保存在 Android 应用私有目录，支持备份恢复。

## 技术栈

- Flutter / Dart
- Material UI
- `archive`、`charset`、`xml`：本地书籍解析
- `interactive_3d`：书籍 3D 展示
- Android Kotlin `MethodChannel`：本地文件选择

## 运行

```bash
flutter pub get
flutter run
```

## 项目结构

```text
lib/
├── models/       # Book、Chapter 等领域模型
├── screens/      # 书架、记录、展厅与阅读界面
├── services/     # 导入、持久化、封面调色等服务
├── theme/        # 全局主题
└── widgets/      # 可复用 UI 组件
```

## 当前限制

- 暂不支持 PDF 正文阅读。
- EPUB 当前提取纯文本，不完整保留复杂 CSS、媒体和页面排版。
- 数据已使用可靠文件写入和备份，但大型书库后续仍需迁移到数据库。

## 路线图

- [ ] 使用 SQLite 或 Isar 改善书库持久化与大文件处理。
- [ ] 支持完整 PDF 阅读与更广泛的 EPUB 排版。
- [ ] 增加正式分页、手势翻页和深色主题。
- [ ] 增加本地数据导出和恢复。
