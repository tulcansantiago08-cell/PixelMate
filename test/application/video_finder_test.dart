import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/video_finder.dart';

void main() {
  test('toma el primer video (no anuncios) y su título', () {
    const html = r'''
      ..."adSlotRenderer":{"x":1}..."promotedVideoRenderer":{"videoId":"AAAAAAAAAAA"}
      ..."videoRenderer":{"videoId":"Cr8K88UcO0s","thumbnail":{},"title":{"runs":[{"text":"Bad Bunny - Tití Me Preguntó (Video Oficial) & más"}]}}
      ..."videoRenderer":{"videoId":"qBUKfQRbzuk","title":{"runs":[{"text":"Otro"}]}}
    ''';
    final v = parseFirstVideo(html)!;
    expect(v.id, 'Cr8K88UcO0s');
    expect(v.title, 'Bad Bunny - Tití Me Preguntó (Video Oficial) & más');
    expect(
        v.watchUrl.toString(), 'https://www.youtube.com/watch?v=Cr8K88UcO0s');
  });

  test('lee la duración del video', () {
    const html = r'''
      "videoRenderer":{"videoId":"Cr8K88UcO0s","title":{"runs":[{"text":"Canción"}]},"lengthText":{"accessibility":{"accessibilityData":{"label":"4 minutos y 21 segundos"}},"simpleText":"4:21"}}
    ''';
    expect(
        parseFirstVideo(html)!.length, const Duration(minutes: 4, seconds: 21));
    expect(parseVideoLength('1:02:03'),
        const Duration(hours: 1, minutes: 2, seconds: 3));
    expect(parseVideoLength('x:10'), isNull);
    expect(
        parseFirstVideo(
                '"videoRenderer":{"videoId":"Cr8K88UcO0s","title":{"runs":[{"text":"A"}]}}')!
            .length,
        isNull);
  });

  test('sin resultados, nada', () {
    expect(parseFirstVideo('<html>sin videos</html>'), isNull);
  });
}
