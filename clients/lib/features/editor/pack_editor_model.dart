import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../data/api.dart';
import '../../data/models.dart';

/// State of the pack being edited. Every mutation applies the server's
/// answer to the local tree — it never re-fetches the whole pack.
class PackEditorModel extends ChangeNotifier {
  PackEditorModel(this.api, this.packId);

  final Api api;
  final String packId;

  Pack? pack;
  String? error;

  Future<void> load() async {
    try {
      pack = await api.getPack(packId);
      error = null;
    } on ApiException catch (e) {
      error = e.text;
    }
    notifyListeners();
  }

  Pack get _p => pack!;

  Round? round(int id) => _p.rounds.where((r) => r.id == id).firstOrNull;

  /// The round a category belongs to.
  Round? roundOf(int categoryId) {
    for (final r in _p.rounds) {
      if (r.categories.any((c) => c.id == categoryId)) return r;
    }
    return null;
  }

  Category? category(int id) {
    for (final r in _p.rounds) {
      for (final c in r.categories) {
        if (c.id == id) return c;
      }
    }
    return null;
  }

  // ---------------------------------------------------------- meta

  Future<void> updateMeta({required String title, required String author, required String description}) async {
    final s = await api.updatePack(packId, title: title, author: author, description: description);
    _p
      ..title = s.title
      ..author = s.author
      ..description = s.description
      ..updatedAt = s.updatedAt
      ..sizeBytes = s.sizeBytes;
    notifyListeners();
  }

  // ---------------------------------------------------------- reorder helper

  /// Moves [from] → [to] (indices in the final list) and renumbers positions.
  static void _move<T>(List<T> list, int from, int to, void Function(T, int) setPos) {
    final item = list.removeAt(from);
    list.insert(to, item);
    for (var i = 0; i < list.length; i++) {
      setPos(list[i], i);
    }
  }

  // ---------------------------------------------------------- rounds

  Future<Round> addRound(String name) async {
    final r = await api.createRound(packId, name);
    _p.rounds.add(r);
    notifyListeners();
    return r;
  }

  Future<void> renameRound(Round r, String name) async {
    final res = await api.updateRound(packId, r.id, name: name);
    r.name = res.name;
    notifyListeners();
  }

  /// Switches a round between normal and final (`409 final_one_question` when
  /// a theme has more than one question).
  Future<void> setRoundFinal(Round r, bool isFinal) async {
    final res = await api.updateRound(packId, r.id, isFinal: isFinal);
    r.isFinal = res.isFinal;
    notifyListeners();
  }

  Future<void> deleteRound(Round r) async {
    await api.deleteRound(packId, r.id);
    _p.rounds.remove(r);
    for (var i = 0; i < _p.rounds.length; i++) {
      _p.rounds[i].position = i;
    }
    notifyListeners();
  }

  Future<void> moveRound(int from, int to) async {
    if (from == to) return;
    final r = _p.rounds[from];
    _move(_p.rounds, from, to, (x, i) => x.position = i);
    notifyListeners();
    try {
      await api.updateRound(packId, r.id, position: to);
    } catch (_) {
      _move(_p.rounds, to, from, (x, i) => x.position = i);
      notifyListeners();
      rethrow;
    }
  }

  // ---------------------------------------------------------- categories

  Future<Category> addCategory(Round r, String name) async {
    final c = await api.createCategory(packId, r.id, name);
    r.categories.add(c);
    notifyListeners();
    return c;
  }

  Future<void> renameCategory(Category c, String name) async {
    final res = await api.updateCategory(packId, c.id, name: name);
    c.name = res.name;
    notifyListeners();
  }

  Future<void> deleteCategory(Round r, Category c) async {
    await api.deleteCategory(packId, c.id);
    r.categories.remove(c);
    for (var i = 0; i < r.categories.length; i++) {
      r.categories[i].position = i;
    }
    notifyListeners();
  }

  Future<void> moveCategory(Round r, int from, int to) async {
    if (from == to) return;
    final c = r.categories[from];
    _move(r.categories, from, to, (x, i) => x.position = i);
    notifyListeners();
    try {
      await api.updateCategory(packId, c.id, position: to);
    } catch (_) {
      _move(r.categories, to, from, (x, i) => x.position = i);
      notifyListeners();
      rethrow;
    }
  }

  // ---------------------------------------------------------- questions

  /// Creates ([existing] == null) or updates a question from a `QuestionInput`.
  Future<Question> saveQuestion(Category c, Question? existing, Json input) async {
    if (existing == null) {
      final q = await api.createQuestion(packId, c.id, input);
      c.questions.add(q);
      notifyListeners();
      return q;
    }
    final q = await api.updateQuestion(packId, existing.id, input);
    final i = c.questions.indexWhere((x) => x.id == existing.id);
    if (i >= 0) c.questions[i] = q;
    notifyListeners();
    return q;
  }

  Future<void> deleteQuestion(Category c, Question q) async {
    await api.deleteQuestion(packId, q.id);
    c.questions.removeWhere((x) => x.id == q.id);
    for (var i = 0; i < c.questions.length; i++) {
      c.questions[i].position = i;
    }
    notifyListeners();
  }

  Future<void> moveQuestion(Category c, int from, int to) async {
    if (from == to) return;
    final q = c.questions[from];
    _move(c.questions, from, to, (x, i) => x.position = i);
    notifyListeners();
    try {
      await api.updateQuestion(packId, q.id, {'position': to});
    } catch (_) {
      _move(c.questions, to, from, (x, i) => x.position = i);
      notifyListeners();
      rethrow;
    }
  }

  // ---------------------------------------------------------- media

  Future<Media> uploadMedia(MultipartFile file, String name, {Progress? onProgress}) async {
    final m = await api.uploadMedia(packId, file, name: name, onProgress: onProgress);
    _p.media
      ..removeWhere((x) => x.name == m.name)
      ..add(m);
    _p.media.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return m;
  }

  Future<void> deleteMedia(Media m) async {
    await api.deleteMedia(packId, m.name);
    _p.media.removeWhere((x) => x.name == m.name);
    notifyListeners();
  }
}

/// Media names: 1–128 chars of `[A-Za-z0-9._-]`, not starting with `.`.
String sanitizeMediaName(String name) {
  const translit = {
    'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'е': 'e', 'ё': 'e', 'ж': 'zh', 'з': 'z', 'и': 'i',
    'й': 'y', 'к': 'k', 'л': 'l', 'м': 'm', 'н': 'n', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't',
    'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'ts', 'ч': 'ch', 'ш': 'sh', 'щ': 'sch', 'ъ': '', 'ы': 'y', 'ь': '',
    'э': 'e', 'ю': 'yu', 'я': 'ya',
  };
  final buf = StringBuffer();
  for (final ch in name.split('')) {
    final lower = ch.toLowerCase();
    if (translit.containsKey(lower)) {
      final t = translit[lower]!;
      buf.write(ch == lower ? t : (t.isEmpty ? t : t[0].toUpperCase() + t.substring(1)));
    } else if (RegExp(r'[A-Za-z0-9._-]').hasMatch(ch)) {
      buf.write(ch);
    } else {
      buf.write('_');
    }
  }
  var s = buf.toString().replaceAll(RegExp(r'_+'), '_').replaceFirst(RegExp(r'^\.+'), '');
  if (s.isEmpty) s = 'file';
  if (s.length > 128) {
    final dot = s.lastIndexOf('.');
    final ext = dot > 0 && s.length - dot <= 10 ? s.substring(dot) : '';
    s = s.substring(0, 128 - ext.length) + ext;
  }
  return s;
}
