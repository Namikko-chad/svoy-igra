import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/blocks.dart';
import '../../data/files.dart';
import '../../data/models.dart';
import '../game/blocks_view.dart';
import 'pack_editor_model.dart';

/// Pack media manager: upload, preview, delete. Inserting into a field goes
/// through [pickMediaSheet].
class MediaScreen extends StatelessWidget {
  const MediaScreen({super.key});

  Future<void> _upload(BuildContext context, FileType type) async {
    await uploadMediaFiles(context, context.read<PackEditorModel>(), type);
  }

  Future<void> _delete(BuildContext context, Media media) async {
    final m = context.read<PackEditorModel>();
    if (!await confirm(context, 'Удалить «${media.name}»?',
        message: 'Вопросы, которые ссылаются на файл, покажут пустое место.', ok: 'Удалить', danger: true)) {
      return;
    }
    try {
      await m.deleteMedia(media);
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, e.text, kind: ToastKind.error);
    }
  }

  void _preview(BuildContext context, Media media) {
    final m = context.read<PackEditorModel>();
    final kind = mediaKind(media.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(media.name, style: AppText.mono(14)),
        content: SingleChildScrollView(
          child: BlocksView(
            blocks: [Block.media(kind, media.url.isEmpty ? mediaUrl(m.packId, media.name) : media.url, media.name)],
            mode: MediaMode.host,
            resolveUrl: m.api.absolute,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<PackEditorModel>();
    final media = m.pack?.media ?? const <Media>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Медиа пакета')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(isDesktop ? 'Фото и видео' : 'Фото и видео из галереи'),
                onTap: () {
                  Navigator.pop(ctx);
                  _upload(context, FileType.media);
                },
              ),
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: const Text('Аудио'),
                onTap: () {
                  Navigator.pop(ctx);
                  _upload(context, FileType.audio);
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Любой файл'),
                onTap: () {
                  Navigator.pop(ctx);
                  _upload(context, FileType.any);
                },
              ),
            ]),
          ),
        ),
        icon: const Icon(Icons.upload),
        label: const Text('Загрузить'),
      ),
      body: media.isEmpty
          ? const EmptyState(
              icon: Icons.perm_media_outlined,
              title: 'Медиафайлов нет',
              subtitle: 'Загрузите изображения, видео или аудио, затем вставьте их в вопрос.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              itemCount: media.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final x = media[i];
                final kind = mediaKind(x.name);
                final url = m.api.absolute(x.url.isEmpty ? mediaUrl(m.packId, x.name) : x.url);
                return Card(
                  child: ListTile(
                    leading: SizedBox(
                      width: 48,
                      height: 48,
                      child: kind == BlockType.image
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(url, fit: BoxFit.cover, cacheWidth: 128,
                                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                            )
                          : Icon(kind == BlockType.video ? Icons.movie_outlined : Icons.audiotrack, color: AppColors.accent),
                    ),
                    title: Text(x.name, style: AppText.mono(13), overflow: TextOverflow.ellipsis),
                    subtitle: Text('${x.mime} · ${formatBytes(x.size)}', style: AppText.muted(12)),
                    onTap: () => _preview(context, x),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'preview') _preview(context, x);
                        if (v == 'delete') _delete(context, x);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'preview', child: Text('Просмотр')),
                        const PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Picks files of [type] and uploads them with progress; asks before replacing
/// an existing name. Returns the last uploaded name (null if none).
Future<String?> uploadMediaFiles(BuildContext context, PackEditorModel m, FileType type) async {
  final files = await pickManyFiles(type: type);
  if (files.isEmpty || !context.mounted) return null;
  final existing = m.pack!.media.map((x) => x.name).toSet();
  String? last;
  for (final f in files) {
    if (!context.mounted) return last;
    final name = sanitizeMediaName(f.name);
    if (existing.contains(name) &&
        !await confirm(context, 'Файл «$name» уже есть', message: 'Заменить его новым?', ok: 'Заменить')) {
      continue;
    }
    if (!context.mounted) return last;
    final progress = showProgressDialog(context, 'Загрузка «$name»');
    final nav = Navigator.of(context);
    try {
      await m.uploadMedia(
        await multipartOf(f),
        name,
        onProgress: (sent, total) => progress.value = total > 0 ? sent / total : null,
      );
      nav.pop();
      last = name;
    } on ApiException catch (e) {
      nav.pop();
      if (context.mounted) showToast(context, '$name: ${e.text}', kind: ToastKind.error);
    } on Exception {
      nav.pop();
      if (context.mounted) showToast(context, '$name: не удалось прочитать файл', kind: ToastKind.error);
    }
  }
  if (last != null && context.mounted) showToast(context, 'Загружено', kind: ToastKind.success);
  return last;
}

/// «Медиа» of a markdown field: a sheet with the pack's files and «Загрузить файл».
/// Returns the chosen (or freshly uploaded) file name.
Future<String?> pickMediaSheet(BuildContext context, PackEditorModel m) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => ChangeNotifierProvider<PackEditorModel>.value(
      value: m,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _MediaSheet(scroll: scroll),
      ),
    ),
  );
}

class _MediaSheet extends StatelessWidget {
  const _MediaSheet({required this.scroll});

  final ScrollController scroll;

  Future<void> _upload(BuildContext context) async {
    final m = context.read<PackEditorModel>();
    final type = await showModalBottomSheet<FileType>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(isDesktop ? 'Фото и видео' : 'Фото и видео из галереи'),
            onTap: () => Navigator.pop(ctx, FileType.media),
          ),
          ListTile(
            leading: const Icon(Icons.audio_file_outlined),
            title: const Text('Аудио'),
            onTap: () => Navigator.pop(ctx, FileType.audio),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Любой файл'),
            onTap: () => Navigator.pop(ctx, FileType.any),
          ),
        ]),
      ),
    );
    if (type == null || !context.mounted) return;
    final name = await uploadMediaFiles(context, m, type);
    if (name != null && context.mounted) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<PackEditorModel>();
    final media = m.pack?.media ?? const <Media>[];
    return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
      Row(children: [
        Expanded(child: Text('Вставить медиа', style: AppText.display(16, weight: FontWeight.w600))),
        FilledButton.icon(
          onPressed: m.pack?.locked == true ? null : () => _upload(context),
          icon: const Icon(Icons.upload, size: 18),
          label: const Text('Загрузить файл'),
        ),
      ]),
      const SizedBox(height: 12),
      if (media.isEmpty) Text('В пакете пока нет файлов.', style: AppText.muted(14)),
      for (final x in media)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(width: 48, height: 48, child: _MediaThumb(media: x, model: m)),
          title: Text(x.name, style: AppText.mono(13), overflow: TextOverflow.ellipsis),
          subtitle: Text('${x.mime} · ${formatBytes(x.size)}', style: AppText.muted(12)),
          onTap: () => Navigator.of(context).pop(x.name),
        ),
    ]);
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({required this.media, required this.model});

  final Media media;
  final PackEditorModel model;

  @override
  Widget build(BuildContext context) {
    final kind = mediaKind(media.name);
    if (kind != BlockType.image) {
      return Icon(kind == BlockType.video ? Icons.movie_outlined : Icons.audiotrack, color: AppColors.accent);
    }
    final url = model.api.absolute(media.url.isEmpty ? mediaUrl(model.packId, media.name) : media.url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, fit: BoxFit.cover, cacheWidth: 128, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
    );
  }
}
