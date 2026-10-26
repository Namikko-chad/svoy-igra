import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../theme/app_theme.dart';

enum TvButtonKind { primary, secondary, danger }

/// D-pad friendly button: a thick `accent` ring + glow + slight scale when
/// focused (manifest §3: every interactive element has a visible focus state).
class TvButton extends StatefulWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subtitle,
    this.kind = TvButtonKind.secondary,
    this.autofocus = false,
    this.focusNode,
    this.expand = false,
  });

  final String label;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onPressed;
  final TvButtonKind kind;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool expand;

  @override
  State<TvButton> createState() => _TvButtonState();
}

class _TvButtonState extends State<TvButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (bg, fg) = switch (widget.kind) {
      TvButtonKind.primary => (AppColors.accent, AppColors.bg),
      TvButtonKind.danger => (AppColors.danger, AppColors.text),
      TvButtonKind.secondary => (_focused ? AppColors.surface2 : AppColors.surface, AppColors.text),
    };
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: fg, size: 36),
          const SizedBox(width: 16),
        ],
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: AppText.bodyStyle(30, weight: FontWeight.w600, color: fg),
                overflow: TextOverflow.ellipsis,
              ),
              if (widget.subtitle != null)
                Text(
                  widget.subtitle!,
                  style: AppText.monoStyle(20, color: fg.withValues(alpha: 0.75)),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );

    return FocusableActionDetector(
      enabled: enabled,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onFocusChange: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? 1.04 : 1,
          duration: AppTheme.fast(context),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: AppTheme.fast(context),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: BoxDecoration(
              color: enabled ? bg : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? AppColors.accent : AppColors.border,
                width: _focused ? 4 : 1,
              ),
              boxShadow: _focused ? AppColors.accentGlow : null,
            ),
            child: Opacity(opacity: enabled ? 1 : 0.5, child: content),
          ),
        ),
      ),
    );
  }
}
