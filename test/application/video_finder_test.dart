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

  test('sin resultados, nada', () {
    expect(parseFirstVideo('<html>sin videos</html>'), isNull);
  });
}
