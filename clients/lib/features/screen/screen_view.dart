import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';
import '../connect/server_screen.dart';
import '../game/blocks_view.dart';
import '../game/board.dart';
import '../game/final_panel.dart';
import '../game/question_panel.dart';
import '../game/scoreboard.dart';
import '../game/session.dart';
import '../game/special.dart';

/// Role `screen`: a read-only display (board, question, scores, who answers).
/// Video and audio autoplay with sound.
class ScreenView extends StatelessWidget {
  const ScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    final session = context.read<Session>();
    final view = socket.view;
    return Scaffold(
      appBar: AppBar(
        title: Text(view == null ? 'Экран' : (view.round?.name ?? gameTitle(view.game)), overflow: TextOverflow.ellipsis),
        actions: sessionActions(context),
      ),
      body: StageBackground(
        child: SafeArea(
          top: false,
          child: view == null
              ? const WaitingForState()
              : Column(children: [
                  HostLine(game: view.game),
                  Scoreboard(view: view),
                  const Divider(),
                  Expanded(child: _content(view, socket, session)),
                ]),
        ),
      ),
    );
  }

  Widget _content(GameView view, GameSocket socket, Session session) {
    switch (view.phase) {
      case Phase.lobby:
        return GameInvite(game: view.game, subtitle: view.pack == null ? 'Ждём выбора пакета' : 'Пакет: ${view.pack!.title}');
      case Phase.board:
        final chooser = view.player(view.chooserId);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Выбирает: ${chooser?.name ?? '—'}', style: AppText.body(15, color: AppColors.gold)),
          ),
          Expanded(child: GameBoard(board: view.board ?? const [])),
        ]);
      case Phase.catTransfer:
        return CatTransferPanel(view: view, canGive: false);
      case Phase.auction:
        return AuctionPanel(view: view, socket: socket);
      case Phase.finalThemes:
      case Phase.finalBets:
      case Phase.finalQuestion:
      case Phase.finalJudging:
      case Phase.finalReveal:
        return FinalPanel(view: view, socket: socket, mode: MediaMode.screen, resolveUrl: session.api.absolute);
      case Phase.question:
      case Phase.answering:
      case Phase.reveal:
        final answering = view.player(view.answeringPlayerId);
        final solo = soloLine(view, null);
        return QuestionPanel(
          view: view,
          mode: MediaMode.screen,
          resolveUrl: session.api.absolute,
          now: () => socket.serverNow,
          footer: view.phase == Phase.answering && answering != null
              ? _Status('Отвечает: ${answering.name}', answering)
              : (view.phase == Phase.question && solo != null ? _Status(solo, view.player(view.soloPlayerId)) : null),
        );
      case Phase.roundEnd:
      case Phase.finished:
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(view.phase == Phase.finished ? 'Игра окончена' : 'Раунд завершён',
              textAlign: TextAlign.center, style: AppText.display(24, color: AppColors.gold)),
          const SizedBox(height: 16),
          Standings(players: view.players),
        ]);
    }
  }
}

String gameTitle(GameRef g) => g.title.isNotEmpty ? g.title : (g.pin == null ? 'Своя игра' : 'Игра ${formatPin(g.pin)}');

/// PIN, link and QR code of a game — the lobby invitation.
class GameInvite extends StatelessWidget {
  const GameInvite({super.key, required this.game, this.subtitle});

  final GameRef game;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(gameTitle(game), textAlign: TextAlign.center, style: AppText.display(22, weight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (game.pin == null)
            Text('Ссылку для входа раздаёт администратор', textAlign: TextAlign.center, style: AppText.muted(15))
          else ...[
            Text('PIN игры', style: AppText.muted(13)),
            Text(formatPin(game.pin), style: AppText.display(40, color: AppColors.gold)),
          ],
          if (game.link != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: game.link!, size: 200, padding: EdgeInsets.zero),
            ),
            const SizedBox(height: 8),
            SelectableText(game.link!, textAlign: TextAlign.center, style: AppText.mono(13, color: AppColors.accent)),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 16),
            Text(subtitle!, textAlign: TextAlign.center, style: AppText.muted(14)),
          ],
        ]),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status(this.text, this.player);

  final String text;
  final PlayerView? player;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: AnsweringLine(text: text, name: player?.name, url: player?.avatarUrl),
      );
}

/// «Ведущий» with the host's avatar (screen role).
class HostLine extends StatelessWidget {
  const HostLine({super.key, required this.game});

  final GameRef game;

  @override
  Widget build(BuildContext context) {
    if (!game.hostTaken) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        Avatar(name: 'Ведущий', url: game.hostAvatarUrl, size: 24),
        const SizedBox(width: 8),
        Text('Ведущий', style: AppText.body(13, weight: FontWeight.w600)),
        const SizedBox(width: 8),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: game.hostConnected ? AppColors.success : AppColors.danger,
          ),
        ),
      ]),
    );
  }
}
