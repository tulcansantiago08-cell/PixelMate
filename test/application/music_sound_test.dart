import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/assistant/video_finder.dart';
import 'package:pixelmate/application/mascot/music.dart';

void main() {
  const video = FoundVideo('abc', 'Mix', length: Duration(minutes: 4));

  MusicController make(bool Function() sounding) => MusicController(
        const Stream.empty(),
        audioPlaying: () async => sounding(),
        checkEvery: const Duration(milliseconds: 10),
        startWithin: const Duration(milliseconds: 40),
        stopAfterSilence: const Duration(milliseconds: 30),
      );

  test('si el video no llega a sonar, deja de bailar y lo dice', () async {
    final music = make(() => false);
    addTearDown(music.dispose);
    music.playedByAssistant(video);
    expect(music.state.playing, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(music.state.playing, isFalse);
    expect(music.videoDidNotStart, isTrue);
  });

  test('baila mientras suena y para cuando se calla', () async {
    var sounding = true;
    final music = make(() => sounding);
    addTearDown(music.dispose);
    music.playedByAssistant(video);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(music.state.playing, isTrue, reason: 'sigue sonando');
    sounding = false;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(music.state.playing, isFalse);
    expect(music.videoDidNotStart, isFalse);
  });

  test('«pon música en YouTube» pone una mezcla de música', () {
    for (final s in [
      'pon música en youtube',
      'Oye James, pon música en YouTube',
      'reproduce una canción en youtube',
    ]) {
      final c = parseCommand(s, DateTime(2026, 11, 22), petName: 'James')!;
      expect((
        c.intent,
        c.text,
        c.searchIn,
        c.play
      ), (
        AssistantIntent.open,
        'música mix',
        'youtube',
        true
      ), reason: s);
    }
    final named =
        parseCommand('pon Despacito en YouTube', DateTime(2026, 11, 22))!;
    expect(named.text, 'Despacito');
  });
}
