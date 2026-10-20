import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solfeus/music.dart';
import 'package:solfeus/staff.dart';

void main() {
  test('dotted duration and measure status use quarter-note beats', () {
    final score = Score(
      numerator: 6,
      denominator: 8,
      measures: [
        Measure(
          right: [
            MusicEvent(value: 4, dotted: true),
            MusicEvent(value: 4, dotted: true),
          ],
        ),
      ],
    );
    expect(score.capacity, 3);
    expect(score.status(score.measures.first), 'Completo');
    score.measures.first.right.add(MusicEvent(value: 8));
    expect(score.status(score.measures.first), 'Excedido');
  });

  test('document roundtrip retains both staves and annotations', () {
    final score = Score(
      title: 'Prueba',
      leftHand: true,
      measures: [
        Measure(
          left: [
            MusicEvent(midi: 48, lyric: 'do', chord: 'Menor', inversion: 1),
          ],
        ),
      ],
    );
    final restored = Score.decode(score.encode());
    expect(restored.leftHand, isTrue);
    expect(restored.measures.first.left.first.lyric, 'do');
    expect(restored.measures.first.left.first.chord, 'Menor');
  });

  test('key signature and explicit natural change sounding MIDI pitch', () {
    expect(soundingMidi(MusicEvent(midi: 65), 1), 66);
    expect(soundingMidi(MusicEvent(midi: 65, accidental: 0), 1), 65);
    expect(pitches(MusicEvent(midi: 60, chord: 'Mayor', inversion: 1)), [
      72,
      64,
      67,
    ]);
  });

  test('export generates a playable PCM WAV header', () {
    final data = renderWav(
      Score(
        measures: [
          Measure(right: [MusicEvent()]),
        ],
      ),
    );
    expect(ascii.decode(data.sublist(0, 4)), 'RIFF');
    expect(ascii.decode(data.sublist(8, 12)), 'WAVE');
    expect(data.length, greaterThan(44));
  });

  testWidgets('narrow staff handles lower taps and selects existing notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    int? added;
    int? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: StaffView(
              events: [MusicEvent(midi: 64)],
              clef: 'Sol',
              width: 84,
              onNote: (note) => added = note,
              onSelect: (index) => selected = index,
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(50, 105));
    expect(selected, 0);
    await tester.tapAt(const Offset(50, 60));
    expect(added, isNotNull);
    added = null;
    await tester.tapAt(const Offset(24, 145));
    expect(added, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'measure sheet groups four per row and scrolls after three rows',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: MeasureSheet(
                measureCount: 13,
                selectedIndex: 0,
                rowHeight: 180,
                availableHeight: 1200,
                measureBuilder: (index, width) => SizedBox(
                  width: width,
                  height: 180,
                  child: Column(
                    children: [
                      Text('${index + 1}'),
                      StaffView(
                        events: [MusicEvent(midi: 60 + index)],
                        clef: 'Sol',
                        width: width,
                        showClef: index % 4 == 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(MeasureSheet)).height, 540);
      expect(
        tester.getTopLeft(find.text('1')).dy,
        tester.getTopLeft(find.text('4')).dy,
      );
      expect(
        tester.getTopLeft(find.text('5')).dy,
        greaterThan(tester.getTopLeft(find.text('4')).dy),
      );
      expect(
        tester.getTopLeft(find.text('4')).dx,
        lessThan(tester.getSize(find.byType(MeasureSheet)).width),
      );

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('13'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selected measure scrolls into the fourth staff row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget sheet(int selectedIndex) => MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: MeasureSheet(
            measureCount: 13,
            selectedIndex: selectedIndex,
            rowHeight: 188,
            availableHeight: 1200,
            measureBuilder: (index, width) => SizedBox(
              width: width,
              height: 185,
              child: Column(
                children: [
                  const SizedBox(height: 22),
                  StaffView(
                    events: [MusicEvent()],
                    clef: 'Sol',
                    width: width,
                    showClef: index % 4 == 0,
                  ),
                  const SizedBox(height: 7),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(sheet(0));
    await tester.pumpWidget(sheet(12));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byType(StaffView).last).dy,
      lessThan(tester.getSize(find.byType(MeasureSheet)).height),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('two staves fit inside a row without overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeasureSheet(
            measureCount: 4,
            selectedIndex: 0,
            rowHeight: 344,
            availableHeight: 1200,
            measureBuilder: (index, width) => SizedBox(
              width: width,
              child: Column(
                children: [
                  const SizedBox(height: 22),
                  StaffView(events: const [], clef: 'Sol', width: width),
                  StaffView(events: const [], clef: 'Fa', width: width),
                  const SizedBox(height: 7),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'three complete rows fit without scrolling; a fourth enables it',
    (tester) async {
      Widget sheet(int count) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: MeasureSheet(
              measureCount: count,
              selectedIndex: 0,
              rowHeight: 188,
              availableHeight: 1000,
              measureBuilder: (index, width) => SizedBox(
                width: width,
                height: 185,
                child: Column(
                  children: [
                    const SizedBox(height: 22),
                    StaffView(events: const [], clef: 'Sol', width: width),
                    const SizedBox(height: 7),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(sheet(12));
      final scrollable = find.descendant(
        of: find.byType(MeasureSheet),
        matching: find.byType(Scrollable),
      );
      expect(tester.getSize(find.byType(MeasureSheet)).height, 564);
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        0,
      );
      await tester.pumpWidget(sheet(13));
      await tester.pumpAndSettle();
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('piano scrolls horizontally from A0 through C8', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    int? played;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: PianoKeyboard(
              activePitch: null,
              onNote: (midi) => played = midi,
            ),
          ),
        ),
      ),
    );
    final scrollable = find.descendant(
      of: find.byType(PianoKeyboard),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final before = position.pixels;
    await tester.drag(find.byType(PianoKeyboard), const Offset(-180, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(before));

    await tester.ensureVisible(find.byKey(const ValueKey('piano-108')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('piano-108')));
    expect(played, 108);
    await tester.ensureVisible(find.byKey(const ValueKey('piano-21')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('piano-21')));
    expect(played, 21);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty measures still paint staff lines and a barline', (
    tester,
  ) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: boundary,
            child: const StaffView(events: [], clef: 'Sol', width: 160),
          ),
        ),
      ),
    );
    final captured = await tester.runAsync(() async {
      final image =
          await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final result = (image.width, pixels.buffer.asUint8List());
      image.dispose();
      return result;
    });
    final (width, bytes) = captured!;
    bool isDark(int x, int y) => bytes[(y * width + x) * 4] < 180;
    expect(isDark(85, 57), isTrue);
    expect(isDark(159, 75), isTrue);
  });
}
