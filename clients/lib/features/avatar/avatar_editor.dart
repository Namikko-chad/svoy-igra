import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/platform.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/avatar_image.dart';

enum _AvatarAction { gallery, camera, remove }

/// «Мой аватар» for a player or the host: pick from the gallery or camera
/// (desktop: a file, no camera),
/// crop to a centred square ≤ 512 px, upload; or remove. [offer] = shown right
/// after joining (adds «Позже»).
Future<void> editMyAvatar(BuildContext context, Api api, {bool hasAvatar = false, bool offer = false}) async {
  final action = await showModalBottomSheet<_AvatarAction>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text(offer ? 'Добавить аватар?' : 'Мой аватар'),
          subtitle: const Text('Картинку увидят все в этой игре'),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: Text(isDesktop ? 'Выбрать файл' : 'Выбрать из галереи'),
          onTap: () => Navigator.pop(ctx, _AvatarAction.gallery),
        ),
        if (!isDesktop)
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Сделать фото'),
            onTap: () => Navigator.pop(ctx, _AvatarAction.camera),
          ),
        if (hasAvatar)
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Удалить аватар'),
            onTap: () => Navigator.pop(ctx, _AvatarAction.remove),
          ),
        if (offer)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Позже'),
            onTap: () => Navigator.pop(ctx),
          ),
      ]),
    ),
  );
  if (action == null || !context.mounted) return;
  try {
    if (action == _AvatarAction.remove) {
      await api.deleteAvatar();
      if (context.mounted) showToast(context, 'Аватар удалён', kind: ToastKind.success);
      return;
    }
    final file = await ImagePicker().pickImage(
      source: action == _AvatarAction.camera ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (file == null || !context.mounted) return;
    showProgressDialog(context, 'Загрузка аватара');
    final nav = Navigator.of(context);
    try {
      final square = await compute(squareAvatar, await file.readAsBytes());
      if (square == null) throw const ApiException('invalid_image', '');
      await api.uploadAvatar(square);
      nav.pop();
      if (context.mounted) showToast(context, 'Аватар обновлён', kind: ToastKind.success);
    } catch (_) {
      nav.pop();
      rethrow;
    }
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.text, kind: ToastKind.error);
  } on Exception {
    if (context.mounted) showToast(context, 'Не удалось открыть картинку', kind: ToastKind.error);
  }
}
