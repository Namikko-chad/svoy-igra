import '../../data/models/game_view.dart';

/// Identity of what the display shows. Equal keys keep the subtree (and its
/// running media) across `state` rebuilds; a new key swaps the stage and
/// stops media owned by the old one. `question` and `answering` share a key
/// so the question's media keeps playing while someone answers.
String stageKeyOf(GameView v) => switch (v.phase) {
  Phase.lobby => 'lobby',
  Phase.board => 'board-${v.round?.index}',
  Phase.catTransfer => 'cat-${v.question?.id}',
  Phase.auction => 'auction-${v.question?.id}',
  Phase.question || Phase.answering => 'q-${v.question?.id}',
  Phase.reveal => 'reveal-${v.question?.id}',
  Phase.roundEnd => 'round_end-${v.round?.index}',
  Phase.finalThemes => 'final_themes',
  Phase.finalBets => 'final_bets',
  Phase.finalQuestion => 'final_question-${v.question?.id}',
  Phase.finalJudging => 'final_judging-${v.question?.id}',
  Phase.finalReveal => 'final_reveal-${v.question?.id}',
  Phase.finished => 'finished',
};
