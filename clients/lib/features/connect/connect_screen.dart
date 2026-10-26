import 'package:flutter/material.dart';

import '../../core/platform.dart';
import '../../core/prefs.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/api.dart';
import '../../data/discovery.dart';
import 'server_screen.dart';

/// First screen: LAN discovery, recent servers and manual address entry.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _address = TextEditingController();
  List<DiscoveredServer> _found = const [];
  bool _searching = false;
  String? _connecting;

  @override
  void initState() {
    super.initState();
    _address.text = Prefs.instance.lastServer ?? '';
    _search();
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final found = await discoverServers();
      if (mounted) setState(() => _found = found);
    } catch (_) {
      // Discovery is best-effort; manual entry stays available.
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _connect(String input) async {
    final base = normalizeBaseUrl(input);
    if (base == null) {
      showToast(context, 'Неверный адрес сервера', kind: ToastKind.error);
      return;
    }
    setState(() => _connecting = base);
    try {
      final info = await Api(base).info();
      await Prefs.instance.rememberServer(base);
      if (!mounted) return;
      _address.text = base;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ServerScreen(baseUrl: base, info: info)));
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) showToast(context, '${e.text}: $base', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _connecting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recent = Prefs.instance.recentServers;
    return Scaffold(
      body: StageBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: RefreshIndicator(
                onRefresh: _search,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 24),
                    Text('СВОЯ ИГРА', textAlign: TextAlign.center, style: AppText.display(32, color: AppColors.gold)),
                    const SizedBox(height: 8),
                    Text('Подключение к серверу', textAlign: TextAlign.center, style: AppText.muted(14)),
                    const SizedBox(height: 24),
                    SectionTitle(
                      'Серверы в сети',
                      trailing: _searching
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              tooltip: 'Искать снова',
                              icon: const Icon(Icons.refresh),
                              onPressed: _search,
                            ),
                    ),
                    if (_found.isEmpty && !_searching)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text(
                          'Серверы не найдены. Проверьте, что ${isDesktop ? 'компьютер' : 'телефон'} в той же сети, что и сервер, или введите адрес вручную.',
                          style: AppText.muted(14),
                        ),
                      ),
                    for (final s in _found)
                      _ServerTile(
                        title: s.name,
                        subtitle: '${s.baseUrl}${s.version.isEmpty ? '' : ' · v${s.version}'}',
                        icon: Icons.wifi_tethering,
                        busy: _connecting == s.baseUrl,
                        onTap: () => _connect(s.baseUrl),
                      ),
                    const SectionTitle('Адрес вручную'),
                    TextField(
                      controller: _address,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(hintText: 'http://192.168.1.10:3050'),
                      onSubmitted: _connect,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _connecting != null ? null : () => _connect(_address.text),
                      child: const Text('Подключиться'),
                    ),
                    if (recent.isNotEmpty) ...[
                      const SectionTitle('Недавние'),
                      for (final r in recent)
                        _ServerTile(
                          title: r,
                          icon: Icons.history,
                          busy: _connecting == r,
                          onTap: () => _connect(r),
                          onRemove: () async {
                            await Prefs.instance.forgetServer(r);
                            setState(() {});
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.busy,
    required this.onTap,
    this.onRemove,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(icon, color: AppColors.accent),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!, style: AppText.mono(12, color: AppColors.textMuted)),
          trailing: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : onRemove == null
                  ? const Icon(Icons.chevron_right)
                  : IconButton(tooltip: 'Убрать', icon: const Icon(Icons.close), onPressed: onRemove),
          onTap: busy ? null : onTap,
        ),
      ),
    );
  }
}
