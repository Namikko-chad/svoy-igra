import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../editor/pack_editor_screen.dart';
import '../game/session.dart';

/// Shared pack library (admin): list, create, import `.dub`, export, delete,
/// lock, copy, open the editor, load into the game.
class PackLibrary extends StatefulWidget {
  const PackLibrary({super.key});

  @override
  State<PackLibrary> createState() => _PackLibraryState();
}

class _PackLibraryState extends State<PackLibrary> {
  List<PackSummary>? _packs;
  String? _error;

  Api get _api => context.read<Session>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final packs = await _api.listPacks();
      if (mounted) {
        setState(() {
          _packs = packs;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.text);
    }
  }

  void _put(PackSummary p) {
    setState(() {
      final list = [...?_packs]..removeWhere((x) => x.id == p.id);
      _packs = [p, ...list];
    });
  }

  Future<void> _create() async {
    final title = (await promptText(context, 'Новый пакет', label: 'Название', ok: 'Создать'))?.trim();
    if (title == null || title.isEmpty || !mounted) return;
    try {
      final pack = await _api.createPack(title);
      if (!mounted) return;
      await _openEditor(pack.id);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
    }
  }

  Future<void> _import() async {
    final f = await pickOneFile();
    if (f == null || !mounted) return;
    if (!f.name.toLowerCase().endsWith('.dub')) {
      showToast(context, 'Нужен файл пакета .dub', kind: ToastKind.error);
      return;
    }
    final progress = showProgressDialog(context, 'Импорт «${f.name}»');
    final nav = Navigator.of(context);
    try {
      final summary = await _api.importPack(
        await multipartOf(f),
        onProgress: (sent, total) => progress.value = total > 0 ? sent / total : null,
      );
      nav.pop();
      _put(summary);
      if (mounted) showToast(context, 'Пакет «${summary.title}» импортирован', kind: ToastKind.success);
    } on ApiException catch (e) {
      nav.pop();
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
    } on Exception {
      nav.pop();
      if (mounted) showToast(context, 'Не удалось прочитать файл', kind: ToastKind.error);
    }
  }

  Future<void> _export(PackSummary p) async {
    final progress = showProgressDialog(context, 'Экспорт «${p.title}»');
    final nav = Navigator.of(context);
    Download d;
    try {
      d = await _api.exportPack(p.id, onProgress: (got, total) => progress.value = total > 0 ? got / total : null);
      nav.pop();
    } on ApiException catch (e) {
      nav.pop();
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
      return;
    }
    try {
      if (await saveBytes(d.fileName, d.bytes, mimeType: 'application/zip') && mounted) {
        showToast(context, 'Сохранено: ${d.fileName}', kind: ToastKind.success);
      }
    } catch (_) {
      if (mounted) showToast(context, 'Не удалось сохранить файл', kind: ToastKind.error);
    }
  }

  Future<void> _delete(PackSummary p) async {
    if (!await confirm(context, 'Удалить «${p.title}»?', message: 'Пакет и его медиа будут удалены с сервера.', ok: 'Удалить', danger: true)) {
      return;
    }
    try {
      await _api.deletePack(p.id);
      if (mounted) setState(() => _packs = [...?_packs]..removeWhere((x) => x.id == p.id));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
    }
  }

  Future<void> _lock(PackSummary p) async {
    if (!await confirm(
      context,
      'Заблокировать «${p.title}»?',
      message: 'Пакет нельзя будет изменить или удалить — только отредактировать его копию. '
          'Снять блокировку может лишь владелец сервера.',
      ok: 'Заблокировать',
      danger: true,
    )) {
      return;
    }
    try {
      _put(await _api.lockPack(p.id));
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
    }
  }

  /// «Редактировать копию»: POST copy, then open the copy.
  Future<void> _copy(PackSummary p) async {
    final title = (await promptText(context, 'Редактировать копию',
            label: 'Название копии', initial: '${p.title} (копия)', ok: 'Создать копию'))
        ?.trim();
    if (title == null || title.isEmpty || !mounted) return;
    final progress = showProgressDialog(context, 'Копирование «${p.title}»');
    final nav = Navigator.of(context);
    try {
      final copy = await _api.copyPack(p.id, title);
      progress.value = 1;
      nav.pop();
      if (mounted) await _openEditor(copy.id);
    } on ApiException catch (e) {
      nav.pop();
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
    }
  }

  Future<void> _open(PackSummary p) => p.locked ? _copy(p) : _openEditor(p.id);

  Future<void> _openEditor(String id) async {
    final api = _api;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PackEditorScreen(api: api, packId: id)));
    // The editor changed counts and sizes; refresh the summaries.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final view = context.select<GameSocket, GameView?>((s) => s.view);
    final canLoad = view != null && (view.phase == Phase.lobby || view.phase == Phase.finished);
    final packs = _packs;
    Widget body;
    if (_error != null && packs == null) {
      body = EmptyState(
        title: 'Не удалось загрузить пакеты',
        subtitle: _error,
        action: OutlinedButton(onPressed: _load, child: const Text('Повторить')),
      );
    } else if (packs == null) {
      body = const Center(child: CircularProgressIndicator());
    } else if (packs.isEmpty) {
      body = ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
          icon: Icons.library_books_outlined,
          title: 'Библиотека пуста',
          subtitle: 'Создайте пакет или импортируйте файл .dub',
        ),
      ]);
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: packs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final p = packs[i];
          final loaded = view?.pack?.id == p.id;
          return Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: loaded ? AppColors.gold : AppColors.border),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _open(p),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        if (p.locked) ...[
                          const Icon(Icons.lock, size: 16, color: AppColors.warning),
                          const SizedBox(width: 6),
                        ],
                        Expanded(child: Text(p.title, style: AppText.body(16, weight: FontWeight.w600))),
                      ]),
                      if (p.author.isNotEmpty) Text(p.author, style: AppText.muted(13)),
                      const SizedBox(height: 4),
                      Text(packCounts(p), style: AppText.muted(12)),
                      Text('${formatBytes(p.sizeBytes)} · изменён ${formatDateTime(p.updatedAt)}',
                          style: AppText.mono(11, color: AppColors.textMuted)),
                      if (loaded) Text('загружен в игру', style: AppText.body(12, color: AppColors.gold)),
                    ]),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'edit':
                          _openEditor(p.id);
                        case 'copy':
                          _copy(p);
                        case 'lock':
                          _lock(p);
                        case 'load':
                          context.read<GameSocket>().command('load_pack', {'packId': p.id});
                        case 'export':
                          _export(p);
                        case 'delete':
                          _delete(p);
                      }
                    },
                    itemBuilder: (_) => [
                      if (!p.locked) const PopupMenuItem(value: 'edit', child: Text('Редактировать')),
                      const PopupMenuItem(value: 'copy', child: Text('Редактировать копию')),
                      PopupMenuItem(value: 'load', enabled: canLoad, child: const Text('Загрузить в игру')),
                      const PopupMenuItem(value: 'export', child: Text('Экспорт .dub')),
                      if (!p.locked) const PopupMenuItem(value: 'lock', child: Text('Заблокировать…')),
                      if (!p.locked) const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                    ],
                  ),
                ]),
              ),
            ),
          );
        },
      );
    }
    return Stack(children: [
      Positioned.fill(child: RefreshIndicator(onRefresh: _load, child: body)),
      Positioned(
        right: 16,
        bottom: 16,
        child: Row(children: [
          FloatingActionButton.extended(
            heroTag: 'import',
            backgroundColor: AppColors.surface2,
            foregroundColor: AppColors.text,
            onPressed: _import,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('Импорт'),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'create',
            backgroundColor: AppColors.accent,
            foregroundColor: AppColors.bg,
            onPressed: _create,
            icon: const Icon(Icons.add),
            label: const Text('Создать'),
          ),
        ]),
      ),
    ]);
  }
}

String packCounts(PackSummary p) =>
    'раундов: ${p.rounds} · тем: ${p.categories} · вопросов: ${p.questions} · медиа: ${p.mediaCount}';

/// Lets the admin choose a pack from the library and sends `load_pack`.
Future<void> pickAndLoadPack(BuildContext context) async {
  final api = context.read<Session>().api;
  final socket = context.read<GameSocket>();
  final pack = await showModalBottomSheet<PackSummary>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, scroll) => FutureBuilder<List<PackSummary>>(
        future: api.listPacks(),
        builder: (ctx, snap) {
          if (snap.hasError) return EmptyState(title: 'Не удалось загрузить пакеты', subtitle: '${snap.error}');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final packs = snap.data!;
          if (packs.isEmpty) {
            return const EmptyState(
              icon: Icons.library_books_outlined,
              title: 'Библиотека пуста',
              subtitle: 'Создайте или импортируйте пакет на вкладке «Пакеты».',
            );
          }
          return ListView(controller: scroll, children: [
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: SectionTitle('Выберите пакет')),
            for (final p in packs)
              ListTile(
                leading: p.locked ? const Icon(Icons.lock, color: AppColors.warning) : const Icon(Icons.library_books_outlined),
                title: Text(p.title),
                subtitle: Text(packCounts(p), style: AppText.muted(12)),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ]);
        },
      ),
    ),
  );
  if (pack != null) socket.command('load_pack', {'packId': pack.id});
}
