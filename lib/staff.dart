import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'music.dart';

const ink = Color(0xFF202B29);
const accent = Color(0xFFE86148);
const teal = Color(0xFF197C74);
const paper = Color(0xFFF7F6F1);

double _noteStart(double width, bool showClef) =>
    showClef ? min(55.0, width * 0.35) : 8.0;

double _noteY(MusicEvent event, String clef, double height) {
  final base = switch (clef) {
    'Fa' => 43,
    'Do 3ª' => 53,
    'Do 4ª' => 50,
    _ => 64,
  };
  const diatonic = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
  final pitch = event.midi;
  final steps =
      (pitch ~/ 12 - base ~/ 12) * 7 +
      diatonic[pitch % 12] -
      diatonic[base % 12];
  return (105.0 - steps * 6).clamp(17.0, height - 22);
}

class MeasureSheet extends StatefulWidget {
  const MeasureSheet({
    super.key,
    required this.measureCount,
    required this.selectedIndex,
    required this.rowHeight,
    required this.availableHeight,
    required this.measureBuilder,
  });

  final int measureCount;
  final int selectedIndex;
  final double rowHeight;
  final double availableHeight;
  final Widget Function(int index, double width) measureBuilder;

  @override
  State<MeasureSheet> createState() => _MeasureSheetState();
}

class PianoKeyboard extends StatefulWidget {
  const PianoKeyboard({
    super.key,
    required this.activePitch,
    required this.onNote,
  });

  final int? activePitch;
  final ValueChanged<int> onNote;

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  final ScrollController _controller = ScrollController(
    initialScrollOffset: 23 * 42.0,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 106,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final whiteWidth = (constraints.maxWidth / 9).clamp(34.0, 50.0);
        final keys = <Widget>[];
        var whiteIndex = 0;
        for (var midi = 21; midi <= 108; midi++) {
          if ([1, 3, 6, 8, 10].contains(midi % 12)) continue;
          final position = whiteIndex++ * whiteWidth;
          keys.add(
            Positioned(
              left: position,
              top: 0,
              width: whiteWidth - 1,
              height: 100,
              child: InkWell(
                key: ValueKey('piano-$midi'),
                onTap: () => widget.onNote(midi),
                child: Container(
                  alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 7),
                  decoration: BoxDecoration(
                    color: widget.activePitch == midi
                        ? const Color(0xFFD6ECE4)
                        : Colors.white,
                    border: Border.all(color: const Color(0xFFB6C5BF)),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: midi % 12 == 0
                      ? Text(
                          noteName(midi),
                          style: const TextStyle(fontSize: 10),
                        )
                      : null,
                ),
              ),
            ),
          );
        }
        var precedingWhites = 0;
        for (var midi = 21; midi <= 108; midi++) {
          if (![1, 3, 6, 8, 10].contains(midi % 12)) {
            precedingWhites++;
            continue;
          }
          keys.add(
            Positioned(
              left: precedingWhites * whiteWidth - whiteWidth * 0.32,
              top: 0,
              width: whiteWidth * 0.6,
              height: 59,
              child: InkWell(
                key: ValueKey('piano-$midi'),
                onTap: () => widget.onNote(midi),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.activePitch == midi ? teal : ink,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return Scrollbar(
          controller: _controller,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: whiteIndex * whiteWidth,
              height: 102,
              child: Stack(children: keys),
            ),
          ),
        );
      },
    ),
  );
}

class _MeasureSheetState extends State<MeasureSheet> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant MeasureSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex ~/ 4 != oldWidget.selectedIndex ~/ 4 ||
        widget.measureCount != oldWidget.measureCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final offset = (widget.selectedIndex ~/ 4 * widget.rowHeight).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = (widget.measureCount + 3) ~/ 4;
    final height = min(
      widget.rowHeight * min(rows, 3),
      max(110.0, widget.availableHeight - 250),
    );
    return SizedBox(
      height: height,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        physics: widget.rowHeight * rows > height
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: rows,
        itemBuilder: (context, row) => SizedBox(
          height: widget.rowHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final count = min(4, widget.measureCount - row * 4);
              final width = constraints.maxWidth / count;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var column = 0; column < count; column++)
                    widget.measureBuilder(row * 4 + column, width),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

Future<Uint8List> staffPng(List<MusicEvent> events, String clef) async {
  const width = 520.0;
  const height = 156.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.scale(2);
  _StaffPainter(
    events,
    clef,
    -1,
    -1,
    false,
    true,
  ).paint(canvas, const Size(width, height));
  final image = await recorder.endRecording().toImage(
    width.toInt() * 2,
    height.toInt() * 2,
  );
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return png!.buffer.asUint8List();
}

class StaffView extends StatelessWidget {
  const StaffView({
    super.key,
    required this.events,
    required this.clef,
    this.selected = -1,
    this.active = -1,
    this.onNote,
    this.onSelect,
    this.compact = false,
    this.width,
    this.showClef = true,
  });

  final List<MusicEvent> events;
  final String clef;
  final int selected;
  final int active;
  final ValueChanged<int>? onNote;
  final ValueChanged<int>? onSelect;
  final bool compact;
  final double? width;
  final bool showClef;

  @override
  Widget build(BuildContext context) {
    final staffWidth =
        width ??
        max(
          MediaQuery.sizeOf(context).width - (compact ? 100 : 72),
          260.0 + max(0, events.length - 3) * 48,
        );
    final staff = GestureDetector(
      onTapDown: onNote == null && onSelect == null
          ? null
          : (details) {
              final position = details.localPosition;
              final firstNote = _noteStart(staffWidth, showClef);
              final spacing =
                  (staffWidth - firstNote - 14) / max(events.length, 1);
              final index = events.isEmpty
                  ? -1
                  : ((position.dx - firstNote) / spacing - 0.5).round().clamp(
                      0,
                      events.length - 1,
                    );
              if (index >= 0 &&
                  onSelect != null &&
                  (position.dx - (firstNote + spacing * (index + 0.5))).abs() <
                      12 &&
                  (position.dy -
                              (events[index].rest
                                  ? 78
                                  : _noteY(
                                      events[index],
                                      clef,
                                      compact ? 114 : 156,
                                    )))
                          .abs() <
                      14) {
                onSelect!(index);
              } else if (onNote != null) {
                final base = switch (clef) {
                  'Fa' => 43,
                  'Do 3ª' => 53,
                  'Do 4ª' => 50,
                  _ => 64,
                };
                const steps = [0, 2, 4, 5, 7, 9, 11];
                final diatonic = ((105 - position.dy) / 6).round().clamp(
                  -12,
                  16,
                );
                final octave = (diatonic / 7).floor();
                final degree = diatonic - octave * 7;
                onNote!((base + octave * 12 + steps[degree]).clamp(0, 107));
              }
            },
      child: CustomPaint(
        size: Size(staffWidth, compact ? 114 : 156),
        painter: _StaffPainter(
          events,
          clef,
          selected,
          active,
          compact,
          showClef,
        ),
      ),
    );
    if (width != null) return staff;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: staff,
    );
  }
}

class _StaffPainter extends CustomPainter {
  _StaffPainter(
    this.events,
    this.clef,
    this.selected,
    this.active,
    this.compact,
    this.showClef,
  );

  final List<MusicEvent> events;
  final String clef;
  final int selected;
  final int active;
  final bool compact;
  final bool showClef;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 57.0;
    final line = Paint()
      ..color = ink.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var index = 0; index < 5; index++) {
      final y = top + index * 12;
      canvas.drawLine(
        Offset(showClef ? 12 : 0, y),
        Offset(size.width, y),
        line,
      );
    }
    canvas.drawLine(
      Offset(size.width - 1, top),
      Offset(size.width - 1, top + 48),
      line..strokeWidth = 2,
    );
    final glyph = clef == 'Sol'
        ? '𝄞'
        : clef == 'Fa'
        ? '𝄢'
        : '𝄡';
    if (showClef) {
      _text(
        canvas,
        glyph,
        const Offset(4, 37),
        min(compact ? 42.0 : 48.0, size.width * 0.5),
        ink,
      );
    }
    final firstNote = _noteStart(size.width, showClef);
    final spacing = (size.width - firstNote - 14) / max(events.length, 1);
    final noteScale = (spacing / 23).clamp(0.2, 1.0);
    for (var index = 0; index < events.length; index++) {
      final event = events[index];
      final x = firstNote + spacing * (index + 0.5);
      final color = index == active
          ? teal
          : index == selected
          ? accent
          : ink;
      if (event.rest) {
        _text(
          canvas,
          '𝄽',
          Offset(x - 14 * noteScale, top - 5),
          30 * noteScale,
          color,
        );
      } else {
        final y = _noteY(event, clef, size.height);
        canvas.save();
        canvas.translate(x, y);
        canvas.scale(noteScale);
        final fill = Paint()..color = color;
        if (y > top + 49 || y < top - 1) {
          canvas.drawLine(const Offset(-15, 0), const Offset(15, 0), line);
        }
        canvas.rotate(-0.27);
        canvas.drawOval(
          const Rect.fromLTWH(-10, -6, 20, 12),
          event.value == 1 || event.value == 2
              ? (Paint()
                  ..color = color
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2)
              : fill,
        );
        canvas.restore();
        if (event.value != 1) {
          canvas.save();
          canvas.translate(x, y);
          canvas.scale(noteScale);
          canvas.drawLine(
            const Offset(9, 0),
            const Offset(9, -34),
            Paint()
              ..color = color
              ..strokeWidth = 1.5,
          );
          final flags = event.value >= 8
              ? (log(event.value / 4) / ln2).round()
              : 0;
          for (var flag = 0; flag < flags; flag++) {
            final flagY = -34.0 + flag * 7;
            final path = Path()
              ..moveTo(9, flagY)
              ..quadraticBezierTo(32, flagY + 2, 17, flagY + 17);
            canvas.drawPath(
              path,
              Paint()
                ..color = color
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2,
            );
          }
          canvas.restore();
        }
        if (event.accidental != 9) {
          _text(
            canvas,
            event.accidental == 0
                ? '♮'
                : event.accidental > 0
                ? '♯'
                : '♭',
            Offset(x - 28 * noteScale, y - 16 * noteScale),
            22 * noteScale,
            color,
          );
        }
        if (event.chord != 'Ninguno' && spacing > 28) {
          _text(canvas, event.chord, Offset(x - 18, 7), 10, teal);
        }
      }
      if (event.dotted) {
        canvas.drawCircle(Offset(x + 18, top + 27), 2, Paint()..color = color);
      }
      if (!compact && event.lyric.isNotEmpty) {
        _text(canvas, event.lyric, Offset(x - 18, 119), 11, ink);
      }
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset position,
    double size,
    Color color,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: color, fontSize: size, fontFamily: 'serif'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _StaffPainter old) => true;
}
