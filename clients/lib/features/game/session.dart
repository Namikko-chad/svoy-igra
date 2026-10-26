import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/socket.dart';
import '../admin/admin_screen.dart';
import '../avatar/avatar.dart';
import '../host/host_screen.dart';
import '../player/player_screen.dart';
import '../screen/screen_view.dart';

/// Everything a role screen needs: REST client (with the token), role and the
/// storage key of the seat ([GameSeat.key]).
class Session {
  const Session({required this.api, required this.role, required this.seatKey});

  final Api api;
  final Role role;
  final String seatKey;

  String get baseUrl => api.baseUrl;

  Future<void> forget() => Prefs.instance.removeSeat(baseUrl, seatKey, role);
}

/// Opens the role screen for a stored seat.
Future<void> openSeat(BuildContext context, String baseUrl, GameSeat seat) {
  final session = Session(api: Api(baseUrl, token: seat.token), role: seat.role, seatKey: seat.key);
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SessionScreen(session: session)));
}

/// «Продолжить как …»: validates the token with `/api/auth/me`, then opens it.
/// An unknown token or a deleted game forgets the seat. Throws [ApiException].
Future<void> continueSeat(BuildContext context, String baseUrl, GameSeat seat) async {
  try {
    final me = await Api(baseUrl, token: seat.token).me();
    final sameGame = seat.pin != null ? me.game.pin == seat.pin : me.game.id == seat.gameId;
    if (me.role != seat.role || !sameGame) throw const ApiException('unauthorized', '');
  } on ApiException catch (e) {
    if (e.code == 'unauthorized' || e.code == 'game_not_found' || e.status == 401 || e.status == 404) {
      await Prefs.instance.removeSeat(baseUrl, seat.key, seat.role);
      throw ApiException(e.code, 'Эта сессия больше недействительна — войдите заново');
    }
    rethrow;
  }
  if (context.mounted) await openSeat(context, baseUrl, seat);
}

/// Owns the [GameSocket] for one signed-in role and routes to its screen.
/// Close codes 4001 / 4003 / 4004 forget the token and go back; 4009 offers
/// to reconnect.
class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.session});

  final Session session;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final GameSocket _socket;
  final _subs = <StreamSubscription<Object?>>[];
  bool _leaving = false;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    _socket = GameSocket(baseUrl: s.baseUrl, token: s.api.token!)..connect();
    _socket.addListener(_onSocket);
    _subs.add(_socket.errors.listen(_onError));
    _subs.add(_socket.events.listen(_onEvent));
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _socket.removeListener(_onSocket);
    _socket.dispose();
    super.dispose();
  }

  void _onError(ServerError e) {
    if (!mounted) return;
    showToast(context, describeError(e.code, e.message), kind: ToastKind.error);
  }

  void _onEvent(GameEvent e) {
    final me = _socket.playerId;
    switch (e.kind) {
      case 'question_opened':
        HapticFeedback.selectionClick();
      case 'buzz':
        if (e.playerId == me || s.role == Role.host) HapticFeedback.heavyImpact();
      case 'judged':
        if (e.playerId == me) {
          e.correct ? HapticFeedback.mediumImpact() : HapticFeedback.vibrate();
        }
      case 'timeout':
        HapticFeedback.lightImpact();
      case 'round_started':
      case 'game_finished':
        HapticFeedback.mediumImpact();
      case 'modifier':
        HapticFeedback.heavyImpact();
      case 'cat_given':
        e.toId == me ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
      case 'auction_bid':
      case 'auction_pass':
      case 'final_theme_removed':
        HapticFeedback.selectionClick();
      case 'auction_won':
        e.playerId == me ? HapticFeedback.heavyImpact() : HapticFeedback.lightImpact();
      case 'final_judged':
        if (e.playerId == me) {
          e.correct ? HapticFeedback.mediumImpact() : HapticFeedback.vibrate();
        }
    }
  }

  void _onSocket() {
    final code = _socket.closeCode;
    if (code == null || _leaving) return;
    final msg = switch (code) {
      CloseCodes.kicked => 'Вас исключили из игры',
      CloseCodes.gameClosed => 'Игра закрыта',
      CloseCodes.invalidToken => 'Сессия недействительна — войдите заново',
      _ => null,
    };
    if (msg == null) return;
    _leaving = true;
    s.forget();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    // Close anything opened on top of the session (editor, dialogs), then it.
    nav.popUntil((r) => r == route);
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Session>.value(value: s),
        ChangeNotifierProvider<GameSocket>.value(value: _socket),
      ],
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.of(context).pop();
        },
        child: MediaBase(
          baseUrl: s.baseUrl,
          child: Stack(children: [
          switch (s.role) {
            Role.player => const PlayerScreen(),
            Role.host => const HostScreen(),
            Role.admin => const AdminScreen(),
            Role.screen => const ScreenView(),
          },
          const _ReplacedOverlay(),
          ]),
        ),
      ),
    );
  }
}

class _ReplacedOverlay extends StatelessWidget {
  const _ReplacedOverlay();

  @override
  Widget build(BuildContext context) {
    final socket = context.watch<GameSocket>();
    if (socket.closeCode != CloseCodes.replaced) return const SizedBox.shrink();
    return Positioned.fill(
      child: ColoredBox(
        color: AppColors.bg.withValues(alpha: 0.92),
        child: Material(
          type: MaterialType.transparency,
          child: EmptyState(
            icon: Icons.devices_other,
            title: 'Вы подключились с другого устройства',
            subtitle: 'Это подключение закрыто. Можно вернуть игру сюда.',
            action: FilledButton(onPressed: socket.reconnectNow, child: const Text('Продолжить здесь')),
          ),
        ),
      ),
    );
  }
}

/// App bar badge: connection status of the socket.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<GameSocket, SocketStatus>((s) => s.status);
    final (text, color) = switch (status) {
      SocketStatus.online => ('в сети', AppColors.success),
      SocketStatus.connecting => ('подключение…', AppColors.warning),
      SocketStatus.offline => ('нет связи', AppColors.danger),
      SocketStatus.closed => ('отключено', AppColors.danger),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(text, style: AppText.muted(12)),
      ]),
    );
  }
}

/// Waits for the first `state`.
class WaitingForState extends StatelessWidget {
  const WaitingForState({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<GameSocket, SocketStatus>((s) => s.status);
    return EmptyState(
      title: status == SocketStatus.offline ? 'Нет связи с сервером' : 'Подключение…',
      subtitle: status == SocketStatus.offline ? 'Переподключаемся автоматически' : null,
      action: const CircularProgressIndicator(),
    );
  }
}

/// «Выйти»: sends `leave` (gives the seat up), forgets the token, closes the screen.
Future<void> leaveSession(BuildContext context) async {
  final session = context.read<Session>();
  final socket = context.read<GameSocket>();
  final message = switch (session.role) {
    Role.player => 'Ваше место и очки будут удалены из игры.',
    Role.host => 'Место ведущего освободится — его сможет занять другой.',
    Role.admin => 'Чтобы вернуться, понадобится PIN администратора.',
    Role.screen => 'Экран отключится от игры.',
  };
  if (!await confirm(context, 'Выйти из игры?', message: message, ok: 'Выйти', danger: true) || !context.mounted) return;
  final nav = Navigator.of(context);
  await socket.leave();
  await session.forget();
  nav.pop();
}

/// App bar actions for role screens: connection badge + «Выйти».
List<Widget> sessionActions(BuildContext context) => [
      const ConnectionBadge(),
      IconButton(tooltip: 'Выйти', icon: const Icon(Icons.logout), onPressed: () => leaveSession(context)),
    ];
