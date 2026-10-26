import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/core/format.dart';
import 'package:svoy_igra_client/data/discovery.dart';
import 'package:svoy_igra_client/features/editor/markdown_format.dart';
import 'package:svoy_igra_client/features/editor/pack_editor_model.dart';

void main() {
  test('formatDateTime is local ISO YYYY-MM-DD HH:MM:SS', () {
    final local = DateTime(2026, 6, 15, 14, 30, 5);
    expect(formatDateTime(local.millisecondsSinceEpoch), '2026-06-15 14:30:05');
    expect(formatDateTime(null), '—');
  });

  test('formatScore', () {
    expect(formatScore(1500), '1 500');
    expect(formatScore(-300), '−300');
    expect(formatScore(0), '0');
  });

  test('normalizeBaseUrl', () {
    expect(normalizeBaseUrl('192.168.1.10:3050'), 'http://192.168.1.10:3050');
    expect(normalizeBaseUrl('http://192.168.1.10:3050/'), 'http://192.168.1.10:3050');
    expect(normalizeBaseUrl('192.168.1.10'), 'http://192.168.1.10:3050');
    expect(normalizeBaseUrl('https://quiz.example'), 'https://quiz.example');
    expect(normalizeBaseUrl(''), isNull);
    expect(normalizeBaseUrl('ftp://x'), isNull);
  });

  test('sanitizeMediaName', () {
    expect(sanitizeMediaName('Фото 1.JPG'), 'Foto_1.JPG');
    expect(sanitizeMediaName('.hidden.png'), 'hidden.png');
    expect(sanitizeMediaName('ok-name_1.mp3'), 'ok-name_1.mp3');
    expect(sanitizeMediaName('!!!'), '_');
    expect(sanitizeMediaName('${'a' * 200}.png').length, 128);
    expect(sanitizeMediaName('${'a' * 200}.png'), endsWith('.png'));
  });

  test('insertAtCursor', () {
    const v = TextEditingValue(text: 'ab', selection: TextSelection.collapsed(offset: 1));
    final r = insertAtCursor(v, 'X');
    expect(r.text, 'aXb');
    expect(r.selection.baseOffset, 2);
    final end = insertAtCursor(const TextEditingValue(text: 'ab'), '!');
    expect(end.text, 'ab!');
  });
}
