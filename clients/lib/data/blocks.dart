import 'dart:convert';

import 'models.dart';

/// Block splitting, identical to the server's rule (protocol §3): every
/// `![alt](src)` becomes a media block at its position, the trimmed text
/// between occurrences becomes a `text` block, empty text is dropped.
/// The editor preview uses this; during a game the server sends blocks.

final RegExp mediaRef = RegExp(r'!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)');

const _videoExt = {'mp4', 'webm', 'mov', 'm4v', 'mkv'};
const _audioExt = {'mp3', 'ogg', 'oga', 'wav', 'm4a', 'aac', 'flac', 'opus'};

/// Media kind by file extension (case-insensitive); anything unknown is an image.
BlockType mediaKind(String src) {
  final cut = src.indexOf(RegExp(r'[?#]'));
  if (cut >= 0) src = src.substring(0, cut);
  final slash = src.lastIndexOf('/');
  final dot = src.lastIndexOf('.');
  final ext = dot > slash ? src.substring(dot + 1).toLowerCase() : '';
  if (_videoExt.contains(ext)) return BlockType.video;
  if (_audioExt.contains(ext)) return BlockType.audio;
  return BlockType.image;
}

/// Path-segment escaping compatible with Go's `url.PathEscape`.
String pathEscape(String s) {
  final out = StringBuffer();
  for (final b in utf8.encode(s)) {
    final c = String.fromCharCode(b);
    final unreserved = (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || (b >= 0x30 && b <= 0x39);
    if (unreserved || '-_.~\$&+:=@'.contains(c)) {
      out.write(c);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

/// Relative URL of a pack media file.
String mediaUrl(String packId, String name) => '/api/packs/${pathEscape(packId)}/media/${pathEscape(name)}';

List<Block> splitBlocks(String packId, String markdown) {
  final blocks = <Block>[];
  void addText(String s) {
    s = s.trim();
    if (s.isNotEmpty) blocks.add(Block.text(s));
  }

  var last = 0;
  for (final m in mediaRef.allMatches(markdown)) {
    addText(markdown.substring(last, m.start));
    final alt = m.group(1)!;
    final src = m.group(2)!;
    final url = src.startsWith('media:') ? mediaUrl(packId, src.substring('media:'.length)) : src;
    blocks.add(Block.media(mediaKind(src), url, alt));
    last = m.end;
  }
  addText(markdown.substring(last));
  return blocks;
}
