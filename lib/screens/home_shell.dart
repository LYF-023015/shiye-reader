import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/book.dart';
import '../services/reading_store.dart';
import '../services/document_service.dart';
import '../services/update_service.dart';
import 'history_screen.dart';
import 'library_screen.dart';
import 'annotations_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.readingStore});

  final ReadingStore readingStore;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  ReadingStore get _readingStore => widget.readingStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    await _readingStore.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _readingStore.flush();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _readingStore.flush();
    }
  }

  void _addImportedBook(Book book) {
    _readingStore.addImportedBook(book);
  }

  Future<void> _showDataActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('导出完整备份'),
              subtitle: const Text('ZIP 包含校验、书籍资源、进度、书签、批注和设置'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _exportBackup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.system_update_alt_rounded),
              title: const Text('检查更新'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _checkForUpdates();
              },
            ),
            ListTile(
              leading: const Icon(Icons.feedback_outlined),
              title: const Text('问题反馈'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _openFeedback();
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore_rounded),
              title: const Text('恢复备份'),
              subtitle: const Text('恢复操作会替换当前书架数据'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _restoreBackup();
              },
            ),
            ListTile(
              leading: Icon(
                _readingStore.readerPreferences.appThemeMode == 'dark'
                    ? Icons.dark_mode_rounded
                    : _readingStore.readerPreferences.appThemeMode == 'light'
                    ? Icons.light_mode_rounded
                    : Icons.brightness_auto_rounded,
              ),
              title: const Text('外观主题'),
              subtitle: Text(
                _readingStore.readerPreferences.appThemeMode == 'dark'
                    ? '深色模式'
                    : _readingStore.readerPreferences.appThemeMode == 'light'
                    ? '浅色模式'
                    : '跟随系统',
              ),
              onTap: () => _showThemePicker(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  void _showThemePicker(BuildContext parentContext) {
    final current = _readingStore.readerPreferences.appThemeMode;
    Navigator.pop(parentContext);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 8, 22, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '外观主题',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final option in const [
              ('system', '跟随系统', Icons.brightness_auto_rounded),
              ('light', '浅色模式', Icons.light_mode_rounded),
              ('dark', '深色模式', Icons.dark_mode_rounded),
            ])
              ListTile(
                leading: Icon(option.$3),
                title: Text(option.$2),
                trailing: current == option.$1
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () {
                  final prefs = _readingStore.readerPreferences;
                  _readingStore.updateReaderPreferences(
                    prefs.copyWith(appThemeMode: option.$1),
                  );
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openFeedback() async {
    try {
      final opened = await launchUrl(
        Uri.parse('https://github.com/LYF-023015/shiye-reader/issues/new'),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('No browser available');
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开反馈页面')));
      }
    }
  }

  Future<void> _checkForUpdates() async {
    try {
      final update = await UpdateService.check();
      if (!mounted) return;
      if (!update.updateAvailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前已是最新版本 ${update.currentVersion}')),
        );
        return;
      }
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('发现新版本'),
          content: Text(
            '当前 ${update.currentVersion}，最新 ${update.latestVersion}。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('前往下载'),
            ),
          ],
        ),
      );
      if (open == true) {
        final opened = await launchUrl(
          update.releaseUrl,
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('无法打开下载页面')));
        }
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('暂时无法检查更新')));
      }
    }
  }

  Future<void> _exportBackup() async {
    try {
      final saved = await DocumentService.saveBytes(
        name:
            'Shiye-backup-${DateTime.now().toIso8601String().substring(0, 10)}.zip',
        content: await _readingStore.createBackupArchive(),
        mimeType: 'application/zip',
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('完整备份已导出')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份导出失败')));
      }
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final content = await DocumentService.openBackupBytes();
      if (content == null || !mounted) return;
      final preview = await _readingStore.inspectBackupBytes(content);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复完整备份'),
          content: Text(
            '备份包含 ${preview.bookCount} 本书、${preview.annotationCount} 条批注。'
            '${preview.createdAt == null ? '' : '\n创建时间：${preview.createdAt!.toLocal()}'}'
            '${preview.isLegacyJson ? '\n这是旧版 JSON 备份。' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'merge'),
              child: const Text('合并恢复'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'replace'),
              child: const Text('整体替换'),
            ),
          ],
        ),
      );
      if (action == null) return;
      await _readingStore.restoreBackupBytes(content, merge: action == 'merge');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份恢复完成')));
      }
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('备份文件无法读取')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _readingStore,
      builder: (context, _) {
        final books = _readingStore.importedBooks
            .map(_readingStore.hydrate)
            .toList();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Column(
              children: [
                if (_readingStore.storageError != null)
                  MaterialBanner(
                    content: Text(_readingStore.storageError!),
                    actions: [
                      TextButton(
                        onPressed: _initialize,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      IndexedStack(
                        index: _currentIndex,
                        children: [
                          LibraryScreen(
                            books: books,
                            readingStore: _readingStore,
                            onBookImported: _addImportedBook,
                          ),
                          HistoryScreen(
                            books: books,
                            readingStore: _readingStore,
                            onOpenAnnotations: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => AnnotationsScreen(
                                  readingStore: _readingStore,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: Container(
                height: 58,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF14161A)
                      : Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    _NavigationItem(
                      icon: Icons.auto_stories_rounded,
                      label: '书架',
                      selected: _currentIndex == 0,
                      onTap: () => setState(() => _currentIndex = 0),
                    ),
                    _NavigationItem(
                      icon: Icons.history_rounded,
                      label: '阅读记录',
                      selected: _currentIndex == 1,
                      onTap: () => setState(() => _currentIndex = 1),
                    ),
                    IconButton(
                      tooltip: '数据与帮助',
                      onPressed: _showDataActions,
                      color: Theme.of(context).colorScheme.onSurface,
                      icon: const Icon(Icons.more_horiz_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    final unselectedColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: .5);
    final color = selected ? selectedColor : unselectedColor;
    return Expanded(
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          key: ValueKey('nav-$label'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(25),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
