import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../avatar/avatar.dart';

const minOffset = -5000;
const maxOffset = 10000;

/// One player in the admin view: score editing, device, latency, buzzer
/// offset, stats, kick.
class PlayerAdminCard extends StatefulWidget {
  const PlayerAdminCard({super.key, required this.player, required this.socket});

  final PlayerView player;
  final GameSocket socket;

  @override
  State<PlayerAdminCard> createState() => _PlayerAdminCardState();
}

class _PlayerAdminCardState extends State<PlayerAdminCard> {
  /// Slider value while dragging; null = follow the server.
  double? _dragOffset;
  bool _deviceOpen = false;

  PlayerView get p => widget.player;
  GameSocket get socket => widget.socket;

  void _setOffset(int ms) {
    final v = ms.clamp(minOffset, maxOffset);
    socket.command('set_buzz_offset', {'playerId': p.id, 'offsetMs': v});
  }

  Future<void> _editOffset() async {
    final v = await promptText(context, 'Сдвиг кнопки, мс',
        initial: '${p.admin?.buzzOffsetMs ?? 0}', label: '$minOffset…$maxOffset', number: true, signed: true);
    final n = int.tryParse(v ?? '');
    if (n == null) return;
    if (n < minOffset || n > maxOffset) {
      if (mounted) showToast(context, 'Допустимо от $minOffset до $maxOffset мс', kind: ToastKind.error);
      return;
    }
    _setOffset(n);
  }

  Future<void> _customDelta() async {
    final v = await promptText(context, 'Изменить очки на…', label: 'например −300 или 500', number: true, signed: true);
    final n = int.tryParse(v ?? '');
    if (n != null && n != 0) socket.command('adjust_score', {'playerId': p.id, 'delta': n});
  }

  Future<void> _setScore() async {
    final v = await promptText(context, 'Очки игрока ${p.name}', initial: '${p.score}', number: true, signed: true);
    final n = int.tryParse(v ?? '');
    if (n != null) socket.command('set_score', {'playerId': p.id, 'score': n});
  }

  Future<void> _kick() async {
    if (await confirm(context, 'Исключить ${p.name}?', message: 'Игрок будет отключён и потеряет очки.', ok: 'Исключить', danger: true)) {
      socket.command('kick_player', {'playerId': p.id});
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = p.admin;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header: name, status, score.
          Row(children: [
            Avatar(name: p.name, url: p.avatarUrl, size: 40),
            const SizedBox(width: 10),
            StatusDot(ok: p.connected, size: 10),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: AppText.body(17, weight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                Text(
                  p.connected ? 'в сети' : 'не в сети · был ${formatDateTime(a?.lastSeenAt)}',
                  style: AppText.body(12, color: p.connected ? AppColors.success : AppColors.danger),
                ),
              ]),
            ),
            InkWell(
              onTap: _setScore,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(formatScore(p.score),
                    style: AppText.display(24, color: p.score < 0 ? AppColors.danger : AppColors.gold)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          // Score controls.
          Row(children: [
            _ScoreButton(label: '−100', onTap: () => socket.command('adjust_score', {'playerId': p.id, 'delta': -100})),
            const SizedBox(width: 6),
            _ScoreButton(label: '+100', onTap: () => socket.command('adjust_score', {'playerId': p.id, 'delta': 100})),
            const SizedBox(width: 6),
            _ScoreButton(label: '±…', onTap: _customDelta),
            const SizedBox(width: 6),
            _ScoreButton(label: '= …', onTap: _setScore),
          ]),
          if (a != null) ...[
            const Divider(height: 28),
            // Latency.
            Row(children: [
              _Metric(label: 'RTT', value: a.rttMs, color: AppColors.latency(a.rttMs)),
              _Metric(label: 'Среднее', value: a.rttAvgMs, color: AppColors.latency(a.rttAvgMs)),
              _Metric(label: 'Джиттер', value: a.jitterMs, color: AppColors.textMuted),
            ]),
            const SizedBox(height: 4),
            Text('Последний контакт: ${formatDateTime(a.lastSeenAt)}', style: AppText.mono(11, color: AppColors.textMuted)),
            const Divider(height: 28),
            // Buzzer offset.
            Row(children: [
              Expanded(child: Text('Сдвиг кнопки', style: AppText.body(14, weight: FontWeight.w600))),
              InkWell(
                onTap: _editOffset,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('${(_dragOffset?.round() ?? a.buzzOffsetMs)} мс', style: AppText.mono(15)),
                ),
              ),
            ]),
            Slider(
              min: minOffset.toDouble(),
              max: maxOffset.toDouble(),
              divisions: (maxOffset - minOffset) ~/ 50,
              value: (_dragOffset ?? a.buzzOffsetMs.toDouble()).clamp(minOffset.toDouble(), maxOffset.toDouble()),
              label: '${(_dragOffset ?? a.buzzOffsetMs).round()} мс',
              onChanged: (v) => setState(() => _dragOffset = v),
              onChangeEnd: (v) {
                setState(() => _dragOffset = null);
                _setOffset(v.round());
              },
            ),
            Row(children: [
              Expanded(
                child: Text(
                  'Итоговый сдвиг: ${a.effectiveOffsetMs} мс${a.effectiveOffsetMs != a.buzzOffsetMs ? ' (с компенсацией)' : ''}',
                  style: AppText.mono(12, color: AppColors.textMuted),
                ),
              ),
              if (a.buzzOffsetMs != 0) TextButton(onPressed: () => _setOffset(0), child: const Text('Сбросить')),
            ]),
            const Divider(height: 28),
            // Stats.
            Wrap(spacing: 16, runSpacing: 8, children: [
              _Stat(label: 'Верно', value: '${a.stats.correct}', color: AppColors.success),
              _Stat(label: 'Неверно', value: '${a.stats.wrong}', color: AppColors.danger),
              _Stat(label: 'Нажатий', value: '${a.stats.buzzes}'),
              _Stat(label: 'Реакция ср.', value: formatMs(a.stats.avgReactionMs)),
              _Stat(label: 'Лучшая', value: formatMs(a.stats.bestReactionMs)),
            ]),
            const Divider(height: 28),
            // Device.
            InkWell(
              onTap: () => setState(() => _deviceOpen = !_deviceOpen),
              child: Row(children: [
                const Icon(Icons.smartphone, size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [a.device.model, a.device.os].where((s) => s.isNotEmpty).join(' · ').ifEmpty('Устройство неизвестно'),
                    style: AppText.body(13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(_deviceOpen ? Icons.expand_less : Icons.expand_more, color: AppColors.textMuted),
              ]),
            ),
            if (_deviceOpen) ...[
              const SizedBox(height: 8),
              _Kv('Платформа', a.device.platform),
              _Kv('Модель', a.device.model),
              _Kv('ОС', a.device.os),
              _Kv('Версия', a.device.appVersion),
              _Kv('Экран', a.device.screen),
              _Kv('IP', a.device.ip),
              _Kv('User-Agent', a.device.userAgent),
            ],
          ],
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.end, children: [
            if (p.avatarUrl != null)
              TextButton.icon(
                onPressed: () => socket.command('clear_avatar', {'playerId': p.id}),
                icon: const Icon(Icons.hide_image_outlined, size: 18),
                label: const Text('Удалить аватар'),
              ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _kick,
              icon: const Icon(Icons.person_remove, size: 18),
              label: const Text('Исключить'),
            ),
          ]),
        ]),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _ScoreButton extends StatelessWidget {
  const _ScoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 40)),
          onPressed: onTap,
          child: Text(label, style: AppText.mono(14)),
        ),
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final int? value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppText.muted(11)),
          Text(formatMs(value), style: AppText.mono(16, color: color)),
        ]),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color = AppColors.text});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppText.muted(11)),
        Text(value, style: AppText.mono(14, color: color)),
      ]);
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 96, child: Text(k, style: AppText.muted(12))),
          Expanded(child: SelectableText(v.isEmpty ? '—' : v, style: AppText.mono(12))),
        ]),
      );
}
