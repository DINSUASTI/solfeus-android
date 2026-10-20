import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'music.dart';
import 'score_store.dart';
import 'staff.dart';

class SolfeusApp extends StatelessWidget {
  const SolfeusApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Solfeus',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: teal,
        surface: paper,
        primary: ink,
      ),
      fontFamily: GoogleFonts.dmSans().fontFamily,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFD6DCD7)),
        ),
      ),
    ),
    home: const SolfeusHome(),
  );
}

class SolfeusHome extends StatefulWidget {
  const SolfeusHome({super.key});

  @override
  State<SolfeusHome> createState() => _SolfeusHomeState();
}

class _SolfeusHomeState extends State<SolfeusHome> {
  final store = ScoreStore();
  final player = AudioPlayer();
  final auth = LocalAuthentication();
  static const accountChannel = MethodChannel('solfeus/google_account');
  String? googleAccount;
  Timer? playTimer;
  List<Score> scores = [];
  Score? score;
  Score? clipboard;
  final history = <String>[];
  int tab = 0;
  int measureIndex = 0;
  int selectedEvent = -1;
  int noteValue = 4;
  int pitch = 60;
  bool rest = false;
  bool dotted = false;
  bool left = false;
  bool metronome = false;
  bool playing = false;
  int activeMeasure = -1;
  int activeRight = -1;
  int activeLeft = -1;
  int? activePitch;
  bool unlocked = false;
  bool busy = true;
  String? error;

  @override
  void initState() {
    super.initState();
    player.onPlayerComplete.listen((_) {
      _stopTracking();
    });
    _start();
  }

  Future<void> _start() async {
    try {
      final available = await auth.isDeviceSupported();
      if (!mounted) return;
      if (available) {
        setState(() => busy = false);
        await _unlock();
      } else {
        setState(() {
          busy = false;
          error =
              'Configura huella o bloqueo de pantalla en Android para acceder.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = 'No se pudo verificar el bloqueo del dispositivo.';
        });
      }
    }
  }

  Future<void> _unlock() async {
    try {
      final success = await auth.authenticate(
        localizedReason: 'Desbloquea tus partituras en Solfeus',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      if (!success || !mounted) return;
      final saved = await store.all();
      final account = await accountChannel.invokeMethod<String>('getAccount');
      if (mounted) {
        setState(() {
          scores = saved;
          googleAccount = account;
          unlocked = true;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Autenticación no disponible. Comprueba el bloqueo de Android.',
        );
      }
    }
  }

  @override
  void dispose() {
    playTimer?.cancel();
    player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final saved = await store.all();
    if (mounted) setState(() => scores = saved);
  }

  Future<void> _edit(Score target) async {
    await player.stop();
    _stopTracking();
    setState(() {
      score = target;
      tab = 1;
      measureIndex = 0;
      selectedEvent = -1;
      history.clear();
      playing = false;
    });
  }

  Future<void> _newScore() async {
    final account = googleAccount ?? await _chooseGoogleAccount();
    if (account == null) return;
    final created = Score(composer: account);
    await store.save(created);
    await _refresh();
    await _edit(created);
    if (mounted) _settings();
  }

  Future<String?> _chooseGoogleAccount() async {
    try {
      final account = await accountChannel.invokeMethod<String>('chooseAccount');
      if (mounted && account != null && account.isNotEmpty) {
        setState(() => googleAccount = account);
        return account;
      }
    } catch (_) {
      _message('No se pudo seleccionar una cuenta Google del dispositivo.');
    }
    return null;
  }

  void _change(VoidCallback change) {
    final current = score;
    if (current == null) return;
    history.add(current.encode());
    if (history.length > 40) history.removeAt(0);
    setState(change);
    unawaited(store.save(current));
  }

  void _undo() {
    if (history.isEmpty) return;
    final previous = Score.decode(history.removeLast());
    setState(() {
      score = previous;
      measureIndex = measureIndex.clamp(0, previous.measures.length - 1);
      selectedEvent = -1;
    });
    unawaited(store.save(previous));
  }

  List<MusicEvent> get _events {
    final measure = score!.measures[measureIndex];
    return left ? measure.left : measure.right;
  }

  void _insert(int midi) {
    _change(() {
      _events.add(
        MusicEvent(midi: midi, value: noteValue, rest: rest, dotted: dotted),
      );
      selectedEvent = _events.length - 1;
    });
  }

  void _fill() {
    final current = score!;
    final remaining =
        current.capacity - current.measures[measureIndex].beats(left);
    if (remaining <= 0) return;
    _change(() {
      var beats = remaining;
      for (final value in [1, 2, 4, 8, 16, 32, 64]) {
        final duration = 4 / value;
        while (beats + 0.0001 >= duration) {
          _events.add(MusicEvent(value: value, rest: true));
          beats -= duration;
        }
      }
    });
  }

  Future<void> _play() async {
    if (playing) {
      await player.stop();
      _stopTracking();
      return;
    }
    try {
      final data = renderWav(score!, metronome: metronome);
      await player.play(BytesSource(data));
      if (mounted) {
        setState(() => playing = true);
        final started = DateTime.now();
        playTimer?.cancel();
        playTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
          if (!mounted || !playing || score == null) return;
          final current = score!;
          final elapsed =
              DateTime.now().difference(started).inMilliseconds / 1000;
          final measureDuration = current.capacity * 60 / current.tempo;
          final index = (elapsed / measureDuration).floor();
          if (index >= current.measures.length) return;
          final position = elapsed - index * measureDuration;
          int active(List<MusicEvent> events) {
            var time = 0.0;
            for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
              time += events[eventIndex].beats * 60 / current.tempo;
              if (position < time) return eventIndex;
            }
            return -1;
          }

          final rightIndex = active(current.measures[index].right);
          final leftIndex = current.leftHand
              ? active(current.measures[index].left)
              : -1;
          setState(() {
            measureIndex = index;
            activeMeasure = index;
            activeRight = rightIndex;
            activeLeft = leftIndex;
            activePitch =
                rightIndex >= 0 &&
                    !current.measures[index].right[rightIndex].rest
                ? soundingMidi(
                    current.measures[index].right[rightIndex],
                    current.key,
                  )
                : leftIndex >= 0 &&
                      !current.measures[index].left[leftIndex].rest
                ? soundingMidi(
                    current.measures[index].left[leftIndex],
                    current.key,
                  )
                : null;
          });
        });
      }
    } catch (_) {
      _message('No se pudo reproducir el audio.');
    }
  }

  void _stopTracking() {
    playTimer?.cancel();
    if (mounted) {
      setState(() {
        playing = false;
        activeMeasure = -1;
        activeRight = -1;
        activeLeft = -1;
        activePitch = null;
      });
    }
  }

  Future<void> _exportWav() async {
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/solfeus-${score!.id}.wav');
      await file.writeAsBytes(renderWav(score!, metronome: metronome));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          title: '${score!.title} · audio WAV',
        ),
      );
    } catch (_) {
      _message('No se pudo exportar el audio.');
    }
  }

  Future<void> _exportPdf() async {
    try {
      final current = score!;
      final document = pw.Document();
      final logo = pw.MemoryImage((await rootBundle.load('assets/logoSolfeus.png')).buffer.asUint8List());
      final notation = <List<pw.MemoryImage>>[];
      for (final measure in current.measures) {
        notation.add([
          pw.MemoryImage(await staffPng(measure.right, current.clef)),
          if (current.leftHand)
            pw.MemoryImage(await staffPng(measure.left, 'Fa')),
        ]);
      }
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (context) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [pw.Image(logo, width: 90, height: 60, fit: pw.BoxFit.contain)]),
          build: (context) => [
            pw.Text(
              current.title,
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text(current.composer),
            pw.SizedBox(height: 12),
            pw.Text(
              '${current.clef}  ·  ${current.numerator}/${current.denominator}  ·  ${current.tempo} BPM',
            ),
            pw.SizedBox(height: 24),
            for (var row = 0; row < (current.measures.length + 3) ~/ 4; row++) ...[
              pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                for (var index = row * 4; index < min((row + 1) * 4, current.measures.length); index++)
                  pw.Expanded(child: pw.Column(children: [
                    pw.Text('Compás ${index + 1}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    for (final staff in notation[index])
                      pw.Image(staff, height: 78, fit: pw.BoxFit.contain),
                  ])),
              ]),
              pw.SizedBox(height: 14),
            ],
          ],
        ),
      );
      await Printing.sharePdf(
        bytes: await document.save(),
        filename: 'solfeus-${current.id}.pdf',
      );
    } catch (_) {
      _message('No se pudo exportar el PDF.');
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!unlocked) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/favicon.png', height: 74, width: 88, fit: BoxFit.contain),
                  const SizedBox(height: 16),
                  Text(
                    'Solfeus',
                    style: GoogleFonts.fraunces(
                      fontSize: 38,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error ?? 'Tus partituras, solo para ti.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (busy)
                    const CircularProgressIndicator()
                  else
                    FilledButton.icon(
                      onPressed: _unlock,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Desbloquear'),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/favicon.png', height: 34, width: 40, fit: BoxFit.contain),
            const SizedBox(width: 9),
            Text(
              'solfeus',
              style: GoogleFonts.fraunces(
                fontWeight: FontWeight.w700,
                fontSize: 25,
              ),
            ),
          ],
        ),
        actions: tab == 1 && score != null
            ? [
                IconButton(
                  tooltip: 'Deshacer',
                  onPressed: history.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo_rounded),
                ),
                IconButton(
                  tooltip: 'Configuración de partitura',
                  onPressed: _settings,
                  icon: const Icon(Icons.tune_rounded),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Exportar',
                  icon: const Icon(Icons.ios_share_rounded),
                  onSelected: (value) =>
                      value == 'pdf' ? _exportPdf() : _exportWav(),
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'pdf',
                      child: Text('Exportar PDF'),
                    ),
                    const PopupMenuItem(
                      value: 'wav',
                      child: Text('Exportar WAV'),
                    ),
                  ],
                ),
              ]
            : null,
      ),
      body: SafeArea(
        child: switch (tab) {
          1 when score != null => _editor(),
          2 => _learn(),
          _ => _library(),
        },
      ),
      bottomNavigationBar: NavigationBar(
        height: 68,
        backgroundColor: Colors.white,
        selectedIndex: tab,
        onDestinationSelected: (index) {
          if (index == 1 && score == null) {
            if (scores.isEmpty) {
              unawaited(_newScore());
            } else {
              unawaited(_edit(scores.first));
            }
          } else {
            setState(() => tab = index);
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music_rounded),
            label: 'Biblioteca',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note_rounded),
            label: 'Editor',
          ),
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school_rounded),
            label: 'Solfeo',
          ),
        ],
      ),
    );
  }

  Widget _library() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 26, 22, 40),
    children: [
      Text(
        'Tu estudio',
        style: GoogleFonts.fraunces(fontSize: 37, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 5),
      Text(
        '${scores.length} ${scores.length == 1 ? 'partitura' : 'partituras'} en tu biblioteca',
        style: const TextStyle(color: Color(0xFF6B7772)),
      ),
      const SizedBox(height: 25),
      InkWell(
        onTap: _newScore,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EMPIEZA A CREAR',
                      style: TextStyle(
                        color: Color(0xFF90C9BA),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      'Una idea, una partitura.',
                      style: GoogleFonts.fraunces(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Abre el editor y deja que suene.',
                      style: TextStyle(color: Color(0xFFBAC8C3)),
                    ),
                  ],
                ),
              ),
              const CircleAvatar(
                backgroundColor: accent,
                radius: 24,
                child: Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 31),
      Text(
        'PARTITURAS',
        style: TextStyle(
          color: teal,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 13),
      if (scores.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 42),
          child: Column(
            children: [
              Icon(
                Icons.music_note_outlined,
                size: 50,
                color: teal.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              const Text('Todavía no hay partituras'),
            ],
          ),
        ),
      for (final item in scores)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _edit(item),
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE7F3EF),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.music_note, color: teal),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${item.composer.isEmpty ? 'Sin compositor' : item.composer}  ·  ${item.clef}  ·  ${item.numerator}/${item.denominator}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6B7772),
                            ),
                          ),
                          Text(
                            '${item.measures.length} compases  ·  ${item.tempo} BPM  ·  ${item.updated.day}/${item.updated.month}/${item.updated.year}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7772),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Opciones de partitura',
                      onSelected: (action) async {
                        if (action == 'delete') {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('¿Eliminar partitura?'),
                              content: Text('Se eliminará "${item.title}".'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancelar'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Eliminar'),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await store.delete(item);
                            if (score?.id == item.id) {
                              setState(() => score = null);
                            }
                            await _refresh();
                          }
                        } else {
                          await _edit(item);
                          if (action == 'play') await _play();
                          if (action == 'pdf') await _exportPdf();
                          if (action == 'wav') await _exportWav();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Editar')),
                        PopupMenuItem(value: 'play', child: Text('Reproducir')),
                        PopupMenuItem(
                          value: 'pdf',
                          child: Text('Exportar PDF'),
                        ),
                        PopupMenuItem(
                          value: 'wav',
                          child: Text('Exportar WAV'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ],
  );

  Widget _editor() {
    final current = score!;
    final measure = current.measures[measureIndex];
    final status = current.status(measure, left: left);
    final used = measure.beats(left);
    final rowHeight = current.leftHand ? 344.0 : 188.0;
    return LayoutBuilder(builder: (context, constraints) => Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.fraunces(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          current.composer.isEmpty
                              ? 'Añade un compositor'
                              : current.composer,
                          style: const TextStyle(color: Color(0xFF6B7772)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _settings,
                    tooltip: 'Editar datos',
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  _metric(Icons.music_note_rounded, current.clef),
                  const SizedBox(width: 7),
                  _metric(
                    Icons.more_time_rounded,
                    '${current.numerator}/${current.denominator}',
                  ),
                  const SizedBox(width: 7),
                  _metric(Icons.speed_rounded, '${current.tempo} BPM'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'COMPÁS ${measureIndex + 1} / ${current.measures.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Compás anterior',
                    onPressed: measureIndex == 0
                        ? null
                        : () => setState(() {
                            measureIndex--;
                            selectedEvent = -1;
                          }),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Compás siguiente',
                    onPressed: measureIndex == current.measures.length - 1
                        ? null
                        : () => setState(() {
                            measureIndex++;
                            selectedEvent = -1;
                          }),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        MeasureSheet(
          measureCount: current.measures.length,
          selectedIndex: measureIndex,
          rowHeight: rowHeight,
          availableHeight: constraints.maxHeight,
          measureBuilder: (index, width) => _measureCell(current, index, width),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            children: [
              Row(
                children: [
                  Icon(
                    status == 'Completo'
                        ? Icons.check_circle
                        : status == 'Excedido'
                        ? Icons.error
                        : Icons.timelapse,
                    size: 17,
                    color: status == 'Completo'
                        ? teal
                        : status == 'Excedido'
                        ? accent
                        : const Color(0xFFA87228),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text('$status · ${used.toStringAsFixed(used.truncateToDouble() == used ? 0 : 2)} / ${current.capacity} pulsos',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                  const Spacer(),
                  TextButton(onPressed: _fill, child: const Text('Completar')),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _action(
                    Icons.add,
                    'Compás',
                    () => _change(() {
                      current.measures.add(Measure());
                      measureIndex = current.measures.length - 1;
                      selectedEvent = -1;
                    }),
                  ),
                  _action(Icons.content_copy, 'Copiar', () {
                    clipboard = Score(
                      measures: [Measure.fromJson(measure.toJson())],
                    );
                    _message('Compás copiado');
                  }),
                  _action(
                    Icons.content_paste,
                    'Pegar',
                    clipboard == null
                        ? null
                        : () => _change(
                            () => current.measures[measureIndex] =
                                Measure.fromJson(
                                  clipboard!.measures.first.toJson(),
                                ),
                          ),
                  ),
                  _action(Icons.delete_outline, 'Eliminar', () {
                    _change(() {
                      if (current.measures.length > 1) {
                        current.measures.removeAt(measureIndex);
                        measureIndex = measureIndex.clamp(
                          0,
                          current.measures.length - 1,
                        );
                      } else {
                        current.measures[0] = Measure();
                      }
                      selectedEvent = -1;
                    });
                  }),
                ],
              ),
              const SizedBox(height: 25),
              const Text(
                'FIGURA Y ENTRADA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: teal,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 0, children: [
                for (final value in [1, 2, 4, 8, 16, 32, 64])
                  ChoiceChip(
                    label: Text(_figure(value)),
                    selected: noteValue == value,
                    onSelected: (_) => setState(() => noteValue = value),
                  ),
              ]),
              Wrap(
                spacing: 6,
                runSpacing: 0,
                children: [
                  FilterChip(
                    label: const Text('Silencio'),
                    selected: rest,
                    onSelected: (value) => setState(() => rest = value),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Puntillo'),
                    selected: dotted,
                    onSelected: (value) => setState(() => dotted = value),
                  ),
                  if (current.leftHand)
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('D')),
                        ButtonSegment(value: true, label: Text('I')),
                      ],
                      selected: {left},
                      onSelectionChanged: (value) => setState(() {
                        left = value.first;
                        selectedEvent = -1;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Toca el teclado o el pentagrama para añadir ${rest ? 'un silencio' : 'una nota'}.',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7772)),
              ),
              const SizedBox(height: 14),
              _keyboard(),
              const SizedBox(height: 20),
            ],
          ),
        ),
        Container(
          color: ink,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() => metronome = !metronome),
                tooltip: 'Metrónomo',
                icon: Icon(
                  Icons.timer_outlined,
                  color: metronome ? const Color(0xFF90D1C0) : Colors.white70,
                ),
              ),
              const Spacer(),
              Text(
                '${current.tempo} BPM',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _play,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(playing ? 'Detener' : 'Escuchar'),
              ),
            ],
          ),
        ),
      ],
    ));
  }

  Widget _measureCell(Score current, int index, double width) {
    final measure = current.measures[index];
    final selected = index == measureIndex;
    return Container(
      width: width,
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: selected ? accent : Colors.transparent, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(onTap: () => setState(() { measureIndex = index; selectedEvent = -1; }),
          child: SizedBox(height: 22, child: Row(children: [
            const SizedBox(width: 7),
            Text('${index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                color: selected ? accent : teal)),
            const Spacer(),
            Icon(current.status(measure) == 'Completo' ? Icons.check_circle :
                current.status(measure) == 'Excedido' ? Icons.error : Icons.circle_outlined,
              size: 13, color: current.status(measure) == 'Excedido' ? accent : teal),
            const SizedBox(width: 7),
          ]))),
        StaffView(events: measure.right, clef: current.clef, width: width,
          showClef: index % 4 == 0,
          selected: selected && !left ? selectedEvent : -1,
          active: activeMeasure == index ? activeRight : -1,
          onNote: (midi) { setState(() { measureIndex = index; left = false; }); _insert(midi); },
          onSelect: (eventIndex) { setState(() { measureIndex = index; left = false; selectedEvent = eventIndex; }); _eventSheet(); }),
        if (current.leftHand) StaffView(events: measure.left, clef: 'Fa', width: width,
          showClef: index % 4 == 0,
          selected: selected && left ? selectedEvent : -1,
          active: activeMeasure == index ? activeLeft : -1,
          onNote: (midi) { setState(() { measureIndex = index; left = true; }); _insert(midi); },
          onSelect: (eventIndex) { setState(() { measureIndex = index; left = true; selectedEvent = eventIndex; }); _eventSheet(); }),
      ]),
    );
  }

  String _figure(int value) => switch (value) {
    1 => 'Redonda',
    2 => 'Blanca',
    4 => 'Negra',
    8 => 'Corchea',
    16 => 'Semicorchea',
    32 => 'Fusa',
    _ => 'Semifusa',
  };

  Widget _metric(IconData icon, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7EFEB),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: teal),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _action(IconData icon, String text, VoidCallback? callback) =>
      OutlinedButton.icon(
        onPressed: callback,
        icon: Icon(icon, size: 17),
        label: Text(text),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );

  Widget _keyboard() => PianoKeyboard(
    activePitch: playing ? activePitch : pitch,
    onNote: (midi) { setState(() => pitch = midi); _insert(midi); },
  );

  void _settings() {
    final current = score!;
    final draft = Score.decode(current.encode());
    final title = TextEditingController(text: draft.title);
    final composer = TextEditingController(text: draft.composer);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            22,
            8,
            22,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Partitura', style: GoogleFonts.fraunces(fontSize: 27)),
                const SizedBox(height: 16),
                TextField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: composer,
                  maxLength: 120,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Compositor · cuenta Google'),
                ),
                TextButton.icon(onPressed: () async {
                  final account = await _chooseGoogleAccount();
                  if (account != null) update(() => composer.text = account);
                }, icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Elegir cuenta Google')),
                DropdownButtonFormField<String>(
                  initialValue: draft.clef,
                  decoration: const InputDecoration(labelText: 'Clave'),
                  items: ['Sol', 'Fa', 'Do 3ª', 'Do 4ª']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: (value) => update(() => draft.clef = value!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: draft.numerator,
                        decoration: const InputDecoration(
                          labelText: 'Numerador',
                        ),
                        items: List.generate(32, (index) => index + 1)
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            update(() => draft.numerator = value!),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: draft.denominator,
                        decoration: const InputDecoration(
                          labelText: 'Denominador',
                        ),
                        items: [1, 2, 4, 8, 16, 32]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            update(() => draft.denominator = value!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Armadura: ${draft.key < 0
                      ? '${-draft.key} bemoles'
                      : draft.key == 0
                      ? 'Sin alteraciones'
                      : '${draft.key} sostenidos'}',
                ),
                Slider(
                  value: draft.key.toDouble(),
                  min: -7,
                  max: 7,
                  divisions: 14,
                  onChanged: (value) => update(() => draft.key = value.round()),
                ),
                Text('Tempo: ${draft.tempo} BPM'),
                Slider(
                  value: draft.tempo.toDouble(),
                  min: 20,
                  max: 300,
                  divisions: 280,
                  onChanged: (value) =>
                      update(() => draft.tempo = value.round()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mano izquierda'),
                  value: draft.leftHand,
                  onChanged: (value) => update(() => draft.leftHand = value),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      _change(() {
                        current.title = title.text.trim().isEmpty
                            ? 'Sin título'
                            : title.text.trim();
                        current.composer = composer.text.trim();
                        current.clef = draft.clef;
                        current.numerator = draft.numerator;
                        current.denominator = draft.denominator;
                        current.key = draft.key;
                        current.tempo = draft.tempo;
                        current.leftHand = draft.leftHand;
                      });
                      Navigator.pop(context);
                    },
                    child: const Text('Guardar cambios'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _eventSheet() {
    final selected = selectedEvent;
    if (selected < 0 || selected >= _events.length) return;
    final event = _events[selected];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          void modify(VoidCallback action) {
            _change(action);
            update(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              5,
              22,
              MediaQuery.viewInsetsOf(context).bottom + 25,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.rest ? 'Silencio' : noteName(event.midi),
                    style: GoogleFonts.fraunces(fontSize: 28),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: event.value,
                          decoration: const InputDecoration(
                            labelText: 'Figura',
                          ),
                          items: [1, 2, 4, 8, 16, 32, 64]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(_figure(value)),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              modify(() => event.value = value!),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!event.rest) ...[
                        IconButton(
                          tooltip: 'Bajar semitono',
                          onPressed: () => modify(
                            () => event.midi = (event.midi - 1).clamp(0, 107),
                          ),
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          tooltip: 'Subir semitono',
                          onPressed: () => modify(
                            () => event.midi = (event.midi + 1).clamp(0, 107),
                          ),
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (!event.rest) ...[
                    DropdownButtonFormField<int>(
                      initialValue: event.accidental,
                      decoration: const InputDecoration(
                        labelText: 'Alteración',
                      ),
                      items: const [
                        DropdownMenuItem(value: 9, child: Text('Armadura')),
                        DropdownMenuItem(value: -2, child: Text('Doble bemol')),
                        DropdownMenuItem(value: -1, child: Text('Bemol')),
                        DropdownMenuItem(value: 0, child: Text('Natural')),
                        DropdownMenuItem(value: 1, child: Text('Sostenido')),
                        DropdownMenuItem(
                          value: 2,
                          child: Text('Doble sostenido'),
                        ),
                      ],
                      onChanged: (value) =>
                          modify(() => event.accidental = value!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: event.chord,
                      decoration: const InputDecoration(labelText: 'Acorde'),
                      items: chordIntervals.keys
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => modify(() => event.chord = value!),
                    ),
                    if (event.chord != 'Ninguno') ...[
                      Text('Inversión: ${event.inversion}'),
                      Slider(
                        value: event.inversion.toDouble(),
                        min: 0,
                        max: (chordIntervals[event.chord]!.length - 1)
                            .toDouble(),
                        divisions: chordIntervals[event.chord]!.length - 1,
                        onChanged: (value) =>
                            modify(() => event.inversion = value.round()),
                      ),
                    ],
                  ],
                  Row(
                    children: [
                      FilterChip(
                        label: const Text('Puntillo'),
                        selected: event.dotted,
                        onSelected: (value) =>
                            modify(() => event.dotted = value),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Ligadura'),
                        selected: event.tied,
                        onSelected: (value) => modify(() => event.tied = value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: event.dynamics,
                    decoration: const InputDecoration(labelText: 'Matiz'),
                    items: ['pp', 'p', 'mf', 'f', 'ff']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => modify(() => event.dynamics = value!),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    initialValue: event.lyric,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Letra o solfeo',
                    ),
                    onChanged: (value) => _change(() => event.lyric = value),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () {
                      _change(() {
                        _events.removeAt(selected);
                        selectedEvent = -1;
                      });
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Eliminar figura'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _learn() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 26, 22, 40),
    children: [
      Text(
        'Solfeo',
        style: GoogleFonts.fraunces(fontSize: 38, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      const Text(
        'Una referencia rápida para volver a la música.',
        style: TextStyle(color: Color(0xFF6B7772)),
      ),
      const SizedBox(height: 25),
      _lesson(
        '01',
        'Figuras y silencios',
        'Redonda 4 pulsos · blanca 2 · negra 1 · corchea ½ · semicorchea ¼ · fusa ⅛. El puntillo añade la mitad del valor. Un silencio ocupa la misma duración que su figura.',
      ),
      _lesson(
        '02',
        'Claves y armaduras',
        'La clave de sol sitúa el Sol en la segunda línea; la de fa, el Fa en la cuarta. Las claves de do señalan el Do central en la tercera o cuarta línea. La armadura indica los sostenidos o bemoles habituales de la pieza.',
      ),
      _lesson(
        '03',
        'Compás y pulso',
        'El numerador indica cuántas unidades hay por compás; el denominador, qué figura representa cada unidad. Un 4/4 admite cuatro negras. El tempo expresa pulsos por minuto.',
      ),
      _lesson(
        '04',
        'Acordes e inversiones',
        'Un acorde mayor combina fundamental, tercera mayor y quinta justa; el menor usa tercera menor. Las séptimas, novenas y suspensiones amplían esa base. Invertir cambia la nota más grave.',
      ),
      _lesson(
        '05',
        'Matices y ligaduras',
        'pp y p indican tocar suave; f y ff, más fuerte. Una ligadura conecta la duración de notas de igual altura. La letra puede acompañar cada figura en el pentagrama.',
      ),
      _lesson(
        '06',
        'El editor',
        'Elige una figura y toca el teclado o pentagrama. Toca una nota para editarla. Cambia de compás con las flechas, completa los huecos con silencios y escucha con el botón de reproducción.',
      ),
    ],
  );

  Widget _lesson(String number, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 23),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              number,
              style: const TextStyle(
                color: accent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.fraunces(
                  fontSize: 23,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Text(
            body,
            style: const TextStyle(height: 1.55, color: Color(0xFF596662)),
          ),
        ),
        const SizedBox(height: 15),
        const Divider(color: Color(0xFFD9E0DB)),
      ],
    ),
  );
}
