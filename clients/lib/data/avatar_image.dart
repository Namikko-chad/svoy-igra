import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Crops a picture to a centred square, scales it to at most [max]×[max] and
/// encodes it as JPEG (protocol §2.1 Avatars). Returns null for undecodable data.
/// Pure and synchronous — run it with `compute` for large photos.
Uint8List? squareAvatar(Uint8List bytes, {int max = 512, int quality = 85}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  final side = oriented.width < oriented.height ? oriented.width : oriented.height;
  final square = img.copyCrop(
    oriented,
    x: (oriented.width - side) ~/ 2,
    y: (oriented.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final out = side > max
      ? img.copyResize(square, width: max, height: max, interpolation: img.Interpolation.average)
      : square;
  return Uint8List.fromList(img.encodeJpg(out, quality: quality));
}

/// Initials for the avatar fallback: first letters of up to two words.
String initials(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  final first = words.first.characters.first;
  final second = words.length > 1 ? words[1].characters.first : '';
  return (first + second).toUpperCase();
}

extension on String {
  /// Grapheme-safe enough for names: the first code point.
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
