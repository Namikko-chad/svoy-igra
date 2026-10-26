import 'json.dart';

enum BlockType { text, image, video, audio }

/// One piece of a question/answer, already split by the server (protocol §3).
class Block {
  const Block.text(this.markdown)
      : type = BlockType.text,
        url = '',
        alt = '';

  const Block.media(this.type, this.url, this.alt) : markdown = '';

  final BlockType type;

  /// Markdown with media references removed (`text` blocks only).
  final String markdown;

  /// Server-relative (`/api/packs/...`) or absolute URL (media blocks only).
  final String url;
  final String alt;

  bool get isMedia => type != BlockType.text;

  factory Block.fromJson(Json json) {
    switch (asString(json['type'])) {
      case 'image':
        return Block.media(BlockType.image, asString(json['url']), asString(json['alt']));
      case 'video':
        return Block.media(BlockType.video, asString(json['url']), asString(json['alt']));
      case 'audio':
        return Block.media(BlockType.audio, asString(json['url']), asString(json['alt']));
      default:
        return Block.text(asString(json['markdown']));
    }
  }

  static List<Block> listFromJson(Object? v) => asList(v, (e) => Block.fromJson(asJson(e)));
}
