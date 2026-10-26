import 'block.dart';

const _imageExt = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'svg', 'bmp'};
const _videoExt = {'mp4', 'webm', 'mov', 'm4v', 'mkv'};
const _audioExt = {'mp3', 'ogg', 'oga', 'wav', 'm4a', 'aac', 'flac', 'opus'};

final _mediaRef = RegExp(r'!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)');

/// Media kind by file extension (protocol §3); unknown → image.
BlockType mediaKind(String src) {
  var path = src;
  final cut = path.indexOf(RegExp('[?#]'));
  if (cut >= 0) path = path.substring(0, cut);
  final dot = path.lastIndexOf('.');
  final ext = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  if (_videoExt.contains(ext)) return BlockType.video;
  if (_audioExt.contains(ext)) return BlockType.audio;
  if (_imageExt.contains(ext)) return BlockType.image;
  return BlockType.image;
}

/// `media:<name>` → `/api/packs/{packId}/media/{name}`; other URLs unchanged.
String mediaUrl(String src, String packId) {
  if (!src.startsWith('media:')) return src;
  final name = src.substring('media:'.length);
  return '/api/packs/${Uri.encodeComponent(packId)}/media/${Uri.encodeComponent(name)}';
}

/// Splits markdown into blocks exactly like the server does for questions
/// (protocol §3). The server pre-splits question/answer; the TV uses this for
/// the reveal `comment`, which arrives as plain markdown.
List<Block> splitBlocks(String markdown, {required String packId}) {
  final blocks = <Block>[];
  var last = 0;
  void addText(String text) {
    final t = text.trim();
    if (t.isNotEmpty) blocks.add(Block.text(t));
  }

  for (final m in _mediaRef.allMatches(markdown)) {
    addText(markdown.substring(last, m.start));
    final src = m.group(2)!;
    blocks.add(Block.media(mediaKind(src), mediaUrl(src, packId), m.group(1) ?? ''));
    last = m.end;
  }
  addText(markdown.substring(last));
  return blocks;
}
