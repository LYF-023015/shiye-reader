import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../models/book.dart';
import 'book_cover.dart';

/// The interactive model used only inside the book showroom.
///
/// Keeping this renderer out of the CoverFlow preserves the shelf's raster
/// performance while the showroom retains a real closed 3D book volume.
class NativeBookModel extends StatefulWidget {
  const NativeBookModel({super.key, required this.book});

  final Book book;

  @override
  State<NativeBookModel> createState() => _NativeBookModelState();
}

class _NativeBookModelState extends State<NativeBookModel> {
  late Future<Uint8List> _coverTexture;
  Timer? _readinessTimer;
  bool _useStaticFallback = false;

  @override
  void initState() {
    super.initState();
    _coverTexture = _loadCoverTexture();
    _readinessTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _useStaticFallback = true);
    });
  }

  @override
  void dispose() {
    _readinessTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NativeBookModel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.book.id != widget.book.id ||
        oldWidget.book.coverBytes != widget.book.coverBytes ||
        oldWidget.book.coverTemplate != widget.book.coverTemplate) {
      _coverTexture = _loadCoverTexture();
    }
  }

  Future<Uint8List> _loadCoverTexture() async {
    final bytes = widget.book.coverBytes;
    late Uint8List source;
    if (bytes != null && bytes.isNotEmpty) {
      source = bytes;
    } else {
      final asset = widget.book.coverAsset ?? _presetAsset(widget.book);
      final data = await rootBundle.load(asset);
      source = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final hasOriginalArtwork =
        (widget.book.coverBytes?.isNotEmpty ?? false) ||
        widget.book.coverAsset != null;
    if (hasOriginalArtwork && !widget.book.overlayCoverText) return source;
    return _composeCoverTexture(source);
  }

  Future<Uint8List> _composeCoverTexture(Uint8List source) async {
    final codec = await ui.instantiateImageCodec(source, targetWidth: 1024);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    final rect = Rect.fromLTWH(0, 0, width, height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(image, rect, rect, Paint());
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x42000000), Colors.transparent, Color(0x82000000)],
          stops: [0, .55, 1],
        ).createShader(rect),
    );
    final title = TextPainter(
      text: TextSpan(
        text: widget.book.title,
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'ShiyeXingshu',
          fontSize: width * .14,
          height: 1.08,
          fontWeight: FontWeight.w400,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 3)),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: width * .72);
    title.paint(
      canvas,
      Offset((width - title.width) / 2, height * .4 - title.height / 2),
    );
    final author = TextPainter(
      text: TextSpan(
        text: widget.book.author,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .86),
          fontSize: width * .055,
          fontWeight: FontWeight.w600,
          letterSpacing: 2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width * .72);
    author.paint(canvas, Offset((width - author.width) / 2, height * .83));
    final rendered = await recorder.endRecording().toImage(
      image.width,
      image.height,
    );
    final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
    codec.dispose();
    image.dispose();
    rendered.dispose();
    if (png == null) return source;
    return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
  }

  static String _presetAsset(Book book) {
    final index = (book.coverTemplate % 20 + 20) % 20 + 1;
    return 'assets/covers/preset_${index.toString().padLeft(2, '0')}.png';
  }

  @override
  Widget build(BuildContext context) {
    if (_useStaticFallback ||
        MediaQuery.disableAnimationsOf(context) ||
        (!Platform.isAndroid && !Platform.isIOS)) {
      return Center(child: BookCover3D(book: widget.book, width: 205));
    }
    return FutureBuilder<Uint8List>(
      future: _coverTexture,
      builder: (context, snapshot) {
        final texture = snapshot.data;
        if (texture == null) {
          return LayoutBuilder(
            builder: (context, constraints) => Center(
              child: BookCoverArtwork(
                book: widget.book,
                width: constraints.maxWidth,
              ),
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Interactive3d(
            key: ValueKey('showroom-model-${widget.book.id}'),
            modelPath: 'assets/models/book_runtime.glb',
            defaultZoom: 2.18,
            backgroundColor: Colors.transparent,
            solidBackgroundColor: const [0, 0, 0, 0],
            initialEntityTextures: [
              EntityTexture(name: 'FrontCover', bytes: texture),
              EntityTexture(name: 'BackCover', bytes: texture),
              EntityTexture(name: 'Spine', bytes: texture),
            ],
            loadingWidget: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: BookCoverArtwork(
                  book: widget.book,
                  width: constraints.maxWidth,
                ),
              ),
            ),
            errorWidget: Center(
              child: BookCover3D(book: widget.book, width: 205),
            ),
            onReady: () => _readinessTimer?.cancel(),
            onError: (_) {
              _readinessTimer?.cancel();
              if (mounted) setState(() => _useStaticFallback = true);
            },
          ),
        );
      },
    );
  }
}
