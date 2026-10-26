String _two(int v) => v.toString().padLeft(2, '0');

/// Unix ms (UTC) → `YYYY-MM-DD HH:MM:SS` in the device's local time zone.
String formatDateTime(int? ms) {
  if (ms == null) return '—';
  final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  return '${d.year}-${_two(d.month)}-${_two(d.day)} '
      '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

/// Local timestamp for file names: `YYYYMMDD-HHMMSS`.
String fileStamp(DateTime d) =>
    '${d.year}${_two(d.month)}${_two(d.day)}-${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  const units = ['КБ', 'МБ', 'ГБ'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 ? 0 : 1)} ${units[i]}';
}

String formatMs(int? ms) => ms == null ? '—' : '$ms мс';

/// Score with a thin space as thousands separator and a real minus sign.
String formatScore(int score) {
  final s = score.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return score < 0 ? '−$buf' : buf.toString();
}

/// Russian plural: 1 вопрос, 2 вопроса, 5 вопросов.
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}
