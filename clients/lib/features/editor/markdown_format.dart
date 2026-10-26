import 'package:flutter/services.dart';

/// Pure text-editing helpers behind the markdown toolbar of the pack editor.
/// Every function takes the field's current [TextEditingValue] and returns the
/// new one; a selection is wrapped / prefixed, a bare cursor gets the markup
/// inserted with the cursor placed where typing should continue.

enum MdWrap {
  bold('**'),
  italic('*');

  const MdWrap(this.marker);
  final String marker;
}

enum MdLine { heading, bullet, numbered, quote }

/// (start, end) of the selection, or the end of the text when there is none.
(int, int) _range(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid) return (v.text.length, v.text.length);
  final a = sel.start.clamp(0, v.text.length), b = sel.end.clamp(0, v.text.length);
  return (a, b);
}

/// Inserts [snippet] at the cursor (replacing a selection), cursor after it.
TextEditingValue insertAtCursor(TextEditingValue v, String snippet) {
  final (start, end) = _range(v);
  final next = v.text.replaceRange(start, end, snippet);
  return TextEditingValue(text: next, selection: TextSelection.collapsed(offset: start + snippet.length));
}

/// **bold** / *italic*: wraps the selection (kept selected) or inserts an
/// empty pair with the cursor inside. Wrapping an already wrapped selection
/// removes the markers.
TextEditingValue wrapSelection(TextEditingValue v, MdWrap kind) {
  final m = kind.marker;
  final (start, end) = _range(v);
  final text = v.text;
  final selected = text.substring(start, end);
  // Toggle off: markers right around the selection.
  if (selected.isNotEmpty &&
      start >= m.length &&
      end + m.length <= text.length &&
      text.substring(start - m.length, start) == m &&
      text.substring(end, end + m.length) == m &&
      // `*` must not be half of a `**`.
      !(kind == MdWrap.italic && _isBoldAround(text, start, end))) {
    final next = text.replaceRange(end, end + m.length, '').replaceRange(start - m.length, start, '');
    return TextEditingValue(
      text: next,
      selection: TextSelection(baseOffset: start - m.length, extentOffset: end - m.length),
    );
  }
  final next = text.replaceRange(start, end, '$m$selected$m');
  return TextEditingValue(
    text: next,
    selection: TextSelection(baseOffset: start + m.length, extentOffset: end + m.length),
  );
}

bool _isBoldAround(String text, int start, int end) =>
    start >= 2 && end + 2 <= text.length && text.substring(start - 2, start) == '**' && text.substring(end, end + 2) == '**';

/// Line markup (`## `, `- `, `1. `, `> `) on every line the selection touches.
/// If all those lines already carry it, it is removed instead (toggle).
TextEditingValue prefixLines(TextEditingValue v, MdLine kind) {
  final text = v.text;
  final (start, end) = _range(v);
  final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  // A selection ending right after a newline does not include the next line.
  final effEnd = end > start && text[end - 1] == '\n' ? end - 1 : end;
  final nl = text.indexOf('\n', effEnd);
  final lineEnd = nl < 0 ? text.length : nl;
  final lines = text.substring(lineStart, lineEnd).split('\n');

  final pattern = switch (kind) {
    MdLine.heading => RegExp(r'^#{1,6} '),
    MdLine.bullet => RegExp(r'^[-*+] '),
    MdLine.numbered => RegExp(r'^\d+\. '),
    MdLine.quote => RegExp(r'^> ?'),
  };
  final allHave = lines.every((l) => pattern.hasMatch(l));
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (allHave) {
      out.add(l.replaceFirst(pattern, ''));
    } else {
      final bare = l.replaceFirst(_anyLinePrefix, '');
      final prefix = switch (kind) {
        MdLine.heading => '## ',
        MdLine.bullet => '- ',
        MdLine.numbered => '${i + 1}. ',
        MdLine.quote => '> ',
      };
      out.add('$prefix$bare');
    }
  }
  final block = out.join('\n');
  final next = text.replaceRange(lineStart, lineEnd, block);
  final delta = block.length - (lineEnd - lineStart);
  if (start == end && lines.length == 1) {
    // Bare cursor: keep it at the same place in the line's content.
    final oldPrefix = lines.first.length - lines.first.replaceFirst(allHave ? pattern : _anyLinePrefix, '').length;
    final newPrefix = out.first.length - (lines.first.length - oldPrefix);
    final col = (start - lineStart - oldPrefix).clamp(0, lines.first.length);
    final offset = (lineStart + newPrefix + col).clamp(lineStart, lineStart + out.first.length);
    return TextEditingValue(text: next, selection: TextSelection.collapsed(offset: offset));
  }
  return TextEditingValue(
    text: next,
    selection: TextSelection(baseOffset: lineStart, extentOffset: lineEnd + delta),
  );
}

/// Any existing block prefix: replaced when a different kind is applied.
final _anyLinePrefix = RegExp(r'^(#{1,6} |[-*+] |\d+\. |> ?)');

/// `[text](url)`: the selection (or [label], or «ссылка») becomes the text;
/// the cursor goes after the link.
TextEditingValue insertLink(TextEditingValue v, String url, {String? label}) {
  final (start, end) = _range(v);
  final selected = v.text.substring(start, end);
  final text = (label != null && label.trim().isNotEmpty)
      ? label.trim()
      : (selected.isNotEmpty ? selected : 'ссылка');
  return insertAtCursor(v, '[$text](${url.trim()})');
}

/// `![](media:<name>)` at the cursor (the block splitter turns it into a media block).
TextEditingValue insertMedia(TextEditingValue v, String name) => insertAtCursor(v, '![](media:$name)');
