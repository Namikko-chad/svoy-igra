import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../game/blocks_view.dart';
import 'media_screen.dart';
import 'pack_editor_model.dart';
import 'question_editor_screen.dart';

/// Runs an editor mutation, showing API errors as toasts. Returns success.
Future<bool> runEdit(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.text, kind: ToastKind.error);
  }
  return false;
}

Route<void> editorRoute(PackEditorModel model, Widget child) => MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider<PackEditorModel>.value(value: model, child: child),
    );

/// Pack editor root: meta, rounds, media.
class PackEditorScreen extends StatefulWidget {
  const PackEditorScreen({super.key, required this.api, required this.packId});

  final Api api;
  final String packId;

  @override
  State<PackEditorScreen> createState() => _PackEditorScreenState();
}

class _PackEditorScreenState extends State<PackEditorScreen> {
  late final PackEditorModel _model = PackEditorModel(widget.api, widget.packId)..load();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PackEditorModel>.value(value: _model, child: const _PackEditorView());
  }
}

class _PackEditorView extends StatelessWidget {
  const _PackEditorView();

  Future<void> _editMeta(BuildContext context, PackEditorModel m) async {
    final p = m.pack!;
    final title = TextEditingController(text: p.title);
    final author = TextEditingController(text: p.author);
    final description = TextEditingController(text: p.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Информация о пакете'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 12),
            TextField(controller: author, decoration: const InputDecoration(labelText: 'Автор')),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (title.text.trim().isEmpty) {
      showToast(context, 'Название не может быть пустым', kind: ToastKind.error);
      return;
    }
    await runEdit(
      context,
      () => m.updateMeta(title: title.text.trim(), author: author.text.trim(), description: description.text.trim()),
    );
  }

  Future<void> _addRound(BuildContext context, PackEditorModel m) async {
    final name = (await promptText(context, 'Новый раунд',
            label: 'Название', initial: 'Раунд ${m.pack!.rounds.length + 1}', ok: 'Добавить'))
        ?.trim();
    if (name == null || name.isEmpty || !context.mounted) return;
    await runEdit(context, () => m.addRound(name));
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<PackEditorModel>();
    final p = m.pack;
    return Scaffold(
      appBar: AppBar(
        title: Text(p?.title ?? 'Редактор пакета', overflow: TextOverflow.ellipsis),
        actions: [
          if (p != null)
            IconButton(
              tooltip: 'Медиа',
              icon: const Icon(Icons.perm_media_outlined),
              onPressed: () => Navigator.of(context).push(editorRoute(m, const MediaScreen())),
            ),
        ],
      ),
      floatingActionButton: p == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addRound(context, m),
              icon: const Icon(Icons.add),
              label: const Text('Раунд'),
            ),
      body: p == null
          ? (m.error != null
              ? EmptyState(
                  title: 'Не удалось открыть пакет',
                  subtitle: m.error,
                  action: OutlinedButton(onPressed: m.load, child: const Text('Повторить')),
                )
              : const Center(child: CircularProgressIndicator()))
          : CustomScrollView(slivers: [
              if (p.locked)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.lock, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Пакет заблокирован: изменить его нельзя. Отредактируйте копию в библиотеке.',
                            style: AppText.body(13, color: AppColors.warning),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _editMeta(context, m),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(p.title, style: AppText.display(18, weight: FontWeight.w600))),
                            const Icon(Icons.edit, size: 18, color: AppColors.textMuted),
                          ]),
                          if (p.author.isNotEmpty) Text('Автор: ${p.author}', style: AppText.muted(13)),
                          if (p.description.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(p.description, style: AppText.body(14)),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'медиа: ${p.media.length} · ${formatBytes(p.sizeBytes)} · изменён ${formatDateTime(p.updatedAt)}',
                            style: AppText.mono(11, color: AppColors.textMuted),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: SectionTitle('Раунды')),
              ),
              if (p.rounds.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Раундов нет. Добавьте первый раунд.', style: AppText.muted(14)),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                sliver: SliverReorderableList(
                  itemCount: p.rounds.length,
                  onReorder: (from, to) {
                    if (to > from) to--;
                    runEdit(context, () => m.moveRound(from, to));
                  },
                  itemBuilder: (context, i) {
                    final r = p.rounds[i];
                    final qs = r.categories.fold<int>(0, (n, c) => n + c.questions.length);
                    return Padding(
                      key: ValueKey('r${r.id}'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                          title: Text(r.name),
                          subtitle: Text(
                            r.isFinal
                                ? 'финал · тем: ${r.categories.length}'
                                : 'тем: ${r.categories.length}/10 · вопросов: $qs',
                            style: AppText.body(12,
                                color: r.isFinal
                                    ? AppColors.gold
                                    : (r.categories.length == 10 ? AppColors.textMuted : AppColors.warning)),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(editorRoute(m, RoundEditorScreen(roundId: r.id))),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]),
    );
  }
}

/// One round: rename/delete and its categories (max 10).
class RoundEditorScreen extends StatelessWidget {
  const RoundEditorScreen({super.key, required this.roundId});

  final int roundId;

  @override
  Widget build(BuildContext context) {
    final m = context.watch<PackEditorModel>();
    final r = m.round(roundId);
    if (r == null) return const Scaffold(body: EmptyState(title: 'Раунд удалён'));
    final full = r.categories.length >= 10;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Переименовать',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final name = (await promptText(context, 'Название раунда', initial: r.name))?.trim();
              if (name != null && name.isNotEmpty && context.mounted) await runEdit(context, () => m.renameRound(r, name));
            },
          ),
          IconButton(
            tooltip: 'Удалить раунд',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, 'Удалить раунд «${r.name}»?',
                  message: 'Все темы и вопросы раунда будут удалены.', ok: 'Удалить', danger: true)) {
                return;
              }
              if (!context.mounted) return;
              final nav = Navigator.of(context);
              if (await runEdit(context, () => m.deleteRound(r))) nav.pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: full
            ? () => showToast(context, 'В раунде не может быть больше 10 тем', kind: ToastKind.warning)
            : () async {
                final name = (await promptText(context, 'Новая тема', label: 'Название', ok: 'Добавить'))?.trim();
                if (name != null && name.isNotEmpty && context.mounted) await runEdit(context, () => m.addCategory(r, name));
              },
        backgroundColor: full ? AppColors.surface2 : AppColors.accent,
        foregroundColor: full ? AppColors.textMuted : AppColors.bg,
        icon: const Icon(Icons.add),
        label: const Text('Тема'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Card(
          child: SwitchListTile(
            key: const ValueKey('round-final'),
            title: const Text('Финал'),
            subtitle: Text(
              'Финальный раунд: финалисты убирают темы, делают ставки и пишут ответ. '
              'В каждой теме — ровно один вопрос, без стоимости.',
              style: AppText.muted(12),
            ),
            value: r.isFinal,
            onChanged: (v) => runEdit(context, () => m.setRoundFinal(r, v)),
          ),
        ),
        SectionTitle(r.isFinal ? 'Темы финала: ${r.categories.length}' : 'Темы ${r.categories.length}/10'),
        if (!r.isFinal && r.categories.length != 10)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
            ),
            child: Text(
              'В классической «Своей игре» в раунде 10 тем. Сейчас: ${r.categories.length}.',
              style: AppText.body(13, color: AppColors.warning),
            ),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: r.categories.length,
          onReorder: (from, to) {
            if (to > from) to--;
            runEdit(context, () => m.moveCategory(r, from, to));
          },
          itemBuilder: (context, i) {
            final c = r.categories[i];
            return Padding(
              key: ValueKey('c${c.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                  title: Text(c.name),
                  subtitle: Text(
                    c.questions.isEmpty
                        ? 'нет вопросов'
                        : (r.isFinal
                            ? (c.questions.length == 1 ? 'вопрос есть' : 'вопросов: ${c.questions.length} — нужен один')
                            : c.questions.map((q) => q.value).join(' · ')),
                    style: AppText.mono(12, color: AppColors.textMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(editorRoute(m, CategoryEditorScreen(categoryId: c.id, roundId: r.id))),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}

/// One category: rename/delete and its questions.
class CategoryEditorScreen extends StatelessWidget {
  const CategoryEditorScreen({super.key, required this.categoryId, required this.roundId});

  final int categoryId;
  final int roundId;

  @override
  Widget build(BuildContext context) {
    final m = context.watch<PackEditorModel>();
    final r = m.round(roundId);
    final c = m.category(categoryId);
    if (r == null || c == null) return const Scaffold(body: EmptyState(title: 'Тема удалена'));
    final finalFull = r.isFinal && c.questions.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Переименовать',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              final name = (await promptText(context, 'Название темы', initial: c.name))?.trim();
              if (name != null && name.isNotEmpty && context.mounted) await runEdit(context, () => m.renameCategory(c, name));
            },
          ),
          IconButton(
            tooltip: 'Удалить тему',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (!await confirm(context, 'Удалить тему «${c.name}»?',
                  message: 'Все вопросы темы будут удалены.', ok: 'Удалить', danger: true)) {
                return;
              }
              if (!context.mounted) return;
              final nav = Navigator.of(context);
              if (await runEdit(context, () => m.deleteCategory(r, c))) nav.pop();
            },
          ),
        ],
      ),
      floatingActionButton: finalFull
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(editorRoute(m, QuestionEditorScreen(categoryId: c.id))),
              icon: const Icon(Icons.add),
              label: const Text('Вопрос'),
            ),
      body: c.questions.isEmpty
          ? EmptyState(
              icon: Icons.quiz_outlined,
              title: 'Вопросов нет',
              subtitle: r.isFinal
                  ? 'Тема финала: добавьте ровно один вопрос.'
                  : 'Стоимость нового вопроса подставится автоматически: 100, 200, 300…',
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              buildDefaultDragHandles: false,
              itemCount: c.questions.length,
              onReorder: (from, to) {
                if (to > from) to--;
                runEdit(context, () => m.moveQuestion(c, from, to));
              },
              itemBuilder: (context, i) {
                final q = c.questions[i];
                final preview = q.question.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '🖼').replaceAll('\n', ' ').trim();
                return Padding(
                  key: ValueKey('q${q.id}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                      title: Row(children: [
                        Text(r.isFinal ? 'Вопрос финала' : '${q.value}', style: AppText.display(16, color: AppColors.gold)),
                        if (!r.isFinal && q.readingSeconds != null) ...[
                          const SizedBox(width: 8),
                          Text('${q.readingSeconds} с', style: AppText.mono(12, color: AppColors.textMuted)),
                        ],
                      ]),
                      subtitle: Text(
                        preview.isEmpty ? '(пусто)' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(editorRoute(m, QuestionEditorScreen(categoryId: c.id, questionId: q.id))),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Markdown preview with the same block splitting as the server.
class BlocksPreview extends StatelessWidget {
  const BlocksPreview({super.key, required this.blocks, required this.api});

  final List<Block> blocks;
  final Api api;

  @override
  Widget build(BuildContext context) {
    if (blocks.isEmpty) return Text('Пусто', style: AppText.muted(14));
    return BlocksView(blocks: blocks, mode: MediaMode.host, resolveUrl: api.absolute, fontSize: 18, center: false);
  }
}
