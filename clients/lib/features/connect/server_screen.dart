import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../game/session.dart';
import 'game_join_screen.dart';

/// After choosing a server: continue a stored seat, join a game by PIN, or
/// create a new game (becoming its admin).
class ServerScreen extends StatefulWidget {
  const ServerScreen({super.key, required this.baseUrl, required this.info});

  final String baseUrl;
  final ServerInfo info;

  @override
  State<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends State<ServerScreen> {
  final _pin = TextEditingController();
  final _title = TextEditingController();
  final _adminPin = TextEditingController();
  final _adminPin2 = TextEditingController();
  String? _busy;
  List<GameInfo>? _games;

  String get base => widget.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  Future<void> _loadGames() async {
    try {
      final games = await Api(base).listGames();
      if (mounted) setState(() => _games = games);
    } on ApiException {
      if (mounted) setState(() => _games = const []);
    }
  }

  Future<void> _openGame(String pin) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameJoinScreen(baseUrl: base, pin: pin)));
    if (mounted) setState(() {});
    await _loadGames();
  }

  @override
  void dispose() {
    for (final c in [_pin, _title, _adminPin, _adminPin2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _join() async {
    final pin = _pin.text.replaceAll(RegExp(r'\D'), '');
    if (pin.length != 6) {
      showToast(context, 'PIN игры — 6 цифр', kind: ToastKind.error);
      return;
    }
    await _openGame(pin);
  }

  /// Public list → only «Смотреть (экран)» via `watch`; the PIN is never shown.
  Future<void> _watch(GameInfo g) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(g.title.isEmpty ? 'Своя игра' : g.title, style: AppText.display(18, weight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              [g.phase.label, if (g.pack != null) 'пакет «${g.pack!.title}»', 'игроков: ${g.players}'].join(' · '),
              style: AppText.muted(13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.tv),
              onPressed: () => Navigator.pop(ctx, true),
              label: const Text('Смотреть (экран)'),
            ),
            const SizedBox(height: 12),
            Text(
              'Чтобы играть, вести игру или управлять ею, нужен PIN игры — его даёт администратор. '
              'Введите его в поле «Войти в игру».',
              style: AppText.muted(12),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _run('watch', () async {
      final r = await Api(base).watchGame(g.id);
      final seat = GameSeat.fromJoin(r);
      await Prefs.instance.saveSeat(base, seat);
      if (mounted) await openSeat(context, base, seat);
      if (mounted) setState(() {});
    });
    await _loadGames();
  }

  Future<void> _create() => _run('create', () async {
        final pin = _adminPin.text.trim();
        if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
          showToast(context, 'PIN администратора — от 4 до 8 цифр', kind: ToastKind.error);
          return;
        }
        if (pin != _adminPin2.text.trim()) {
          showToast(context, 'PIN-коды не совпадают', kind: ToastKind.error);
          return;
        }
        final title = _title.text.trim();
        final r = await Api(base).createGame(pin, title: title.isEmpty ? null : title);
        final seat = GameSeat.fromJoin(r);
        await Prefs.instance.saveSeat(base, seat);
        _adminPin.clear();
        _adminPin2.clear();
        _title.clear();
        if (mounted) await openSeat(context, base, seat);
        if (mounted) setState(() {});
      });

  Future<void> _continue(GameSeat seat) => _run('seat:${seat.key}:${seat.role.name}', () async {
        await continueSeat(context, base, seat);
        if (mounted) setState(() {});
      });

  @override
  Widget build(BuildContext context) {
    final seats = Prefs.instance.seats(base);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.info.name),
        actions: [IconButton(tooltip: 'Обновить', icon: const Icon(Icons.refresh), onPressed: _loadGames)],
      ),
      body: StageBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(base, style: AppText.mono(12, color: AppColors.textMuted)),
                if (seats.isNotEmpty) ...[
                  const SectionTitle('Мои игры'),
                  for (final s in seats)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Icon(roleIcon(s.role), color: AppColors.accent),
                          title: Text(s.title.isNotEmpty ? s.title : (s.pin == null ? 'Своя игра' : 'Игра ${formatPin(s.pin)}')),
                          subtitle: Text(
                            s.pin == null ? '${s.label} · просмотр' : 'PIN ${formatPin(s.pin)} · ${s.label}',
                            style: AppText.muted(12),
                          ),
                          trailing: _busy == 'seat:${s.key}:${s.role.name}'
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  tooltip: 'Забыть',
                                  icon: const Icon(Icons.close),
                                  onPressed: () async {
                                    await Prefs.instance.removeSeat(base, s.key, s.role);
                                    setState(() {});
                                  },
                                ),
                          onTap: _busy != null ? null : () => _continue(s),
                        ),
                      ),
                    ),
                ],
                const SectionTitle('Войти в игру'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: _pin,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        textAlign: TextAlign.center,
                        style: AppText.mono(28),
                        decoration: const InputDecoration(hintText: 'PIN игры', counterText: ''),
                        onSubmitted: (_) => _join(),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: _busy != null ? null : _join, child: const Text('Далее')),
                    ]),
                  ),
                ),
                if (_games != null && _games!.isNotEmpty) ...[
                  const SectionTitle('Игры на сервере'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                    child: Text(
                      'Отсюда игру можно только смотреть как экран. Чтобы играть, '
                      'введите PIN от администратора в поле «Войти в игру».',
                      style: AppText.muted(12),
                    ),
                  ),
                  for (final g in _games!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: const Icon(Icons.tv, color: AppColors.accent),
                          title: Text(g.title.isEmpty ? 'Своя игра' : g.title),
                          subtitle: Text(
                            [
                              g.phase.label,
                              if (g.pack != null) '«${g.pack!.title}»',
                              'игроков: ${g.players}',
                            ].join(' · '),
                            style: AppText.muted(12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _busy != null ? null : () => _watch(g),
                        ),
                      ),
                    ),
                ],
                const SectionTitle('Создать игру'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      TextField(
                        controller: _title,
                        maxLength: 60,
                        decoration: const InputDecoration(labelText: 'Название (необязательно)', counterText: ''),
                      ),
                      const SizedBox(height: 12),
                      _PinInput(controller: _adminPin, label: 'PIN администратора (4–8 цифр)'),
                      const SizedBox(height: 12),
                      _PinInput(controller: _adminPin2, label: 'Повторите PIN', onSubmit: _create),
                      const SizedBox(height: 8),
                      Text(
                        'Вы станете администратором игры: выберете пакет, настроите игру и раздадите ссылку.',
                        style: AppText.muted(12),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _busy != null ? null : _create,
                        child: _busy == 'create'
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Создать игру'),
                      ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PinInput extends StatelessWidget {
  const _PinInput({required this.controller, required this.label, this.onSubmit});

  final TextEditingController controller;
  final String label;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
        decoration: InputDecoration(labelText: label),
        onSubmitted: onSubmit == null ? null : (_) => onSubmit!(),
      );
}

/// `123456` → `123 456`.
String formatPin(String? pin) => pin == null ? '' : (pin.length == 6 ? '${pin.substring(0, 3)} ${pin.substring(3)}' : pin);

IconData roleIcon(Role r) => switch (r) {
      Role.player => Icons.person,
      Role.host => Icons.mic,
      Role.admin => Icons.admin_panel_settings,
      Role.screen => Icons.tv,
    };
