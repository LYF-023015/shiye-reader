import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.width = 88});

  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 1.42,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * .09),
        boxShadow: [
          BoxShadow(
            color: book.palette.last.withValues(alpha: .14),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _BookArtwork(book: book, logicalWidth: width),
          Padding(
            padding: EdgeInsets.all(width * .12),
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                book.coverMark,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: book.palette.last,
                  fontSize: width * .11,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  shadows: [
                    Shadow(
                      color: Colors.white.withValues(alpha: .8),
                      blurRadius: 5,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single flat cover texture for use on a real 3D book face.
///
/// Unlike [BookCover3D], this widget does not paint page edges, a second spine,
/// shadows, or any other geometry. That keeps the shelf volume closed and lets
/// the face be raster-cached while only its transform changes during a drag.
class BookCoverArtwork extends StatelessWidget {
  const BookCoverArtwork({super.key, required this.book, this.width = 190});

  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.48;
    final hasOriginalArtwork =
        (book.coverBytes?.isNotEmpty ?? false) || book.coverAsset != null;
    return SizedBox(
      width: width,
      height: height,
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _BookArtwork(
              book: book,
              logicalWidth: width,
              filterQuality: FilterQuality.low,
            ),
            if (hasOriginalArtwork && book.overlayCoverText) ...[
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x52000000),
                      Colors.transparent,
                      Color(0x85000000),
                    ],
                    stops: [0, .55, 1],
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, -.18),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * .14),
                  child: Text(
                    book.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'serif',
                      fontSize: width * .135,
                      height: 1.08,
                      fontWeight: FontWeight.w800,
                      letterSpacing: width * .006,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                        Shadow(color: Colors.white24, blurRadius: 1),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: width * .12,
                right: width * .12,
                bottom: height * .12,
                child: Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .86),
                    fontSize: width * .06,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class BookCover3D extends StatelessWidget {
  const BookCover3D({super.key, required this.book, this.width = 190});

  final Book book;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.48;
    final title = book.title.split('').join('\n');
    final geometry = _BindingGeometry.forStyle(book.bindingStyle);
    final faceWidth = width - geometry.foreEdge;

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(geometry.cornerRadius),
                  right: Radius.circular(geometry.cornerRadius + 1),
                ),
                border: Border.all(
                  color: book.palette.last.withValues(alpha: .2),
                  width: 1.4,
                ),
                color: Color.lerp(book.palette[0], Colors.white, .25),
                boxShadow: [
                  BoxShadow(
                    color: book.palette.last.withValues(alpha: .17),
                    blurRadius: 18,
                    offset: const Offset(7, 11),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: width * geometry.spineRatio * .7,
            top: geometry.pageInset,
            right: 2.5,
            bottom: geometry.pageInset,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(geometry.cornerRadius),
                ),
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color.lerp(geometry.pageColor, Colors.white, .62)!,
                    geometry.pageColor,
                    Color.lerp(geometry.pageColor, Colors.black, .07)!,
                  ],
                  stops: const [0, .72, 1],
                ),
                border: Border.all(
                  color: Colors.black.withValues(alpha: .045),
                  width: .6,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: Container(
              width: faceWidth,
              height: height,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(geometry.cornerRadius),
                  right: Radius.circular(geometry.cornerRadius * .55),
                ),
                border: Border.all(
                  color: book.palette.last.withValues(alpha: .2),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _BookArtwork(book: book, logicalWidth: faceWidth),
                  if (book.overlayCoverText)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: faceWidth * geometry.spineRatio,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              book.palette.last.withValues(alpha: .42),
                              Colors.white.withValues(alpha: .24),
                              book.palette.last.withValues(alpha: .14),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .12),
                              blurRadius: 5,
                              offset: const Offset(3, 0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (book.overlayCoverText)
                    Positioned(
                      top: height * .2,
                      left: faceWidth * .32,
                      right: faceWidth * .2,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: book.palette.last,
                          fontSize: faceWidth * .115,
                          height: 1.12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: Colors.white.withValues(alpha: .86),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: faceWidth * .2,
                    right: faceWidth * .06,
                    bottom: height * .18,
                    child: Text(
                      book.author,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: book.palette.last.withValues(alpha: .82),
                        fontSize: faceWidth * .06,
                        fontWeight: FontWeight.w500,
                        shadows: [
                          Shadow(
                            color: Colors.white.withValues(alpha: .85),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: faceWidth * .12,
                    right: 0,
                    top: 0,
                    height: height * .32,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: .42),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 1.5,
            right: 0,
            bottom: 1.5,
            width: 2.5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: book.palette.last.withValues(alpha: .38),
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(geometry.cornerRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BindingGeometry {
  const _BindingGeometry({
    required this.spineRatio,
    required this.foreEdge,
    required this.pageInset,
    required this.cornerRadius,
    required this.pageColor,
  });

  final double spineRatio;
  final double foreEdge;
  final double pageInset;
  final double cornerRadius;
  final Color pageColor;

  factory _BindingGeometry.forStyle(BookBindingStyle style) {
    return switch (style) {
      BookBindingStyle.hardcover => const _BindingGeometry(
        spineRatio: .105,
        foreEdge: 9,
        pageInset: 4.5,
        cornerRadius: 5,
        pageColor: Color(0xFFF7F4EC),
      ),
      BookBindingStyle.clothbound => const _BindingGeometry(
        spineRatio: .13,
        foreEdge: 11,
        pageInset: 5.5,
        cornerRadius: 7,
        pageColor: Color(0xFFEDE5D6),
      ),
      BookBindingStyle.paperback => const _BindingGeometry(
        spineRatio: .055,
        foreEdge: 6,
        pageInset: 2.5,
        cornerRadius: 3,
        pageColor: Color(0xFFFAF9F4),
      ),
      BookBindingStyle.japaneseBinding => const _BindingGeometry(
        spineRatio: .045,
        foreEdge: 5,
        pageInset: 2,
        cornerRadius: 1.5,
        pageColor: Color(0xFFF2EBDD),
      ),
    };
  }
}

class _BookArtwork extends StatelessWidget {
  const _BookArtwork({
    required this.book,
    required this.logicalWidth,
    this.filterQuality = FilterQuality.medium,
  });

  final Book book;
  final double logicalWidth;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final decodeWidth = (logicalWidth * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(120, 720);
    final bytes = book.coverBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        cacheWidth: decodeWidth,
        errorBuilder: (_, _, _) => _PresetCover(
          template: book.coverTemplate,
          palette: book.palette,
          cacheWidth: decodeWidth,
          filterQuality: filterQuality,
        ),
      );
    }
    final asset = book.coverAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: filterQuality,
        gaplessPlayback: true,
        cacheWidth: decodeWidth,
        errorBuilder: (_, _, _) => _PresetCover(
          template: book.coverTemplate,
          palette: book.palette,
          cacheWidth: decodeWidth,
          filterQuality: filterQuality,
        ),
      );
    }
    return _PresetCoverRaster(book: book, pixelWidth: decodeWidth);
  }
}

final Map<String, Future<ui.Image>> _presetCoverRasterCache = {};

Future<void> precacheBookCoverArtwork(Book book, int pixelWidth) async {
  await _presetCoverImage(book, pixelWidth);
}

Future<ui.Image> _presetCoverImage(Book book, int pixelWidth) {
  final key =
      '${book.id}|${book.coverTemplate}|$pixelWidth|${book.overlayCoverText}';
  return _presetCoverRasterCache.putIfAbsent(
    key,
    () => _renderPresetCover(book, pixelWidth),
  );
}

class _PresetCoverRaster extends StatelessWidget {
  const _PresetCoverRaster({required this.book, required this.pixelWidth});

  final Book book;
  final int pixelWidth;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: _presetCoverImage(book, pixelWidth),
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) {
          return _PresetCover(
            template: book.coverTemplate,
            palette: book.palette,
            cacheWidth: pixelWidth,
            filterQuality: FilterQuality.low,
          );
        }
        return RawImage(
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}

Future<ui.Image> _renderPresetCover(Book book, int width) async {
  final index = (book.coverTemplate % 20 + 20) % 20 + 1;
  final data = await rootBundle.load(
    'assets/covers/preset_${index.toString().padLeft(2, '0')}.png',
  );
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    targetWidth: width,
  );
  final frame = await codec.getNextFrame();
  final source = frame.image;
  final height = (width * 1.48).round();
  final rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
    rect,
    Paint(),
  );
  if (book.overlayCoverText) {
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
        text: book.title,
        style: TextStyle(
          color: Colors.white,
          fontFamily: 'serif',
          fontSize: width * .135,
          height: 1.08,
          fontWeight: FontWeight.w800,
          shadows: const [
            Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
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
        text: book.author,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .86),
          fontSize: width * .06,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width * .72);
    author.paint(canvas, Offset((width - author.width) / 2, height * .84));
  }
  final result = await recorder.endRecording().toImage(width, height);
  codec.dispose();
  source.dispose();
  return result;
}

class _PresetCover extends StatelessWidget {
  const _PresetCover({
    required this.template,
    required this.palette,
    required this.cacheWidth,
    required this.filterQuality,
  });

  final int template;
  final List<Color> palette;
  final int cacheWidth;
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final index = (template % 20 + 20) % 20 + 1;
    return Image.asset(
      'assets/covers/preset_${index.toString().padLeft(2, '0')}.png',
      fit: BoxFit.cover,
      alignment: Alignment.center,
      filterQuality: filterQuality,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) =>
          CustomPaint(painter: _CoverPainter(palette, template)),
    );
  }
}

class _CoverPainter extends CustomPainter {
  const _CoverPainter(this.palette, this.template);

  final List<Color> palette;
  final int template;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final variant = (template ~/ 5) % 4;
    final family = template % 5;
    final background = Paint()
      ..shader = LinearGradient(
        begin: [
          Alignment.topLeft,
          Alignment.topCenter,
          Alignment.centerLeft,
          Alignment.bottomLeft,
        ][variant],
        end: [
          Alignment.bottomRight,
          Alignment.bottomCenter,
          Alignment.centerRight,
          Alignment.topRight,
        ][variant],
        colors: [
          Color.lerp(palette[1], Colors.white, variant * .07)!,
          palette[0],
          Color.lerp(palette[2], Colors.black, .12)!,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, background);

    switch (family) {
      case 0:
        final mist = Paint()..color = Colors.white.withValues(alpha: .3);
        canvas.drawCircle(
          Offset(size.width * (.15 + variant * .18), size.height * .38),
          size.width * .52,
          mist,
        );
        final mountain = Path()
          ..moveTo(0, size.height * .8)
          ..lineTo(size.width * .3, size.height * (.48 + variant * .03))
          ..lineTo(size.width * .55, size.height * .72)
          ..lineTo(size.width * .82, size.height * .45)
          ..lineTo(size.width, size.height * .67)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          mountain,
          Paint()..color = palette[2].withValues(alpha: .76),
        );
        break;
      case 1:
        final line = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .025
          ..color = Colors.white.withValues(alpha: .42);
        for (var index = 0; index < 4; index++) {
          canvas.drawCircle(
            Offset(
              size.width * (.2 + index * .24),
              size.height * (.28 + variant * .1),
            ),
            size.width * (.16 + index * .055),
            line,
          );
        }
        break;
      case 2:
        final band = Paint()..color = Colors.white.withValues(alpha: .28);
        for (var index = -1; index < 4; index++) {
          final left = size.width * (index * .34 + variant * .07);
          final path = Path()
            ..moveTo(left, 0)
            ..lineTo(left + size.width * .2, 0)
            ..lineTo(left + size.width * .78, size.height)
            ..lineTo(left + size.width * .55, size.height)
            ..close();
          canvas.drawPath(path, band);
        }
        break;
      case 3:
        final accent = Paint()..color = Colors.white.withValues(alpha: .55);
        canvas.drawRect(
          Rect.fromLTWH(
            size.width * (.12 + variant * .06),
            size.height * .12,
            size.width * .025,
            size.height * .76,
          ),
          accent,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            0,
            size.height * (.68 + variant * .035),
            size.width,
            size.height * .025,
          ),
          accent,
        );
        break;
      case 4:
        final wavePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * .08
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .28);
        for (var index = 0; index < 4; index++) {
          final y = size.height * (.2 + index * .2);
          final wave = Path()
            ..moveTo(-size.width * .1, y)
            ..cubicTo(
              size.width * .25,
              y - size.height * (.1 + variant * .015),
              size.width * .65,
              y + size.height * .1,
              size.width * 1.1,
              y,
            );
          canvas.drawPath(wave, wavePaint);
        }
        break;
    }

    canvas.drawCircle(
      Offset(size.width * (.76 - variant * .12), size.height * .18),
      math.max(4, size.width * .055),
      Paint()..color = palette[2].withValues(alpha: .35),
    );
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.template != template;
}
