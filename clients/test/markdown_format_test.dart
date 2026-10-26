import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/features/editor/markdown_format.dart';

TextEditingValue v(String text, int start, [int? end]) =>
    TextEditingValue(text: text, selection: TextSelection(baseOffset: start, extentOffset: end ?? start));

String sel(TextEditingValue x) => x.selection.textInside(x.text);

void main() {
  group('wrapSelection', () {
    test('wraps the selection and keeps it selected', () {
      final r = wrapSelection(v('one two three', 4, 7), MdWrap.bold);
      expect(r.text, 'one **two** three');
      expect(sel(r), 'two');
      final i = wrapSelection(v('one two', 4, 7), MdWrap.italic);
      expect(i.text, 'one *two*');
      expect(sel(i), 'two');
    });

    test('empty selection inserts a pair with the cursor inside', () {
      final r = wrapSelection(v('ab', 1), MdWrap.bold);
      expect(r.text, 'a****b');
      expect(r.selection.baseOffset, 3);
      expect(r.selection.isCollapsed, isTrue);
    });

    test('toggles off when already wrapped', () {
      final on = wrapSelection(v('x two y', 2, 5), MdWrap.bold);
      final off = wrapSelection(on, MdWrap.bold);
      expect(off.text, 'x two y');
      expect(sel(off), 'two');
    });

    test('italic inside bold adds markers instead of eating bold', () {
      final r = wrapSelection(v('**two**', 2, 5), MdWrap.italic);
      expect(r.text, '***two***');
    });

    test('no selection info → appends at the end', () {
      final r = wrapSelection(const TextEditingValue(text: 'ab'), MdWrap.italic);
      expect(r.text, 'ab**');
      expect(r.selection.baseOffset, 3);
    });
  });

  group('prefixLines', () {
    test('heading on the cursor line, cursor keeps its place in the content', () {
      final r = prefixLines(v('first\nsecond', 8), MdLine.heading);
      expect(r.text, 'first\n## second');
      expect(r.selection.baseOffset, 11);
    });

    test('bullet / quote on every selected line', () {
      final r = prefixLines(v('a\nb\nc', 0, 3), MdLine.bullet);
      expect(r.text, '- a\n- b\nc');
      expect(sel(r), '- a\n- b');
      final q = prefixLines(v('a\nb', 0, 3), MdLine.quote);
      expect(q.text, '> a\n> b');
    });

    test('numbered list counts lines', () {
      final r = prefixLines(v('a\nb\nc', 0, 5), MdLine.numbered);
      expect(r.text, '1. a\n2. b\n3. c');
    });

    test('toggles off and replaces another prefix', () {
      final off = prefixLines(v('- a\n- b', 0, 7), MdLine.bullet);
      expect(off.text, 'a\nb');
      final swap = prefixLines(v('- a', 1), MdLine.numbered);
      expect(swap.text, '1. a');
      final h = prefixLines(v('## T', 4), MdLine.heading);
      expect(h.text, 'T');
      expect(h.selection.baseOffset, 1);
    });

    test('selection ending after a newline does not take the next line', () {
      final r = prefixLines(v('a\nb', 0, 2), MdLine.bullet);
      expect(r.text, '- a\nb');
    });

    test('empty text', () {
      final r = prefixLines(v('', 0), MdLine.bullet);
      expect(r.text, '- ');
      expect(r.selection.baseOffset, 2);
    });
  });

  group('links and media', () {
    test('link uses the selection as text', () {
      final r = insertLink(v('see here now', 4, 8), 'https://x.ru');
      expect(r.text, 'see [here](https://x.ru) now');
      expect(r.selection.baseOffset, 24);
    });

    test('link label wins, default text otherwise', () {
      expect(insertLink(v('', 0), 'http://a', label: 'Сайт').text, '[Сайт](http://a)');
      expect(insertLink(v('', 0), 'http://a').text, '[ссылка](http://a)');
    });

    test('media at the cursor', () {
      final r = insertMedia(v('ab', 1), 'pic.png');
      expect(r.text, 'a![](media:pic.png)b');
      expect(r.selection.baseOffset, 19);
    });
  });
}
