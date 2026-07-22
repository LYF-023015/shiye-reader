import 'package:flutter/material.dart';

import '../models/book.dart';
import 'book_cover.dart';

String bookHeroTag(Book book) => 'book-extract-${book.id}';

class BookHero extends StatelessWidget {
  const BookHero({super.key, required this.book, required this.child});

  final Book book;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: bookHeroTag(book),
      transitionOnUserGestures: true,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder:
          (flightContext, animation, direction, fromContext, toContext) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = animation.value.clamp(0.0, 1.0);
                final extraction = _phase(t, 0, .34, Curves.easeOutCubic);
                final open = _phase(t, .36, .72, Curves.easeInOutCubic);
                final close = _phase(t, .7, .9, Curves.easeInOutCubic);
                final openAmount = open * (1 - close) * 1.12;
                final liftScale = 1 + extraction * .12;

                return Material(
                  color: Colors.transparent,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Transform.scale(
                      scale: liftScale,
                      child: SizedBox(
                        width: 186,
                        height: 276,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3EEDC),
                                  borderRadius: BorderRadius.circular(7),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: .14),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: .3),
                                      blurRadius: 12 + 30 * extraction,
                                      spreadRadius: 2 * extraction,
                                      offset: Offset(
                                        8 * extraction,
                                        14 * extraction,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 6,
                              top: 4,
                              bottom: 4,
                              width: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: book.palette.first,
                                  borderRadius: const BorderRadius.horizontal(
                                    left: Radius.circular(5),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Transform(
                                alignment: Alignment.centerLeft,
                                transform: Matrix4.identity()
                                  ..setEntry(3, 2, -.0018)
                                  ..rotateY(-openAmount),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: BookCoverArtwork(
                                    book: book,
                                    width: 186,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
      child: child,
    );
  }
}

double _phase(double t, double begin, double end, Curve curve) {
  if (t <= begin) return 0;
  if (t >= end) return 1;
  return curve.transform((t - begin) / (end - begin));
}
