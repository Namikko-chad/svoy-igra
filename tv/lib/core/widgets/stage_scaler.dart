import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/app_colors.dart';

/// Lays the whole app out on a fixed 1920×1080 canvas and scales it to the
/// real screen (letterboxed if the aspect differs). TVs report very different
/// logical sizes (960×540 at 2× density, 1920×1080 at 1×); designing once in
/// TV pixels keeps the manifest sizes (board values 72 px …) literal.
class StageScaler extends StatelessWidget {
  const StageScaler({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    const stage = Size(AppConfig.stageWidth, AppConfig.stageHeight);
    final scale = (mq.size.width / stage.width) < (mq.size.height / stage.height)
        ? mq.size.width / stage.width
        : mq.size.height / stage.height;
    if (!scale.isFinite || scale <= 0) return const ColoredBox(color: AppColors.bg);

    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: SizedBox(
          width: stage.width * scale,
          height: stage.height * scale,
          child: FittedBox(
            child: SizedBox.fromSize(
              size: stage,
              child: MediaQuery(
                data: mq.copyWith(
                  size: stage,
                  devicePixelRatio: mq.devicePixelRatio * scale,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                  viewInsets: EdgeInsets.zero,
                  textScaler: TextScaler.noScaling,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
