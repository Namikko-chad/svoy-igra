import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';

/// Special questions (protocol §4.5): modifier splash, «Кот в мешке» transfer,
/// auction.

IconData modifierIcon(Modifier m) => switch (m) {
      Modifier.cat => Icons.pets,
      Modifier.auction => Icons.gavel,
      Modifier.noRisk => Icons.shield_outlined,
      Modifier.double => Icons.exposure_plus_2,
    };

/// The modifier revealed when a special cell opens: label + stake, scaled in.
class ModifierSplash extends StatelessWidget {
  const ModifierSplash({super.key, required this.question, this.compact = false});

  final QuestionView question;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m = question.modifier;
    if (m == null) return const SizedBox.shrink();
    final stakeText = switch (m) {
      Modifier.auction => question.stake > question.value ? 'Ставка: ${formatScore(question.stake)}' : null,
      _ => 'Стоимость: ${formatScore(question.stake)}',
    };
    return TweenAnimationBuilder<double>(
      key: ValueKey('mod:${question.id}:${m.name}'),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 10 : 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold, width: 2),
          boxShadow: AppColors.goldGlow,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(modifierIcon(m), color: AppColors.gold, size: compact ? 22 : 30),
          const SizedBox(width: 12),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.label, style: AppText.display(compact ? 16 : 22, color: AppColors.gold)),
              if (stakeText != null) Text(stakeText, style: AppText.mono(14)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Category + value header used before the question is shown.
class _CellHeader extends StatelessWidget {
  const _CellHeader({required this.question});

  final QuestionView question;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(
            question.categoryName.toUpperCase(),
            style: AppText.body(13, weight: FontWeight.w600, color: AppColors.textMuted),
          ),
        ),
        Text('${question.value}', style: AppText.display(24, color: AppColors.gold)),
      ]);
}

/// Phase `cat_transfer`: the chooser (or the host on their behalf) gives the
/// question to another player; everybody else sees who is choosing.
class CatTransferPanel extends StatelessWidget {
  const CatTransferPanel({super.key, required this.view, required this.canGive, this.onGive, this.meId});

  final GameView view;
  final bool canGive;
  final void Function(String playerId)? onGive;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final q = view.question;
    final chooser = view.player(view.chooserId);
    final others = view.players.where((p) => p.id != view.chooserId).toList();
    final targets = others.any((p) => p.connected) ? others : view.players;
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (q != null) ...[_CellHeader(question: q), const SizedBox(height: 12), ModifierSplash(question: q)],
      const SizedBox(height: 20),
      if (canGive) ...[
        Text(
          meId != null && meId == view.chooserId ? 'Кому отдать кота в мешке?' : 'Кому отдаёт ${chooser?.name ?? 'выбирающий'}?',
          textAlign: TextAlign.center,
          style: AppText.display(18, weight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        for (final p in targets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              key: ValueKey('give:${p.id}'),
              onPressed: () {
                HapticFeedback.selectionClick();
                onGive?.call(p.id);
              },
              child: Row(children: [
                Avatar(name: p.name, url: p.avatarUrl, size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text(p.name)),
                Icon(Icons.circle, size: 8, color: p.connected ? AppColors.success : AppColors.danger),
                const SizedBox(width: 10),
                Text(formatScore(p.score), style: AppText.display(14, color: AppColors.gold)),
              ]),
            ),
          ),
      ] else
        Text(
          'Кота в мешке отдаёт: ${chooser?.name ?? '—'}',
          textAlign: TextAlign.center,
          style: AppText.body(16, color: AppColors.textMuted),
        ),
    ]);
  }
}

/// Phase `auction`: state for everyone; on my turn — amount (+100 steps),
/// «Ставка», «Ва-банк», «Пас». The host can close the bidding.
class AuctionPanel extends StatefulWidget {
  const AuctionPanel({super.key, required this.view, required this.socket, this.me, this.hostControls = false});

  final GameView view;
  final GameSocket socket;
  final MeView? me;
  final bool hostControls;

  @override
  State<AuctionPanel> createState() => _AuctionPanelState();
}

class _AuctionPanelState extends State<AuctionPanel> {
  int? _amount;

  /// Next legal bid: the high bid + 100, capped by my score.
  static int suggestedBid(int highBid, int myScore) => (highBid + 100) > myScore ? myScore : highBid + 100;

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final a = view.auction;
    final q = view.question;
    if (a == null) return const SizedBox.shrink();
    final me = widget.me;
    final myScore = me?.score ?? 0;
    final canBid = me?.canBid ?? false;
    final minBid = a.highBid + 1;
    final canRaise = canBid && !a.allIn && myScore > a.highBid;
    final amount = (_amount ?? suggestedBid(a.highBid, myScore)).clamp(minBid, myScore < minBid ? minBid : myScore);
    final bidder = view.player(a.highBidderId);
    final turn = view.player(a.turnPlayerId);
    return ListView(padding: const EdgeInsets.all(16), children: [
      if (q != null) ...[_CellHeader(question: q), const SizedBox(height: 12), ModifierSplash(question: q, compact: true)],
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text('Высшая ставка', style: AppText.muted(13)),
            Text(formatScore(a.highBid), style: AppText.display(36, color: AppColors.gold)),
            if (a.allIn) Text('ВА-БАНК', style: AppText.display(14, color: AppColors.danger)),
            Text(bidder?.name ?? '—', style: AppText.body(16, weight: FontWeight.w600)),
            const Divider(height: 24),
            Text(
              a.turnPlayerId == null
                  ? 'Торги окончены'
                  : (canBid ? 'Ваш ход' : 'Ходит: ${turn?.name ?? '—'}'),
              style: AppText.body(15, weight: FontWeight.w600, color: canBid ? AppColors.accent : AppColors.text),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
              for (final p in view.players)
                Chip(
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(p.name),
                    if (a.passedPlayerIds.contains(p.id)) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.block, size: 14, color: AppColors.textMuted),
                    ] else if (p.id == a.highBidderId) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.gavel, size: 14, color: AppColors.gold),
                    ],
                  ]),
                  avatar: Avatar(name: p.name, url: p.avatarUrl, size: 24),
                  side: BorderSide(color: p.id == a.turnPlayerId ? AppColors.accent : AppColors.border),
                  labelStyle: AppText.body(13, color: a.passedPlayerIds.contains(p.id) ? AppColors.textMuted : AppColors.text),
                ),
            ]),
            if (a.passedPlayerIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Пас: ${a.passedPlayerIds.map((id) => view.player(id)?.name ?? '?').join(', ')}',
                    style: AppText.muted(12)),
              ),
          ]),
        ),
      ),
      if (canBid) ...[
        const SizedBox(height: 16),
        if (canRaise)
          Row(children: [
            IconButton.outlined(
              tooltip: '−100',
              onPressed: amount - 100 >= minBid ? () => setState(() => _amount = amount - 100) : null,
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _editAmount(context, minBid, myScore),
                child: Text(formatScore(amount), textAlign: TextAlign.center, style: AppText.display(28)),
              ),
            ),
            IconButton.outlined(
              tooltip: '+100',
              onPressed: amount + 100 <= myScore ? () => setState(() => _amount = amount + 100) : null,
              icon: const Icon(Icons.add),
            ),
          ]),
        const SizedBox(height: 12),
        Row(children: [
          if (canRaise) ...[
            Expanded(
              child: FilledButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  widget.socket.command('auction_bid', {'amount': amount});
                  setState(() => _amount = null);
                },
                child: const Text('Ставка'),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.text),
              onPressed: myScore > a.highBid
                  ? () {
                      HapticFeedback.heavyImpact();
                      widget.socket.command('auction_all_in');
                    }
                  : null,
              child: const Text('Ва-банк'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(onPressed: () => widget.socket.command('auction_pass'), child: const Text('Пас')),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Ваши очки: ${formatScore(myScore)}', textAlign: TextAlign.center, style: AppText.muted(12)),
        ),
      ],
      if (widget.hostControls) ...[
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.gavel),
          onPressed: () => widget.socket.command('auction_close'),
          label: const Text('Закрыть торги'),
        ),
      ],
    ]);
  }

  Future<void> _editAmount(BuildContext context, int min, int max) async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ваша ставка'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'от $min до $max'),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    final n = int.tryParse(v ?? '');
    if (n != null && mounted) setState(() => _amount = n.clamp(min, max));
  }
}

/// «Отвечает <имя>» for solo questions (no buttons).
String? soloLine(GameView view, String? meId) {
  final solo = view.player(view.soloPlayerId);
  if (solo == null || view.phase == Phase.reveal) return null;
  return solo.id == meId ? 'Отвечаете вы — кнопок нет' : 'Отвечает ${solo.name}';
}
