import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/files.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';
import '../connect/server_screen.dart';
import '../game/session.dart';
import '../game/settings_card.dart';
import '../host/host_screen.dart';
import '../library/pack_library.dart';
import '../screen/screen_view.dart';

/// Admin «Игра» tab: PIN + share link, game state, pack, settings, game file,
/// rename / admin PIN, reset, close.
class AdminGameTab extends StatelessWidget {
  const AdminGameTab({super.key});

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    final view = socket.view;
    if (view == null) return const WaitingForState();
    final g = view.game;
    final canLoad = view.phase == Phase.lobby || view.phase == Phase.finished;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _InviteCard(game: g),
        const SectionTitle('Состояние'),
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text('Фаза: ${view.phase.label}'),
                subtitle: view.round == null
                    ? null
                    : Text(
                        'Раунд ${view.round!.index + 1}/${view.round!.total} · ${view.round!.name}',
                        style: AppText.muted(12),
                      ),
              ),
              const Divider(),
              ListTile(
                leading: Avatar(
                  name: 'Ведущий',
                  url: g.hostAvatarUrl,
                  size: 40,
                  ring: g.hostConnected ? AppColors.success : null,
                ),
                trailing: g.hostAvatarUrl == null
                    ? null
                    : IconButton(
                        tooltip: 'Удалить аватар ведущего',
                        icon: const Icon(Icons.hide_image_outlined),
                        onPressed: () => socket.command('clear_avatar'),
                      ),
                title: Text(
                  g.hostConnected ? 'Ведущий подключён' : (g.hostTaken ? 'Ведущий не в сети' : 'Ведущего нет'),
                ),
                subtitle: Text(
                  'Игроков: ${view.players.length} · администраторов в сети: ${view.admins ?? 0}',
                  style: AppText.muted(12),
                ),
              ),
            ],
          ),
        ),
        const SectionTitle('Пакет'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.library_books_outlined, color: AppColors.accent),
            title: Text(view.pack?.title ?? 'Пакет не выбран'),
            subtitle: Text(
              canLoad
                  ? 'Ведущий начнёт игру после выбора пакета'
                  : 'Сменить пакет можно в лобби или после окончания игры',
              style: AppText.muted(12),
            ),
            trailing: FilledButton(
              onPressed: canLoad ? () => pickAndLoadPack(context) : null,
              child: Text(view.pack == null ? 'Выбрать' : 'Сменить'),
            ),
          ),
        ),
        const SectionTitle('Настройки игры'),
        SettingsCard(settings: view.settings, socket: socket, canCompensate: true),
        const SectionTitle('Файл игры'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.download),
                onPressed: () => exportGameFile(context),
                label: const Text('Сохранить'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload),
                onPressed: () => importGameFile(context),
                label: const Text('Загрузить'),
              ),
            ),
          ],
        ),
        const SectionTitle('Игра'),
        OutlinedButton.icon(
          icon: const Icon(Icons.edit),
          onPressed: () => _rename(context, g),
          label: const Text('Переименовать игру'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.password),
          onPressed: () => _changePin(context),
          label: const Text('Сменить PIN администратора'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () => resetGame(context),
          child: const Text('Сбросить игру…'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.text),
          icon: const Icon(Icons.delete_forever),
          onPressed: () => _close(context),
          label: const Text('Закрыть игру'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Future<void> _rename(BuildContext context, GameRef g) async {
    final socket = context.read<GameSocket>();
    final title = (await promptText(context, 'Название игры', initial: g.title, maxLength: 60))?.trim();
    if (title == null) return;
    socket.command('update_game', {'title': title});
  }

  Future<void> _changePin(BuildContext context) async {
    final socket = context.read<GameSocket>();
    final pin = (await promptText(
      context,
      'Новый PIN администратора',
      label: '4–8 цифр',
      number: true,
      maxLength: 8,
    ))
        ?.trim();
    if (pin == null || !context.mounted) return;
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      showToast(context, 'PIN администратора — от 4 до 8 цифр', kind: ToastKind.error);
      return;
    }
    final again = (await promptText(context, 'Повторите PIN', number: true, maxLength: 8))?.trim();
    if (again == null || !context.mounted) return;
    if (again != pin) {
      showToast(context, 'PIN-коды не совпадают', kind: ToastKind.error);
      return;
    }
    if (socket.command('update_game', {'adminPin': pin})) {
      showToast(context, 'PIN администратора изменён', kind: ToastKind.success);
    }
  }

  Future<void> _close(BuildContext context) async {
    final socket = context.read<GameSocket>();
    if (await confirm(
      context,
      'Закрыть игру?',
      message: 'Игра будет удалена вместе с игроками и очками; все отключатся. Пакеты останутся в библиотеке.',
      ok: 'Закрыть',
      danger: true,
    )) {
      socket.command('close_game');
    }
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.game});

  final GameRef game;

  @override
  Widget build(BuildContext context) {
    final link = game.link;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('PIN игры', style: AppText.muted(13)),
            SelectableText(
              game.pin == null ? '—' : formatPin(game.pin),
              style: AppText.display(36, color: AppColors.gold),
            ),
            if (link != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: link, size: 180, padding: EdgeInsets.zero),
              ),
              const SizedBox(height: 8),
              SelectableText(
                link,
                textAlign: TextAlign.center,
                style: AppText.mono(13, color: AppColors.accent),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) showToast(context, 'Ссылка скопирована', kind: ToastKind.success);
                      },
                      label: const Text('Копировать'),
                    ),
                  ),
                  // Linux has no system share sheet (share_plus would open mail).
                  if (clientPlatform != ClientPlatform.linux) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.share, size: 18),
                        onPressed: () => SharePlus.instance.share(
                          ShareParams(
                            text:
                                'Присоединяйтесь к «${gameTitle(game)}»: $link${game.pin == null ? '' : ' (PIN ${game.pin})'}',
                            subject: 'Своя игра',
                          ),
                        ),
                        label: const Text('Поделиться'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> exportGameFile(BuildContext context) async {
  final api = context.read<Session>().api;
  try {
    final d = await api.exportGame();
    final saved = await saveBytes(d.fileName, d.bytes, mimeType: 'application/json');
    if (saved && context.mounted) showToast(context, 'Игра сохранена: ${d.fileName}', kind: ToastKind.success);
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.text, kind: ToastKind.error);
  } catch (_) {
    if (context.mounted) showToast(context, 'Не удалось сохранить файл', kind: ToastKind.error);
  }
}

Future<void> importGameFile(BuildContext context) async {
  final api = context.read<Session>().api;
  final f = await pickOneFile();
  if (f == null || !context.mounted) return;
  if (!f.name.toLowerCase().endsWith('.json')) {
    showToast(context, 'Нужен файл игры .json', kind: ToastKind.error);
    return;
  }
  if (!await confirm(
    context,
    'Загрузить игру из «${f.name}»?',
    message: 'Пакет, игроки, очки и настройки этой игры будут заменены. PIN и ссылка останутся.',
    ok: 'Загрузить',
  )) {
    return;
  }
  try {
    await api.importGame(await f.readAsBytes());
    if (context.mounted) showToast(context, 'Игра загружена', kind: ToastKind.success);
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.text, kind: ToastKind.error);
  } on Exception {
    if (context.mounted) showToast(context, 'Не удалось прочитать файл', kind: ToastKind.error);
  }
}
