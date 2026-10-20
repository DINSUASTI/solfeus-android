import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class MusicEvent {
  MusicEvent({
    this.midi = 60,
    this.value = 4,
    this.rest = false,
    this.dotted = false,
    this.tied = false,
    this.accidental = 9,
    this.chord = 'Ninguno',
    this.inversion = 0,
    this.dynamics = 'mf',
    this.lyric = '',
  });

  int midi;
  int value;
  bool rest;
  bool dotted;
  bool tied;
  int accidental;
  String chord;
  int inversion;
  String dynamics;
  String lyric;

  double get beats => (4 / value) * (dotted ? 1.5 : 1);

  Map<String, dynamic> toJson() => {
    'midi': midi,
    'value': value,
    'rest': rest,
    'dotted': dotted,
    'tied': tied,
    'accidental': accidental,
    'chord': chord,
    'inversion': inversion,
    'dynamics': dynamics,
    'lyric': lyric,
  };

  factory MusicEvent.fromJson(Map<String, dynamic> json) => MusicEvent(
    midi: json['midi'] as int? ?? 60,
    value: json['value'] as int? ?? 4,
    rest: json['rest'] as bool? ?? false,
    dotted: json['dotted'] as bool? ?? false,
    tied: json['tied'] as bool? ?? false,
    accidental: json['accidental'] as int? ?? 9,
    chord: json['chord'] as String? ?? 'Ninguno',
    inversion: json['inversion'] as int? ?? 0,
    dynamics: json['dynamics'] as String? ?? 'mf',
    lyric: json['lyric'] as String? ?? '',
  );
}

class Measure {
  Measure({List<MusicEvent>? right, List<MusicEvent>? left})
    : right = right ?? [],
      left = left ?? [];

  List<MusicEvent> right;
  List<MusicEvent> left;

  double beats(bool leftHand) =>
      (leftHand ? left : right).fold(0, (sum, event) => sum + event.beats);

  Map<String, dynamic> toJson() => {
    'right': right.map((event) => event.toJson()).toList(),
    'left': left.map((event) => event.toJson()).toList(),
  };

  factory Measure.fromJson(Map<String, dynamic> json) => Measure(
    right: (json['right'] as List? ?? [])
        .map(
          (event) =>
              MusicEvent.fromJson(Map<String, dynamic>.from(event as Map)),
        )
        .toList(),
    left: (json['left'] as List? ?? [])
        .map(
          (event) =>
              MusicEvent.fromJson(Map<String, dynamic>.from(event as Map)),
        )
        .toList(),
  );
}

class Score {
  Score({
    this.id,
    this.title = 'Sin título',
    this.composer = '',
    this.clef = 'Sol',
    this.key = 0,
    this.numerator = 4,
    this.denominator = 4,
    this.tempo = 96,
    this.leftHand = false,
    List<Measure>? measures,
    DateTime? updated,
  }) : measures = measures ?? [Measure()],
       updated = updated ?? DateTime.now();

  int? id;
  String title;
  String composer;
  String clef;
  int key;
  int numerator;
  int denominator;
  int tempo;
  bool leftHand;
  List<Measure> measures;
  DateTime updated;

  double get capacity => numerator * 4 / denominator;

  String status(Measure measure, {bool left = false}) {
    final used = measure.beats(left);
    if (used > capacity + 0.0001) return 'Excedido';
    if ((used - capacity).abs() < 0.0001) return 'Completo';
    return 'Incompleto';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'composer': composer,
    'clef': clef,
    'key': key,
    'numerator': numerator,
    'denominator': denominator,
    'tempo': tempo,
    'leftHand': leftHand,
    'measures': measures.map((measure) => measure.toJson()).toList(),
    'updated': updated.toIso8601String(),
  };

  String encode() => jsonEncode(toJson());

  factory Score.decode(String source) =>
      Score.fromJson(jsonDecode(source) as Map<String, dynamic>);

  factory Score.fromJson(Map<String, dynamic> json) => Score(
    id: json['id'] as int?,
    title: json['title'] as String? ?? 'Sin título',
    composer: json['composer'] as String? ?? '',
    clef: json['clef'] as String? ?? 'Sol',
    key: json['key'] as int? ?? 0,
    numerator: json['numerator'] as int? ?? 4,
    denominator: json['denominator'] as int? ?? 4,
    tempo: json['tempo'] as int? ?? 96,
    leftHand: json['leftHand'] as bool? ?? false,
    measures: (json['measures'] as List? ?? [])
        .map(
          (measure) =>
              Measure.fromJson(Map<String, dynamic>.from(measure as Map)),
        )
        .toList(),
    updated:
        DateTime.tryParse(json['updated'] as String? ?? '') ?? DateTime.now(),
  );
}

const noteNames = [
  'Do',
  'Do♯',
  'Re',
  'Mi♭',
  'Mi',
  'Fa',
  'Fa♯',
  'Sol',
  'Sol♯',
  'La',
  'Si♭',
  'Si',
];
String noteName(int midi) => '${noteNames[midi % 12]}${midi ~/ 12 - 1}';

const chordIntervals = <String, List<int>>{
  'Ninguno': [0],
  'Mayor': [0, 4, 7],
  'Menor': [0, 3, 7],
  'Disminuido': [0, 3, 6],
  'Aumentado': [0, 4, 8],
  '7 dominante': [0, 4, 7, 10],
  '7 mayor': [0, 4, 7, 11],
  '7 menor': [0, 3, 7, 10],
  '9': [0, 4, 7, 10, 14],
  'Sus2': [0, 2, 7],
  'Sus4': [0, 5, 7],
  '7♭5': [0, 4, 6, 10],
};

int soundingMidi(MusicEvent event, int key) {
  if (event.accidental != 9) {
    return (event.midi + event.accidental).clamp(0, 127);
  }
  const sharps = [5, 0, 7, 2, 9, 4, 11];
  const flats = [11, 4, 9, 2, 7, 0, 5];
  final pitchClass = event.midi % 12;
  if (key > 0 && sharps.take(key).contains(pitchClass)) return event.midi + 1;
  if (key < 0 && flats.take(-key).contains(pitchClass)) return event.midi - 1;
  return event.midi;
}

List<int> pitches(MusicEvent event, [int key = 0]) {
  final intervals = [
    ...(chordIntervals[event.chord] ?? [0]),
  ];
  for (var index = 0; index < event.inversion % intervals.length; index++) {
    intervals[index] += 12;
  }
  return intervals
      .map((interval) => (soundingMidi(event, key) + interval).clamp(0, 127))
      .toList();
}

Uint8List renderWav(Score score, {bool metronome = false}) {
  const sampleRate = 22050;
  final measureSeconds = score.capacity * 60 / score.tempo;
  final totalSamples =
      (score.measures.length * measureSeconds * sampleRate).ceil() + sampleRate;
  final samples = Float32List(totalSamples);

  void renderVoice(List<MusicEvent> events, double start) {
    var time = start;
    for (var eventIndex = 0; eventIndex < events.length; eventIndex++) {
      final event = events[eventIndex];
      var duration = event.beats * 60 / score.tempo;
      while (event.tied &&
          eventIndex + 1 < events.length &&
          !events[eventIndex + 1].rest &&
          events[eventIndex + 1].midi == event.midi) {
        eventIndex++;
        duration += events[eventIndex].beats * 60 / score.tempo;
        if (!events[eventIndex].tied) break;
      }
      if (!event.rest) {
        final amplitude = switch (event.dynamics) {
          'pp' => 0.12,
          'p' => 0.19,
          'f' => 0.38,
          'ff' => 0.48,
          _ => 0.28,
        };
        final notes = pitches(event, score.key);
        for (final midi in notes) {
          final frequency = 440 * pow(2, (midi - 69) / 12);
          final startSample = (time * sampleRate).round();
          final length = (duration * sampleRate).round();
          for (
            var index = 0;
            index < length && startSample + index < totalSamples;
            index++
          ) {
            final seconds = index / sampleRate;
            final envelope =
                min(1.0, seconds * 90) *
                exp(-2.5 * seconds / max(duration, 0.08)) *
                min(1.0, (duration - seconds) * 28);
            final phase = 2 * pi * frequency * seconds;
            samples[startSample + index] +=
                amplitude *
                envelope /
                notes.length *
                (sin(phase) + 0.32 * sin(2 * phase) + 0.13 * sin(3 * phase));
          }
        }
      }
      time += duration;
    }
  }

  for (
    var measureIndex = 0;
    measureIndex < score.measures.length;
    measureIndex++
  ) {
    final start = measureIndex * measureSeconds;
    final measure = score.measures[measureIndex];
    renderVoice(measure.right, start);
    if (score.leftHand) renderVoice(measure.left, start);
    if (metronome) {
      for (var beat = 0; beat < score.numerator; beat++) {
        final offset =
            ((start + beat * 60 / score.tempo * 4 / score.denominator) *
                    sampleRate)
                .round();
        for (
          var index = 0;
          index < 850 && offset + index < totalSamples;
          index++
        ) {
          samples[offset + index] +=
              0.15 *
              exp(-index / 180) *
              sin(2 * pi * (beat == 0 ? 1100 : 850) * index / sampleRate);
        }
      }
    }
  }

  final dataSize = totalSamples * 2;
  final bytes = ByteData(44 + dataSize);
  void tag(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + dataSize, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, dataSize, Endian.little);
  for (var index = 0; index < totalSamples; index++) {
    bytes.setInt16(
      44 + index * 2,
      (samples[index].clamp(-1.0, 1.0) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
