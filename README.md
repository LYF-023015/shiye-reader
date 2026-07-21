# 拾页 Shiye

> 一款本地优先的 Flutter 阅读器，记录每一次翻页与停留。

拾页提供沉浸式阅读、立体书架和本地书籍导入体验。项目目前以 Android 为主要目标平台，同时保留 Flutter 多端工程结构。

## 界面预览

![书架](qa/qa-library-final.png)

![书籍展厅](qa/qa-showroom-final.png)

![阅读记录](qa/qa-history-dark.png)

## 功能

- 书架：CoverFlow 浏览、搜索、阅读进度与封面替换。
- 书籍展厅：可交互的 3D 书籍模型和书籍详情。
- 本地导入：支持 TXT、EPUB 和 PDF；TXT 包含 UTF-8、UTF-16、GBK 解码，EPUB 可提取元数据、正文和内嵌封面。
- 阅读器：目录、进度、书签、文本批注及多种排版和护眼设置。
- 阅读记录：按日期与阅读时长生成统计与热力图。
- 本地存储：书架、阅读进度、书签、批注和设置均以 JSON 持久化。

## 技术栈

- Flutter / Dart
- Material UI
- `archive`、`charset`、`xml`：本地书籍解析
- `interactive_3d`：书籍 3D 展示
- Android Kotlin `MethodChannel`：文件选择与 PDF 封面渲染

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

- PDF 目前只生成封面，尚未解析正文。
- 原生文件选择目前实现于 Android；其他平台待补齐。
- 数据暂存于单一 JSON 文件，后续会迁移到更可靠的本地数据库。

## 路线图

- [ ] 使用 SQLite 或 Isar 改善书库持久化与大文件处理。
- [ ] 支持完整 PDF 阅读与更广泛的 EPUB 排版。
- [ ] 增加正式分页、手势翻页和深色主题。
- [ ] 补齐 iOS、桌面及 Web 的文件导入能力。
