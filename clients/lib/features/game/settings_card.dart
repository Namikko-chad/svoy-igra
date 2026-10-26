import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/socket.dart';

/// Game settings (`update_settings`). The host changes timings and the penalty;
/// the admin also toggles latency compensation.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.settings, required this.socket, required this.canCompensate});

  final Settings? settings;
  final GameSocket socket;
  final bool canCompensate;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (s == null) return Text('Настройки недоступны', style: AppText.muted(14));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Column(children: [
          _NumberSetting(
            title: 'Время на чтение',
            subtitle: 'Общий таймер после показа вопроса, с',
            value: s.readingSeconds,
            min: 1,
            max: 120,
            onChanged: (v) => socket.command('update_settings', {'readingSeconds': v}),
          ),
          const Divider(),
          _NumberSetting(
            title: 'Окно для ответа',
            subtitle: 'Сколько кнопка открыта после чтения, с',
            value: s.buzzSeconds,
            min: 3,
            max: 300,
            onChanged: (v) => socket.command('update_settings', {'buzzSeconds': v}),
          ),
          const Divider(),
          SwitchListTile(
            title: const Text('Штраф за неверный ответ'),
            subtitle: Text('Вычитать стоимость вопроса', style: AppText.muted(12)),
            value: s.wrongPenalty,
            onChanged: (v) => socket.command('update_settings', {'wrongPenalty': v}),
          ),
          const Divider(),
          _NumberSetting(
            title: 'Время на ответ в финале',
            subtitle: 'Сколько финалисты пишут ответ, с',
            value: s.finalSeconds,
            min: 10,
            max: 300,
            onChanged: (v) => socket.command('update_settings', {'finalSeconds': v}),
          ),
          const Divider(),
          if (canCompensate)
            SwitchListTile(
              title: const Text('Автокомпенсация задержки'),
              subtitle: Text('Открывать кнопку раньше на половину средней задержки (RTT/2)', style: AppText.muted(12)),
              value: s.autoLatencyCompensation,
              onChanged: (v) => socket.command('update_settings', {'autoLatencyCompensation': v}),
            )
          else
            ListTile(
              title: const Text('Компенсация задержки'),
              subtitle: Text('Меняет администратор', style: AppText.muted(12)),
              trailing: Text(s.autoLatencyCompensation ? 'вкл' : 'выкл', style: AppText.mono(14)),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text('Изменения действуют со следующего вопроса.', style: AppText.muted(12)),
      ),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text('СПЕЦИАЛЬНЫЕ ВОПРОСЫ В РАУНДЕ', style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textMuted)),
      ),
      Card(
        child: Column(children: [
          for (final (i, m) in Modifier.values.indexed) ...[
            if (i > 0) const Divider(),
            _NumberSetting(
              key: ValueKey('mod:${m.name}'),
              title: m.label,
              subtitle: 'Сколько клеток на раунд (0–5)',
              value: s.modifiers.of(m),
              min: 0,
              max: 5,
              onChanged: (v) => socket.command('update_settings', {'modifiers': s.modifiers.withCount(m, v)}),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text('Расставляются случайно при начале следующего раунда.', style: AppText.muted(12)),
      ),
    ]);
  }
}

class _NumberSetting extends StatelessWidget {
  const _NumberSetting({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  Future<void> _edit(BuildContext context) async {
    final v = await promptText(context, title, initial: '$value', label: '$min…$max', number: true);
    final n = int.tryParse(v ?? '');
    if (n == null) return;
    if (n < min || n > max) {
      if (context.mounted) showToast(context, 'Допустимо от $min до $max', kind: ToastKind.error);
      return;
    }
    onChanged(n);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: AppText.muted(12)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: const Icon(Icons.remove), onPressed: value > min ? () => onChanged(value - 1) : null),
        InkWell(
          onTap: () => _edit(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text('$value', style: AppText.mono(18)),
          ),
        ),
        IconButton(icon: const Icon(Icons.add), onPressed: value < max ? () => onChanged(value + 1) : null),
      ]),
    );
  }
}
