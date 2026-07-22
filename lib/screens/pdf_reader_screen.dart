import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/document_service.dart';
import '../services/reading_store.dart';

class PdfReaderScreen extends StatefulWidget {
  const PdfReaderScreen({
    super.key,
    required this.book,
    required this.readingStore,
  });

  final Book book;
  final ReadingStore readingStore;

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  final DateTime _openedAt = DateTime.now();
  final PdfViewerController _viewerController = PdfViewerController();
  late Uint8List _bytes = widget.book.sourceBytes ?? Uint8List(0);
  bool _restoredPosition = false;
  int _lastSavedPage = -1;

  @override
  void initState() {
    super.initState();
    _viewerController.addListener(_onViewerChanged);
  }

  void _onViewerChanged() {
    final pages = _viewerController.pageCount;
    if (pages <= 0) return;
    if (!_restoredPosition) {
      _restoredPosition = true;
      final savedPage = widget.readingStore
          .stateFor(widget.book)
          .chapterIndex
          .clamp(0, pages - 1);
      _lastSavedPage = savedPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _viewerController.jumpToPage(savedPage);
      });
      return;
    }
    final page = _viewerController.currentPage.clamp(0, pages - 1);
    if (page == _lastSavedPage) return;
    _lastSavedPage = page;
    widget.readingStore.updateProgress(
      widget.book,
      pages <= 1 ? 0 : page / (pages - 1),
      page,
    );
  }

  @override
  void dispose() {
    _viewerController
      ..removeListener(_onViewerChanged)
      ..dispose();
    widget.readingStore.recordSession(
      widget.book,
      DateTime.now().difference(_openedAt),
    );
    super.dispose();
  }

  void _persist(Uint8List bytes, {bool showMessage = false}) {
    _bytes = bytes;
    widget.readingStore.updateImportedBook(
      widget.book.copyWith(sourceBytes: bytes),
    );
    if (showMessage && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF 批注已保存')));
    }
  }

  Future<void> _saveAs(Uint8List bytes) async {
    try {
      final saved = await DocumentService.saveBytes(
        name: '${widget.book.title}-批注.pdf',
        content: bytes,
        mimeType: 'application/pdf',
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF 已导出')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('PDF 导出失败')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes.isEmpty) {
      return const Scaffold(body: Center(child: Text('PDF 文件数据缺失，请重新导入')));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF202226),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202226),
        foregroundColor: Colors.white,
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
      ),
      body: PdfEditorView(
        key: ValueKey('pdf-editor-${widget.book.id}'),
        bytes: _bytes,
        documentId: widget.book.id,
        viewerController: _viewerController,
        onDocumentChanged: _persist,
        onSave: (bytes) => _persist(bytes, showMessage: true),
        onSaveAs: _saveAs,
        backgroundColor: const Color(0xFF202226),
        features: const PdfEditorFeatures(
          pageEditing: false,
          flatten: false,
          colorProcessing: false,
        ),
      ),
    );
  }
}
