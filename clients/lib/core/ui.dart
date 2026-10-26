import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

enum ToastKind { info, success, error, warning }

/// Bottom-centre toast, auto-hides after 3 s, coloured by kind.
void showToast(BuildContext context, String text, {ToastKind kind = ToastKind.info}) {
  final color = switch (kind) {
    ToastKind.info => AppColors.accent,
    ToastKind.success => AppColors.success,
    ToastKind.error => AppColors.danger,
    ToastKind.warning => AppColors.warning,
  };
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      duration: const Duration(seconds: 3),
      content: Row(children: [
        Container(width: 4, height: 20, color: color),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
    ));
}

Future<bool> confirm(BuildContext context, String title, {String? message, String ok = 'Да', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.text) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Single-field text prompt. Returns null on cancel.
Future<String?> promptText(
  BuildContext context,
  String title, {
  String initial = '',
  String? label,
  String ok = 'Сохранить',
  bool number = false,
  bool signed = false,
  int? maxLength,
  int maxLines = 1,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: 1,
        keyboardType: number ? TextInputType.numberWithOptions(signed: signed) : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(signed ? r'[-0-9]' : r'[0-9]'))] : null,
        decoration: InputDecoration(labelText: label),
        onSubmitted: maxLines == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(ok)),
      ],
    ),
  );
}

/// Modal progress for uploads/downloads. Update through the returned notifier;
/// close with `Navigator.pop`.
ValueNotifier<double?> showProgressDialog(BuildContext context, String title) {
  final progress = ValueNotifier<double?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: ValueListenableBuilder<double?>(
          valueListenable: progress,
          builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: v),
            const SizedBox(height: 12),
            Text(v == null ? '…' : '${(v * 100).round()} %', style: AppText.mono(14)),
          ]),
        ),
      ),
    ),
  );
  return progress;
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(), style: AppText.body(12, weight: FontWeight.w600, color: AppColors.textMuted)),
        ),
        ?trailing,
      ]),
    );
  }
}

/// A connection dot (success / danger).
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.ok, this.size = 8});

  final bool ok;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? AppColors.success : AppColors.danger),
      );
}

/// Centered message with an optional icon and action.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.subtitle, this.icon, this.action});

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Icon(icon, size: 48, color: AppColors.textMuted),
          if (icon != null) const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: AppText.display(18, weight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, textAlign: TextAlign.center, style: AppText.muted(14)),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}
