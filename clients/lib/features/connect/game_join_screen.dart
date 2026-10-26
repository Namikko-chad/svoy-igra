import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../avatar/avatar_editor.dart';
import '../game/session.dart';
import 'server_screen.dart';

/// Step 2 of joining: the game is known by PIN, choose a role.
/// Also the target of share links / deep links.
class GameJoinScreen extends StatefulWidget {
  const GameJoinScreen({super.key, required this.baseUrl, required this.pin});

  final String baseUrl;
  final String pin;

  @override
  State<GameJoinScreen> createState() => _GameJoinScreenState();
}

class _GameJoinScreenState extends State<GameJoinScreen> {
  final _name = TextEditingController();
  final _adminPin = TextEditingController();
  GameInfo? _game;
  String? _error;
  String? _busy;

  String get base => widget.baseUrl;
  Api get _api => Api(base);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _adminPin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final g = await _api.gameInfo(widget.pin);
      await Prefs.instance.rememberServer(base);
      if (mounted) {
        setState(() {
          _game = g;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.text);
    }
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.text, kind: ToastKind.error);
      if (e.code == 'host_taken') await _load();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _join(Role role, {String? name, String? adminPin}) => _run(role.name, () async {
        final r = await _api.joinGame(widget.pin, role, name: name, adminPin: adminPin);
        final seat = GameSeat.fromJoin(r);
        await Prefs.instance.saveSeat(base, seat);
        _adminPin.clear();
        // Players and the host may set an avatar right away.
        if ((role == Role.player || role == Role.host) && mounted) {
          await editMyAvatar(context, Api(base, token: r.token), offer: true);
        }
        if (mounted) await openSeat(context, base, seat);
        if (mounted) await _load();
      });

  void _joinPlayer() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 32) {
      showToast(context, 'Имя должно быть от 1 до 32 символов', kind: ToastKind.error);
      return;
    }
    _join(Role.player, name: name);
  }

  void _joinAdmin() {
    final pin = _adminPin.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      showToast(context, 'PIN администратора — от 4 до 8 цифр', kind: ToastKind.error);
      return;
    }
    _join(Role.admin, adminPin: pin);
  }

  @override
  Widget build(BuildContext context) {
    final g = _game;
    final seats = Prefs.instance.seatsForGame(base, widget.pin);
    return Scaffold(
      appBar: AppBar(
        title: Text('Игра ${formatPin(widget.pin)}'),
        actions: [IconButton(tooltip: 'Обновить', icon: const Icon(Icons.refresh), onPressed: _load)],
      ),
      body: StageBackground(
        child: g == null
            ? (_error == null
                ? const Center(child: CircularProgressIndicator())
                : EmptyState(
                    icon: Icons.search_off,
                    title: _error!,
                    subtitle: '$base · PIN ${formatPin(widget.pin)}',
                    action: OutlinedButton(onPressed: _load, child: const Text('Повторить')),
                  ))
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    _GameCard(game: g),
                    if (seats.isNotEmpty) ...[
                      const SectionTitle('Продолжить'),
                      for (final s in seats)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: FilledButton.icon(
                            icon: Icon(roleIcon(s.role)),
                            onPressed: _busy != null
                                ? null
                                : () => _run('c${s.role.name}', () async {
                                      await continueSeat(context, base, s);
                                      if (mounted) await _load();
                                    }),
                            label: Text('Продолжить как ${s.label}'),
                          ),
                        ),
                    ],
                    const SectionTitle('Игрок'),
                    _Panel(children: [
                      TextField(
                        controller: _name,
                        maxLength: 32,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Ваше имя', counterText: ''),
                        onSubmitted: (_) => _joinPlayer(),
                      ),
                      const SizedBox(height: 12),
                      _Action(label: 'Играть', busy: _busy == 'player', onPressed: _busy != null ? null : _joinPlayer, primary: true),
                    ]),
                    const SectionTitle('Ведущий'),
                    _Panel(children: [
                      if (g.hostTaken)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text('Ведущий уже подключён', style: AppText.body(13, color: AppColors.warning)),
                        ),
                      _Action(
                        label: 'Вести игру',
                        busy: _busy == 'host',
                        onPressed: _busy != null || g.hostTaken ? null : () => _join(Role.host),
                      ),
                    ]),
                    const SectionTitle('Экран'),
                    _Panel(children: [
                      Text('${isDesktop ? 'Компьютер' : 'Телефон'} покажет табло и вопросы без кнопки ответа.', style: AppText.muted(13)),
                      const SizedBox(height: 8),
                      _Action(
                        label: 'Открыть как экран',
                        busy: _busy == 'screen',
                        onPressed: _busy != null ? null : () => _join(Role.screen),
                      ),
                    ]),
                    const SectionTitle('Администратор'),
                    _Panel(children: [
                      TextField(
                        controller: _adminPin,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                        decoration: const InputDecoration(labelText: 'PIN администратора'),
                        onSubmitted: (_) => _joinAdmin(),
                      ),
                      const SizedBox(height: 12),
                      _Action(label: 'Войти как администратор', busy: _busy == 'admin', onPressed: _busy != null ? null : _joinAdmin),
                    ]),
                    const SizedBox(height: 24),
                  ]),
                ),
              ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});

  final GameInfo game;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(game.title.isEmpty ? 'Своя игра' : game.title, style: AppText.display(20, weight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (game.pin != null) Text('PIN ${formatPin(game.pin)}', style: AppText.mono(16, color: AppColors.gold)),
          const SizedBox(height: 8),
          Text(
            [
              game.phase.label,
              if (game.pack != null) 'пакет «${game.pack!.title}»',
              'игроков: ${game.players}',
            ].join(' · '),
            style: AppText.muted(13),
          ),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.busy, required this.onPressed, this.primary = false});

  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : Text(label);
    return primary
        ? FilledButton(onPressed: onPressed, child: child)
        : OutlinedButton(onPressed: onPressed, child: child);
  }
}
