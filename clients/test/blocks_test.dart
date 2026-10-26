import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/data/blocks.dart';
import 'package:svoy_igra_client/data/models.dart';

void main() {
  group('splitBlocks', () {
    test('protocol example', () {
      const md = 'Кто изображён на фото?\n\n![](media:portrait.jpg)\n\nПослушайте отрывок: ![гимн](media:anthem.mp3)';
      expect(splitBlocks('p1', md), const [
        Block.text('Кто изображён на фото?'),
        Block.media(BlockType.image, '/api/packs/p1/media/portrait.jpg', ''),
        Block.text('Послушайте отрывок:'),
        Block.media(BlockType.audio, '/api/packs/p1/media/anthem.mp3', 'гимн'),
      ]);
    });

    test('plain text is one trimmed block, empty text dropped', () {
      expect(splitBlocks('p', '  Просто текст  \n'), const [Block.text('Просто текст')]);
      expect(splitBlocks('p', '   '), isEmpty);
      expect(splitBlocks('p', '![](media:a.png)![](media:b.mp4)'), const [
        Block.media(BlockType.image, '/api/packs/p/media/a.png', ''),
        Block.media(BlockType.video, '/api/packs/p/media/b.mp4', ''),
      ]);
    });

    test('http urls, titles and angle brackets', () {
      expect(splitBlocks('p', 'a ![x](https://e.com/v.WEBM?t=1 "title") b ![](<media:c.ogg>)'), const [
        Block.text('a'),
        Block.media(BlockType.video, 'https://e.com/v.WEBM?t=1', 'x'),
        Block.text('b'),
        Block.media(BlockType.audio, '/api/packs/p/media/c.ogg', ''),
      ]);
    });

    test('links are not media', () {
      expect(splitBlocks('p', '[ссылка](http://x)'), const [Block.text('[ссылка](http://x)')]);
    });

    test('pack id and name are path-escaped like Go url.PathEscape', () {
      expect(mediaUrl('a b/c', 'x y.png'), '/api/packs/a%20b%2Fc/media/x%20y.png');
      expect(pathEscape('a-b_c.d~e:f@g'), 'a-b_c.d~e:f@g');
    });
  });

  group('mediaKind', () {
    test('by extension, case-insensitive, unknown → image', () {
      expect(mediaKind('a.MP3'), BlockType.audio);
      expect(mediaKind('a.flac'), BlockType.audio);
      expect(mediaKind('a.mkv'), BlockType.video);
      expect(mediaKind('a.svg'), BlockType.image);
      expect(mediaKind('a.txt'), BlockType.image);
      expect(mediaKind('noext'), BlockType.image);
      expect(mediaKind('dir.mp4/file'), BlockType.image);
      expect(mediaKind('http://x/y.mov#t=2'), BlockType.video);
    });
  });
}
