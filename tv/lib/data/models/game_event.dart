import 'game_view.dart';
import 'json.dart';

enum GameEventKind {
  questionOpened,
  buzz,
  judged,
  timeout,
  scoreAdjusted,
  roundStarted,
  gameFinished,
  modifier,
  catGiven,
  auctionBid,
  auctionPass,
  auctionWon,
  finalThemeRemoved,
  finalJudged,
  unknown,
}

/// One-shot cue for sounds/animations (protocol §4.2 `event`). Never needed
/// for correctness — the next `state` carries the truth.
class GameEvent {
  const GameEvent(
    this.kind, {
    this.playerId,
    this.correct,
    this.delta,
    this.reactionMs,
    this.modifier,
    this.questionId,
    this.fromId,
    this.toId,
    this.amount,
    this.allIn,
    this.themeId,
  });

  final GameEventKind kind;
  final String? playerId;
  final bool? correct;
  final int? delta;
  final int? reactionMs;
  final Modifier? modifier;
  final int? questionId;
  final String? fromId;
  final String? toId;
  final int? amount;
  final bool? allIn;
  final int? themeId;

  factory GameEvent.fromJson(Json j) {
    final kind = switch (asString(j['kind'])) {
      'question_opened' => GameEventKind.questionOpened,
      'buzz' => GameEventKind.buzz,
      'judged' => GameEventKind.judged,
      'timeout' => GameEventKind.timeout,
      'score_adjusted' => GameEventKind.scoreAdjusted,
      'round_started' => GameEventKind.roundStarted,
      'game_finished' => GameEventKind.gameFinished,
      'modifier' => GameEventKind.modifier,
      'cat_given' => GameEventKind.catGiven,
      'auction_bid' => GameEventKind.auctionBid,
      'auction_pass' => GameEventKind.auctionPass,
      'auction_won' => GameEventKind.auctionWon,
      'final_theme_removed' => GameEventKind.finalThemeRemoved,
      'final_judged' => GameEventKind.finalJudged,
      _ => GameEventKind.unknown,
    };
    return GameEvent(
      kind,
      playerId: asStringOrNull(j['playerId']),
      correct: j['correct'] is bool ? j['correct'] as bool : null,
      delta: asIntOrNull(j['delta']),
      reactionMs: asIntOrNull(j['reactionMs']),
      modifier: Modifier.parse(j['modifier']),
      questionId: asIntOrNull(j['questionId']),
      fromId: asStringOrNull(j['fromId']),
      toId: asStringOrNull(j['toId']),
      amount: asIntOrNull(j['amount']),
      allIn: j['allIn'] is bool ? j['allIn'] as bool : null,
      themeId: asIntOrNull(j['themeId']),
    );
  }
}
