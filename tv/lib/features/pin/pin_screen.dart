import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/server_address.dart';
import '../../core/widgets/stage_background.dart';
import '../../core/widgets/tv_button.dart';
import '../../data/models/game_info.dart';
import 'pin_controller.dart';

/// Game PIN entry: a D-pad digit pad (remote number keys work too), then the
/// found game's card with «Показать игру».
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, required this.app});

  final AppController app;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  late final PinController _pin = PinController(widget.app.api);
  final _joinFocus = FocusNode(debugLabel: 'join');
  final _firstKeyFocus = FocusNode(debugLabel: 'pad-1');

  static final _digitKeys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit0: 0, LogicalKeyboardKey.numpad0: 0,
    LogicalKeyboardKey.digit1: 1, LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.digit2: 2, LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.digit3: 3, LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.digit4: 4, LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.digit5: 5, LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.digit6: 6, LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.digit7: 7, LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.digit8: 8, LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.digit9: 9, LogicalKeyboardKey.numpad9: 9,
  };

  @override
  void initState() {
    super.initState();
    _pin.addListener(_onPin);
  }

  @override
  void dispose() {
    _pin.removeListener(_onPin);
    _pin.dispose();
    _joinFocus.dispose();
    _firstKeyFocus.dispose();
    super.dispose();
  }

  PinStatus? _lastStatus;

  void _onPin() {
    final status = _pin.status;
    if (status == PinStatus.found && _lastStatus != PinStatus.found && _lastStatus != PinStatus.joining) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _joinFocus.requestFocus();
      });
    }
    _lastStatus = status;
  }

  Future<void> _join() async {
    final result = await _pin.join();
    if (result != null && mounted) await widget.app.joined(result);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final digit = _digitKeys[event.logicalKey];
    if (digit != null) {
      _pin.addDigit(digit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      _pin.backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final server = widget.app.server;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.app.backToGames();
      },
      child: Focus(
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: StageBackground(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(120, 96, 120, 72),
              child: ListenableBuilder(
                listenable: _pin,
                builder: (context, _) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _left(server)),
                    const SizedBox(width: 96),
                    FocusTraversalGroup(child: _pad()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _left(Uri? server) {
    final game = _pin.game;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('СВОЯ ИГРА', style: AppText.displayStyle(56, color: AppColors.gold)),
        const SizedBox(height: 8),
        Text(
          'Введите PIN игры${server == null ? '' : ' · сервер ${ServerAddress.label(server)}'}',
          style: AppText.bodyStyle(30, color: AppColors.textMuted),
        ),
        const SizedBox(height: 48),
        _PinBoxes(digits: _pin.digits, busy: _pin.status == PinStatus.looking),
        const SizedBox(height: 24),
        SizedBox(
          height: 44,
          child: _pin.message == null
              ? (_pin.status == PinStatus.looking
                  ? Text('Ищем игру…', style: AppText.bodyStyle(30, color: AppColors.textMuted))
                  : null)
              : Text(_pin.message!, style: AppText.bodyStyle(30, weight: FontWeight.w600, color: AppColors.danger)),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: AppTheme.phase(context),
          child: game == null
              ? Text(
                  'PIN — 6 цифр, его показывает ведущий или администратор игры.\n'
                  'Цифры можно набирать и кнопками пульта.',
                  key: const ValueKey('hint'),
                  style: AppText.bodyStyle(26, color: AppColors.textMuted),
                )
              : _GameCard(
                  key: ValueKey(game.id),
                  game: game,
                  joining: _pin.status == PinStatus.joining,
                  joinFocus: _joinFocus,
                  onJoin: _join,
                  onOther: () {
                    _pin.clear();
                    _firstKeyFocus.requestFocus();
                  },
                ),
        ),
      ],
    );
  }

  Widget _pad() {
    Widget key(String label, VoidCallback onTap, {FocusNode? focus, bool autofocus = false, IconData? icon}) =>
        Padding(
          padding: const EdgeInsets.all(8),
          child: _PadKey(label: label, icon: icon, onTap: onTap, focusNode: focus, autofocus: autofocus),
        );
    Widget digit(int d) => key('$d', () => _pin.addDigit(d),
        focus: d == 1 ? _firstKeyFocus : null, autofocus: d == 1);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ])
          Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) digit(d)]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          key('Стереть', _pin.backspace, icon: Icons.backspace_outlined),
          digit(0),
          key('Очистить', _pin.clear, icon: Icons.clear),
        ]),
        const SizedBox(height: 24),
        TvButton(
          icon: Icons.view_list,
          label: 'К списку игр',
          onPressed: widget.app.backToGames,
        ),
      ],
    );
  }
}

class _PinBoxes extends StatelessWidget {
  const _PinBoxes({required this.digits, required this.busy});

  final String digits;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < PinController.length; i++) ...[
          if (i == 3) const SizedBox(width: 24),
          Container(
            width: 112,
            height: 136,
            margin: const EdgeInsets.only(right: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: i == digits.length && !busy ? AppColors.accent : AppColors.border,
                width: i == digits.length && !busy ? 3 : 1,
              ),
            ),
            child: Text(
              i < digits.length ? digits[i] : '',
              style: AppText.displayStyle(72, color: AppColors.gold, tabular: true),
            ),
          ),
        ],
      ],
    );
  }
}

class _GameCard extends StatelessWidget {
  const _GameCard({
    super.key,
    required this.game,
    required this.joining,
    required this.joinFocus,
    required this.onJoin,
    required this.onOther,
  });

  final GameInfo game;
  final bool joining;
  final FocusNode joinFocus;
  final VoidCallback onJoin;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.accentGlow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            game.title.isEmpty ? 'Игра ${game.pin ?? ''}'.trim() : game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.displayStyle(40),
          ),
          const SizedBox(height: 8),
          Text(
            [
              game.pack == null ? 'пакет не выбран' : 'пакет «${game.pack!.title}»',
              game.phaseLabel,
              'игроков: ${game.players}',
            ].join('  ·  '),
            style: AppText.bodyStyle(26, color: AppColors.textMuted),
          ),
          const SizedBox(height: 28),
          FocusTraversalGroup(
            child: Row(children: [
              TvButton(
                kind: TvButtonKind.primary,
                focusNode: joinFocus,
                icon: Icons.tv,
                label: joining ? 'Подключаем…' : 'Показать игру',
                onPressed: joining ? null : onJoin,
              ),
              const SizedBox(width: 20),
              TvButton(
                icon: Icons.dialpad,
                label: 'Другой PIN',
                onPressed: joining ? null : onOther,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

/// One digit-pad key with the accent focus ring.
class _PadKey extends StatefulWidget {
  const _PadKey({
    required this.label,
    required this.onTap,
    this.icon,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<_PadKey> createState() => _PadKeyState();
}

class _PadKeyState extends State<_PadKey> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onTap();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppTheme.fast(context),
          curve: Curves.easeOut,
          width: 136,
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _focused ? AppColors.cellHover : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _focused ? AppColors.accent : AppColors.border, width: _focused ? 4 : 1),
            boxShadow: _focused ? AppColors.accentGlow : null,
          ),
          child: widget.icon != null
              ? Icon(widget.icon, size: 44, color: AppColors.text, semanticLabel: widget.label)
              : Text(widget.label, style: AppText.displayStyle(48, tabular: true)),
        ),
      ),
    );
  }
}
