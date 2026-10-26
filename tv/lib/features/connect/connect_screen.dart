import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/server_address.dart';
import '../../core/widgets/stage_background.dart';
import '../../core/widgets/tv_button.dart';
import '../../data/discovery/lan_discovery.dart';
import '../../data/discovery/server_probe.dart';
import '../../data/models/discovered_server.dart';

/// Choose a server: LAN discovery list + manual address. Fully D-pad driven.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _address = TextEditingController();
  final _addressFocus = FocusNode();
  final _rescanFocus = FocusNode();
  List<DiscoveredServer> _found = const [];
  bool _scanning = false;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final saved = widget.controller.server;
    if (saved != null) _address.text = ServerAddress.label(saved);
    _scan();
  }

  @override
  void dispose() {
    _address.dispose();
    _addressFocus.dispose();
    _rescanFocus.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final found = await LanDiscovery.scan();
    if (!mounted) return;
    setState(() {
      _found = found;
      _scanning = false;
    });
    // Nothing to pick: park focus on "search again" (not the text field,
    // which would pop the on-screen keyboard).
    if (found.isEmpty && !_addressFocus.hasFocus) {
      _rescanFocus.requestFocus();
    }
    // Exactly one server and nothing chosen before: just use it.
    final c = widget.controller;
    if (found.length == 1 && c.server == null && !c.isChangingServer) {
      unawaited(c.chooseServer(found.single.base));
    }
  }

  Future<void> _connectManual() async {
    final base = ServerAddress.parse(_address.text);
    if (base == null) {
      setState(() => _error = 'Введите адрес, например 192.168.1.10:3050');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await ServerProbe.info(base);
      if (!mounted) return;
      await widget.controller.chooseServer(base);
    } on ProbeError catch (e) {
      if (mounted) setState(() => _error = '${e.message}: ${ServerAddress.label(base)}');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final canGoBack = c.isChangingServer && c.server != null;
    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.returnToServer();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: StageBackground(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(120, 96, 120, 72),
            child: FocusTraversalGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('СВОЯ ИГРА', style: AppText.displayStyle(72, color: AppColors.gold)),
                  const SizedBox(height: 8),
                  Text('Экран для телевизора — выберите сервер игры',
                      style: AppText.bodyStyle(32, color: AppColors.textMuted)),
                  const SizedBox(height: 64),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _discoveredPanel()),
                        const SizedBox(width: 80),
                        Expanded(child: _manualPanel(canGoBack)),
                      ],
                    ),
                  ),
                  Text(
                    'Игроки подключаются с телефонов, экран только показывает игру.',
                    style: AppText.bodyStyle(24, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _discoveredPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Серверы в сети'),
        const SizedBox(height: 24),
        if (_scanning)
          Row(children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.accent),
            ),
            const SizedBox(width: 20),
            Text('Поиск в локальной сети…', style: AppText.bodyStyle(28, color: AppColors.textMuted)),
          ])
        else if (_found.isEmpty)
          Text('Ничего не найдено. Сервер запущен и в той же сети?',
              style: AppText.bodyStyle(28, color: AppColors.textMuted)),
        for (final (i, s) in _found.indexed)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TvButton(
              expand: true,
              autofocus: i == 0,
              icon: Icons.tv,
              label: s.name,
              subtitle: '${ServerAddress.label(s.base)}${s.version.isEmpty ? '' : '  ·  v${s.version}'}',
              onPressed: () => widget.controller.chooseServer(s.base),
            ),
          ),
        const SizedBox(height: 32),
        TvButton(
          focusNode: _rescanFocus,
          icon: Icons.refresh,
          label: 'Искать снова',
          onPressed: _scanning ? null : _scan,
        ),
      ],
    );
  }

  Widget _manualPanel(bool canGoBack) {
    final saved = widget.controller.server;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Адрес вручную'),
        const SizedBox(height: 24),
        // Single-line text fields swallow ↑/↓; hand them to focus traversal.
        Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp):
                DirectionalFocusIntent(TraversalDirection.up, ignoreTextFields: false),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down, ignoreTextFields: false),
          },
          child: TextField(
            controller: _address,
            focusNode: _addressFocus,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            style: AppText.monoStyle(32, color: AppColors.text),
            decoration: const InputDecoration(hintText: '192.168.1.10:3050'),
            onSubmitted: (_) => _connectManual(),
          ),
        ),
        const SizedBox(height: 24),
        TvButton(
          kind: TvButtonKind.primary,
          icon: Icons.link,
          label: _checking ? 'Проверяем…' : 'Подключиться',
          onPressed: _checking ? null : _connectManual,
        ),
        if (_error != null) ...[
          const SizedBox(height: 20),
          Text(_error!, style: AppText.bodyStyle(26, color: AppColors.danger)),
        ],
        if (canGoBack && saved != null) ...[
          const SizedBox(height: 40),
          TvButton(
            icon: Icons.arrow_back,
            label: 'Вернуться',
            subtitle: ServerAddress.label(saved),
            onPressed: widget.controller.returnToServer,
          ),
        ],
      ],
    );
  }

  Widget _heading(String text) => Text(
        text.toUpperCase(),
        style: AppText.bodyStyle(24, weight: FontWeight.w600, color: AppColors.textMuted)
            .copyWith(letterSpacing: 2),
      );
}
