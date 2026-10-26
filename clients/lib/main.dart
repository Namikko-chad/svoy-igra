import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/platform.dart';
import 'core/prefs.dart';
import 'core/theme.dart';
import 'data/deeplink.dart';
import 'data/device.dart';
import 'data/url_scheme.dart';
import 'features/connect/connect_screen.dart';
import 'features/connect/game_join_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await DeviceHello.collect();
  unawaited(registerUrlScheme());
  // Linux passes the link that started the app only as an argument; Windows
  // and macOS deliver it through the app_links stream as well (repeats ignored).
  final launchLink = isDesktop && args.isNotEmpty ? Uri.tryParse(args.first) : null;
  runApp(SvoyIgraApp(launchLink: launchLink));
}

class SvoyIgraApp extends StatefulWidget {
  const SvoyIgraApp({super.key, this.launchLink});

  /// Desktop: the link passed on the command line at start.
  final Uri? launchLink;

  @override
  State<SvoyIgraApp> createState() => _SvoyIgraAppState();
}

class _SvoyIgraAppState extends State<SvoyIgraApp> {
  final _navigator = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _links;
  GameLink? _last;
  DateTime _lastAt = DateTime(0);

  @override
  void initState() {
    super.initState();
    // Share links (§8): svoyigra://join?server=…&pin=… and https://<host>/g/<pin>.
    // The stream also delivers the link that launched the app.
    try {
      _links = AppLinks().uriLinkStream.listen(_onLink, onError: (Object _) {});
    } catch (_) {
      // No plugin (tests): links are simply not handled.
    }
    final launch = widget.launchLink;
    if (launch != null) WidgetsBinding.instance.addPostFrameCallback((_) => _onLink(launch));
  }

  @override
  void dispose() {
    _links?.cancel();
    super.dispose();
  }

  void _onLink(Uri uri) {
    final link = parseGameLink(uri);
    if (link == null) return;
    // The initial link may be delivered twice (initial + stream); ignore repeats.
    final now = DateTime.now();
    if (link == _last && now.difference(_lastAt) < const Duration(seconds: 3)) return;
    _last = link;
    _lastAt = now;
    Prefs.instance.rememberServer(link.server);
    _navigator.currentState?.push(
      MaterialPageRoute<void>(builder: (_) => GameJoinScreen(baseUrl: link.server, pin: link.pin)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      title: 'Своя игра',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const ConnectScreen(),
    );
  }
}
