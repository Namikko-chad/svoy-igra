import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/blocks.dart';
import '../../data/models.dart';
import 'markdown_format.dart';
import 'media_screen.dart';
import 'pack_editor_model.dart';
import 'pack_editor_screen.dart';

/// Create / edit one question: value, reading time override, markdown fields
/// with live preview and media insertion.
class QuestionEditorScreen extends StatefulWidget {
  const QuestionEditorScreen({super.key, required this.categoryId, this.questionId});

  final int categoryId;
  final int? questionId;

  @override
  State<QuestionEditorScreen> createState() => _QuestionEditorScreenState();
}

class _QuestionEditorScreenState extends State<QuestionEditorScreen> {
  final _value = TextEditingController();
  final _reading = TextEditingController();
  final _question = TextEditingController();
  final _answer = TextEditingController();
  final _comment = TextEditingController();
  Question? _existing;
  bool _saving = false;
  String _initial = '';

  List<TextEditingController> get _all => [_value, _reading, _question, _answer, _comment];

  String get _snapshot => _all.map((c) => c.text).join('\u0000');

  bool get _dirty => _snapshot != _initial;

  @override
  void initState() {
    super.initState();
    final m = context.read<PackEditorModel>();
    final c = m.category(widget.categoryId);
    final q = widget.questionId == null ? null : c?.questions.where((x) => x.id == widget.questionId).firstOrNull;
    _existing = q;
    if (q != null) {
      _value.text = '${q.value}';
      _reading.text = q.readingSeconds?.toString() ?? '';
      _question.text = q.question;
      _answer.text = q.answer;
      _comment.text = q.comment;
    }
    _initial = _snapshot;
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final m = context.read<PackEditorModel>();
    final c = m.category(widget.categoryId);
    if (c == null) return;
    final valueText = _value.text.trim();
    final readingText = _reading.text.trim();
    final value = int.tryParse(valueText);
    final reading = int.tryParse(readingText);
    if (valueText.isNotEmpty && (value == null || value < 0)) {
      showToast(context, 'Стоимость — целое число', kind: ToastKind.error);
      return;
    }
    if (readingText.isNotEmpty && (reading == null || reading < 1 || reading > 120)) {
      showToast(context, 'Время чтения — от 1 до 120 с', kind: ToastKind.error);
      return;
    }
    if (_question.text.trim().isEmpty) {
      showToast(context, 'Введите текст вопроса', kind: ToastKind.error);
      return;
    }
    final input = <String, dynamic>{
      'question': _question.text,
      'answer': _answer.text,
      'comment': _comment.text,
      'readingSeconds': reading,
      'value': ?value,
    };
    setState(() => _saving = true);
    final nav = Navigator.of(context);
    final ok = await runEdit(context, () async {
      _existing = await m.saveQuestion(c, _existing, input);
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      _initial = _snapshot;
      nav.pop();
    }
  }

  Future<void> _delete() async {
    final m = context.read<PackEditorModel>();
    final c = m.category(widget.categoryId);
    final q = _existing;
    if (c == null || q == null) return;
    if (!await confirm(context, 'Удалить вопрос ${q.value}?', ok: 'Удалить', danger: true) || !mounted) return;
    final nav = Navigator.of(context);
    if (await runEdit(context, () => m.deleteQuestion(c, q))) {
      _initial = _snapshot;
      nav.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<PackEditorModel>();
    final c = m.category(widget.categoryId);
    final isNew = _existing == null;
    final isFinal = c != null && (m.roundOf(c.id)?.isFinal ?? false);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await confirm(context, 'Выйти без сохранения?', ok: 'Выйти', danger: true)) {
          _initial = _snapshot;
          nav.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(isFinal ? 'Вопрос финала' : (isNew ? 'Новый вопрос' : 'Вопрос ${_existing!.value}')),
          actions: [
            if (!isNew)
              IconButton(
                tooltip: 'Удалить',
                icon: const Icon(Icons.delete_outline),
                onPressed: _saving ? null : _delete,
              ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Сохранить'),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c != null)
              Text(
                c.name.toUpperCase(),
                style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textMuted),
              ),
            const SizedBox(height: 12),
            if (isFinal)
              Text('Финал: стоимости и времени чтения нет — финалисты делают ставки.', style: AppText.muted(13))
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _value,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Стоимость',
                        hintText: isNew ? 'авто' : null,
                        helperText: isNew ? 'Пусто — 100 × номер' : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _reading,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Время чтения, с',
                        hintText: 'как в игре',
                        helperText: 'Пусто — настройка игры',
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            MarkdownField(label: 'Вопрос', controller: _question, minLines: 4),
            const SizedBox(height: 16),
            MarkdownField(label: 'Ответ', controller: _answer, minLines: 2),
            const SizedBox(height: 16),
            MarkdownField(label: 'Комментарий ведущему', controller: _comment, minLines: 2),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Multiline markdown input with a formatting toolbar (bold, italic, heading,
/// lists, quote, link, media) and a live preview.
class MarkdownField extends StatefulWidget {
  const MarkdownField({super.key, required this.label, required this.controller, this.minLines = 3});

  final String label;
  final TextEditingController controller;
  final int minLines;

  @override
  State<MarkdownField> createState() => _MarkdownFieldState();
}

class _MarkdownFieldState extends State<MarkdownField> {
  final _focus = FocusNode();
  bool _preview = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _apply(TextEditingValue Function(TextEditingValue v) edit) {
    widget.controller.value = edit(widget.controller.value);
    _focus.requestFocus();
  }

  Future<void> _link() async {
    final ctrl = widget.controller;
    final before = ctrl.value;
    final sel = before.selection;
    final selected = sel.isValid && !sel.isCollapsed ? sel.textInside(before.text) : '';
    final url = TextEditingController(text: 'https://');
    final label = TextEditingController(text: selected);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ссылка'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'Текст'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Адрес (URL)'),
              onSubmitted: (_) => Navigator.pop(ctx, true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Вставить')),
        ],
      ),
    );
    final u = url.text.trim();
    if (ok != true || u.isEmpty || u == 'https://') return;
    ctrl.value = insertLink(before, u, label: label.text);
    _focus.requestFocus();
  }

  Future<void> _insertMedia() async {
    final m = context.read<PackEditorModel>();
    final ctrl = widget.controller;
    final before = ctrl.value;
    final name = await pickMediaSheet(context, m);
    if (name == null) return;
    // Into THIS field, at the cursor it had when «Медиа» was pressed.
    ctrl.value = insertMedia(before, name);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final m = context.read<PackEditorModel>();
    Widget tool(IconData icon, String tip, VoidCallback onTap) =>
        IconButton(tooltip: tip, icon: Icon(icon, size: 20), visualDensity: VisualDensity.compact, onPressed: onTap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.label, style: AppText.body(14, weight: FontWeight.w600)),
            ),
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit_note : Icons.visibility_outlined, size: 18),
              label: Text(_preview ? 'Текст' : 'Просмотр'),
            ),
          ],
        ),
        if (!_preview)
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: AppColors.border),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  tool(Icons.format_bold, 'Жирный', () => _apply((v) => wrapSelection(v, MdWrap.bold))),
                  tool(Icons.format_italic, 'Курсив', () => _apply((v) => wrapSelection(v, MdWrap.italic))),
                  tool(Icons.title, 'Заголовок', () => _apply((v) => prefixLines(v, MdLine.heading))),
                  tool(
                    Icons.format_list_bulleted,
                    'Маркированный список',
                    () => _apply((v) => prefixLines(v, MdLine.bullet)),
                  ),
                  tool(
                    Icons.format_list_numbered,
                    'Нумерованный список',
                    () => _apply((v) => prefixLines(v, MdLine.numbered)),
                  ),
                  tool(Icons.format_quote, 'Цитата', () => _apply((v) => prefixLines(v, MdLine.quote))),
                  tool(Icons.link, 'Ссылка', _link),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _insertMedia,
                    icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                    label: const Text('Медиа'),
                  ),
                ],
              ),
            ),
          ),
        if (_preview)
          Container(
            constraints: BoxConstraints(minHeight: widget.minLines * 22.0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (_, v, _) => BlocksPreview(blocks: splitBlocks(m.packId, v.text), api: m.api),
            ),
          )
        else
          TextField(
            controller: widget.controller,
            focusNode: _focus,
            minLines: widget.minLines,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Markdown: **жирный**, *курсив*, ![](media:файл.jpg)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                borderSide: BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
                borderSide: BorderSide(color: AppColors.border),
              ),
            ),
          ),
      ],
    );
  }
}
