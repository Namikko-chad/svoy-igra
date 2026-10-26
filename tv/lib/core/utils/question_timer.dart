/// Which window the question timer bar is counting down.
enum TimerStage { reading, buzzing }

/// One countdown window in server time (Unix ms).
class Countdown {
  const Countdown(this.stage, this.startsAt, this.endsAt);

  final TimerStage stage;
  final int startsAt;
  final int endsAt;

  int get totalMs => endsAt - startsAt;

  int remainingMs(int now) {
    final left = endsAt - now;
    if (left < 0) return 0;
    return left > totalMs ? totalMs : left;
  }

  /// 1.0 = full bar, 0.0 = drained.
  double fraction(int now) => totalMs <= 0 ? 0 : remainingMs(now) / totalMs;

  /// Whole seconds shown next to the bar (rounded up, so "1" until the end).
  int secondsLeft(int now) => (remainingMs(now) + 999) ~/ 1000;

  /// Manifest: the timer turns `warning` in the last 3 s.
  bool isWarning(int now) {
    final left = remainingMs(now);
    return left > 0 && left <= 3000;
  }

  @override
  bool operator ==(Object other) =>
      other is Countdown &&
      other.stage == stage &&
      other.startsAt == startsAt &&
      other.endsAt == endsAt;

  @override
  int get hashCode => Object.hash(stage, startsAt, endsAt);

  @override
  String toString() => 'Countdown($stage, $startsAt..$endsAt)';
}

/// The window running at server time [now] (protocol §4.4 timer bars):
/// reading = `readingStartsAt → readingEndsAt`, then the buzz window =
/// `buzzStartsAt → buzzEndsAt` (after a wrong answer `buzzStartsAt` is the
/// reopen moment). Null when the view carries no usable window.
Countdown? questionCountdown({
  required int? readingStartsAt,
  required int? readingEndsAt,
  required int? buzzStartsAt,
  required int? buzzEndsAt,
  required int now,
}) {
  if (readingStartsAt != null && readingEndsAt != null && now < readingEndsAt) {
    return Countdown(TimerStage.reading, readingStartsAt, readingEndsAt);
  }
  if (buzzStartsAt != null && buzzEndsAt != null) {
    return Countdown(TimerStage.buzzing, buzzStartsAt > buzzEndsAt ? buzzEndsAt : buzzStartsAt, buzzEndsAt);
  }
  return null;
}
