import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/stage_scaler.dart';
import 'features/connect/connect_screen.dart';
import 'features/display/display_screen.dart';
import 'features/games/games_screen.dart';
import 'features/pin/pin_screen.dart';

class SvoyIgraTvApp extends StatelessWidget {
  const SvoyIgraTvApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Своя игра — экран',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      darkTheme: AppTheme.build(),
      themeMode: ThemeMode.dark,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      shortcuts: {
        ...WidgetsApp.defaultShortcuts,
        // D-pad centre / OK on Android TV remotes.
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA): const ActivateIntent(),
      },
      builder: (context, child) => StageScaler(child: child ?? const SizedBox()),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final socket = controller.socket;
          final Widget child = switch (controller.stage) {
            AppStage.connect => ConnectScreen(key: const ValueKey('connect'), controller: controller),
            AppStage.games => GamesScreen(key: ValueKey('games-${controller.server}'), app: controller),
            AppStage.pin => PinScreen(key: ValueKey('pin-${controller.server}'), app: controller),
            AppStage.display => DisplayScreen(
                key: ValueKey(socket),
                socket: socket!,
                onChangeGame: controller.changeGame,
                onChangeServer: controller.changeServer,
              ),
          };
          return AnimatedSwitcher(duration: AppTheme.phase(context), child: child);
        },
      ),
    );
  }
}
