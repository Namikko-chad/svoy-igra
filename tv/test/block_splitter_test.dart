import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/data/models/block.dart';
import 'package:svoy_igra_tv/data/models/block_splitter.dart';

void main() {
  test('splits the protocol §3 example in document order', () {
    const md = 'Кто изображён на фото?\n\n![](media:portrait.jpg)\n\n'
        'Послушайте отрывок: ![гимн](media:anthem.mp3)';
    final blocks = splitBlocks(md, packId: 'pk_1');

    expect(blocks.map((b) => b.type), [
      BlockType.text,
      BlockType.image,
      BlockType.text,
      BlockType.audio,
    ]);
    expect(blocks[0].markdown, 'Кто изображён на фото?');
    expect(blocks[1].url, '/api/packs/pk_1/media/portrait.jpg');
    expect(blocks[2].markdown, 'Послушайте отрывок:');
    expect(blocks[3].alt, 'гимн');
    expect(blocks[3].url, '/api/packs/pk_1/media/anthem.mp3');
  });

  test('drops empty text and keeps absolute URLs', () {
    final blocks = splitBlocks('  ![](https://x.org/a.MP4)  ', packId: 'p');
    expect(blocks, hasLength(1));
    expect(blocks.single.type, BlockType.video);
    expect(blocks.single.url, 'https://x.org/a.MP4');
  });

  test('media kind by extension, unknown is image', () {
    expect(mediaKind('a.webm'), BlockType.video);
    expect(mediaKind('a.FLAC'), BlockType.audio);
    expect(mediaKind('a.svg'), BlockType.image);
    expect(mediaKind('a.bin'), BlockType.image);
    expect(mediaKind('noext'), BlockType.image);
    expect(mediaKind('https://h/x.mp3?v=1'), BlockType.audio);
  });

  test('plain text is one block', () {
    final blocks = splitBlocks('Просто **текст**', packId: 'p');
    expect(blocks.single.markdown, 'Просто **текст**');
  });
}
