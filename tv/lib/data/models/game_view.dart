import 'block.dart';
import 'json.dart';

enum Phase {
  lobby,
  board,
  catTransfer,
  auction,
  question,
  answering,
  reveal,
  roundEnd,
  finalThemes,
  finalBets,
  finalQuestion,
  finalJudging,
  finalReveal,
  finished;

  static Phase parse(String raw) => switch (raw) {
        'board' => Phase.board,
        'cat_transfer' => Phase.catTransfer,
        'auction' => Phase.auction,
        'question' => Phase.question,
        'answering' => Phase.answering,
        'reveal' => Phase.reveal,
        'round_end' => Phase.roundEnd,
        'final_themes' => Phase.finalThemes,
        'final_bets' => Phase.finalBets,
        'final_question' => Phase.finalQuestion,
        'final_judging' => Phase.finalJudging,
        'final_reveal' => Phase.finalReveal,
        'finished' => Phase.finished,
        _ => Phase.lobby,
      };

  bool get hasQuestion => this == question || this == answering || this == reveal;

  bool get isFinal =>
      this == finalThemes || this == finalBets || this == finalQuestion || this == finalJudging || this == finalReveal;
}

/// Special question kinds (protocol §4.5), revealed when a cell opens.
enum Modifier {
  cat,
  auction,
  noRisk,
  double;

  static Modifier? parse(Object? raw) => switch (raw) {
        'cat' => Modifier.cat,
        'auction' => Modifier.auction,
        'no_risk' => Modifier.noRisk,
        'double' => Modifier.double,
        _ => null,
      };

  String get label => switch (this) {
        Modifier.cat => 'Кот в мешке',
        Modifier.auction => 'Аукцион',
        Modifier.noRisk => 'Вопрос без риска',
        Modifier.double => 'Двойная стоимость',
      };

  String get emoji => switch (this) {
        Modifier.cat => '🐱',
        Modifier.auction => '🔨',
        Modifier.noRisk => '🛡',
        Modifier.double => '×2',
      };
}

/// Phase `auction` (protocol §4.2 `AuctionView`).
class AuctionView {
  const AuctionView({
    required this.turnPlayerId,
    required this.highBid,
    required this.highBidderId,
    required this.allIn,
    required this.passedPlayerIds,
  });

  final String? turnPlayerId;
  final int highBid;
  final String highBidderId;
  final bool allIn;
  final List<String> passedPlayerIds;

  factory AuctionView.fromJson(Json j) => AuctionView(
        turnPlayerId: asStringOrNull(j['turnPlayerId']),
        highBid: asInt(j['highBid']),
        highBidderId: asString(j['highBidderId']),
        allIn: asBool(j['allIn']),
        passedPlayerIds: asList(j['passedPlayerIds'], (e) => asString(e)),
      );
}

class FinalTheme {
  const FinalTheme(this.id, this.name, this.removed);
  final int id;
  final String name;
  final bool removed;

  factory FinalTheme.fromJson(Json j) => FinalTheme(asInt(j['id']), asString(j['name']), asBool(j['removed']));
}

class FinalParticipant {
  const FinalParticipant({
    required this.playerId,
    required this.hasBet,
    required this.bet,
    required this.hasAnswer,
    required this.answer,
    required this.correct,
  });

  final String playerId;
  final bool hasBet;

  /// Hidden (null) for the screen until this finalist is judged.
  final int? bet;
  final bool hasAnswer;
  final String? answer;

  /// Null until the host judged this finalist.
  final bool? correct;

  bool get judged => correct != null;

  factory FinalParticipant.fromJson(Json j) => FinalParticipant(
        playerId: asString(j['playerId']),
        hasBet: asBool(j['hasBet']),
        bet: asIntOrNull(j['bet']),
        hasAnswer: asBool(j['hasAnswer']),
        answer: asStringOrNull(j['answer']),
        correct: j['correct'] is bool ? j['correct'] as bool : null,
      );
}

/// Phases `final_*` (protocol §4.2 `FinalView`, §4.6).
class FinalView {
  const FinalView({
    required this.themes,
    required this.removerId,
    this.answerStartsAt,
    required this.answerEndsAt,
    required this.participants,
  });

  final List<FinalTheme> themes;
  final String? removerId;
  /// final_question: the written-answer window, server ms.
  final int? answerStartsAt;
  final int? answerEndsAt;
  final List<FinalParticipant> participants;

  /// The theme left after removals (the last unremoved one).
  FinalTheme? get remainingTheme {
    final left = themes.where((t) => !t.removed).toList();
    return left.length == 1 ? left.single : null;
  }

  factory FinalView.fromJson(Json j) => FinalView(
        themes: asList(j['themes'], (e) => FinalTheme.fromJson(asJson(e))),
        removerId: asStringOrNull(j['removerId']),
        answerStartsAt: asIntOrNull(j['answerStartsAt']),
        answerEndsAt: asIntOrNull(j['answerEndsAt']),
        participants: asList(j['participants'], (e) => FinalParticipant.fromJson(asJson(e))),
      );
}

class PackRef {
  const PackRef(this.id, this.title);
  final String id;
  final String title;

  factory PackRef.fromJson(Json j) => PackRef(asString(j['id']), asString(j['title']));
}

/// `GameView.game`: identity of the game this view belongs to.
class GameRef {
  const GameRef({
    required this.pin,
    required this.title,
    required this.link,
    required this.hostTaken,
    required this.hostConnected,
    this.hostAvatarUrl,
  });

  /// Null for a screen that watches a game picked from the public list.
  final String? pin;
  final String title;

  /// Share link `<base>/g/<PIN>` (protocol §8); null exactly when [pin] is.
  final String? link;
  final bool hostTaken;
  final bool hostConnected;

  /// Server-relative URL of the host's avatar; null → initials.
  final String? hostAvatarUrl;

  static const empty = GameRef(pin: null, title: '', link: null, hostTaken: false, hostConnected: false);

  factory GameRef.fromJson(Json j) => GameRef(
        pin: asNonEmptyOrNull(j['pin']),
        title: asString(j['title']),
        link: asNonEmptyOrNull(j['link']),
        hostTaken: asBool(j['hostTaken']),
        hostConnected: asBool(j['hostConnected']),
        hostAvatarUrl: asNonEmptyOrNull(j['hostAvatarUrl']),
      );
}

class RoundInfo {
  const RoundInfo(this.index, this.name, this.total, {this.isFinal = false});
  final int index;
  final String name;
  final int total;

  /// `kind: 'final'` (protocol §4.6).
  final bool isFinal;

  factory RoundInfo.fromJson(Json j) => RoundInfo(
        asInt(j['index']),
        asString(j['name']),
        asInt(j['total']),
        isFinal: j['kind'] == 'final',
      );
}

class BoardQuestion {
  const BoardQuestion(this.id, this.value, this.played);
  final int id;
  final int value;
  final bool played;

  factory BoardQuestion.fromJson(Json j) =>
      BoardQuestion(asInt(j['id']), asInt(j['value']), asBool(j['played']));
}

class BoardCategory {
  const BoardCategory(this.id, this.name, this.questions);
  final int id;
  final String name;
  final List<BoardQuestion> questions;

  factory BoardCategory.fromJson(Json j) => BoardCategory(
        asInt(j['id']),
        asString(j['name']),
        asList(j['questions'], (e) => BoardQuestion.fromJson(asJson(e))),
      );
}

class PlayerView {
  const PlayerView(this.id, this.name, this.score, this.connected, {this.avatarUrl});
  final String id;
  final String name;
  final int score;
  final bool connected;

  /// Server-relative avatar URL; null → initials.
  final String? avatarUrl;

  factory PlayerView.fromJson(Json j) => PlayerView(
        asString(j['id']),
        asString(j['name']),
        asInt(j['score']),
        asBool(j['connected'], true),
        avatarUrl: asNonEmptyOrNull(j['avatarUrl']),
      );
}

class QuestionView {
  const QuestionView({
    required this.id,
    required this.categoryName,
    required this.value,
    required this.blocks,
    required this.answerBlocks,
    required this.comment,
    this.modifier,
    int? stake,
  }) : stake = stake ?? value;

  final int id;
  final String categoryName;
  final int value;

  /// Revealed when the cell opens; null for an ordinary question.
  final Modifier? modifier;

  /// What a correct answer earns (×2, the winning bid …; final: 0).
  final int stake;
  final List<Block> blocks;

  /// Present for the screen only in phase `reveal`.
  final List<Block>? answerBlocks;
  final String? comment;

  factory QuestionView.fromJson(Json j) => QuestionView(
        id: asInt(j['id']),
        categoryName: asString(j['categoryName']),
        value: asInt(j['value']),
        modifier: Modifier.parse(j['modifier']),
        stake: asIntOrNull(j['stake']),
        blocks: Block.listFromJson(j['blocks']),
        answerBlocks: j['answerBlocks'] == null ? null : Block.listFromJson(j['answerBlocks']),
        comment: asStringOrNull(j['comment']),
      );
}

class LastResult {
  const LastResult(this.playerId, this.correct, this.delta);
  final String playerId;
  final bool correct;
  final int delta;

  factory LastResult.fromJson(Json j) =>
      LastResult(asString(j['playerId']), asBool(j['correct']), asInt(j['delta']));
}

/// `state` payload as the `screen` role receives it (protocol §4.2). Fields the
/// screen never gets (`typedAnswer`, `settings`, `me`, admin info) are skipped.
class GameView {
  const GameView({
    required this.serverNow,
    required this.game,
    required this.phase,
    required this.pack,
    required this.round,
    required this.board,
    required this.players,
    required this.chooserId,
    required this.question,
    this.soloPlayerId,
    this.auction,
    this.finalView,
    required this.answeringPlayerId,
    required this.attemptedPlayerIds,
    required this.readingStartsAt,
    required this.readingEndsAt,
    required this.buzzStartsAt,
    required this.buzzEndsAt,
    required this.lastResult,
  });

  final int serverNow;
  final GameRef game;
  final Phase phase;
  final PackRef? pack;
  final RoundInfo? round;
  final List<BoardCategory> board;
  final List<PlayerView> players;
  final String? chooserId;
  final QuestionView? question;

  /// cat / auction / no_risk: the only player who answers (no buttons).
  final String? soloPlayerId;
  final AuctionView? auction;

  /// `final` in the protocol (a Dart keyword).
  final FinalView? finalView;
  final String? answeringPlayerId;
  final List<String> attemptedPlayerIds;
  /// Timer windows in server ms (phases question/answering), protocol §4.4.
  final int? readingStartsAt;
  final int? readingEndsAt;
  final int? buzzStartsAt;
  final int? buzzEndsAt;
  final LastResult? lastResult;

  factory GameView.fromJson(Json j) {
    Object? nested(String key) => j[key] is Map ? j[key] : null;
    return GameView(
      serverNow: asInt(j['serverNow']),
      game: nested('game') == null ? GameRef.empty : GameRef.fromJson(asJson(j['game'])),
      phase: Phase.parse(asString(j['phase'])),
      pack: nested('pack') == null ? null : PackRef.fromJson(asJson(j['pack'])),
      round: nested('round') == null ? null : RoundInfo.fromJson(asJson(j['round'])),
      board: asList(j['board'], (e) => BoardCategory.fromJson(asJson(e))),
      players: asList(j['players'], (e) => PlayerView.fromJson(asJson(e))),
      chooserId: asStringOrNull(j['chooserId']),
      question: nested('question') == null ? null : QuestionView.fromJson(asJson(j['question'])),
      soloPlayerId: asStringOrNull(j['soloPlayerId']),
      auction: nested('auction') == null ? null : AuctionView.fromJson(asJson(j['auction'])),
      finalView: nested('final') == null ? null : FinalView.fromJson(asJson(j['final'])),
      answeringPlayerId: asStringOrNull(j['answeringPlayerId']),
      attemptedPlayerIds: asList(j['attemptedPlayerIds'], (e) => asString(e)),
      readingStartsAt: asIntOrNull(j['readingStartsAt']),
      readingEndsAt: asIntOrNull(j['readingEndsAt']),
      buzzStartsAt: asIntOrNull(j['buzzStartsAt']),
      buzzEndsAt: asIntOrNull(j['buzzEndsAt']),
      lastResult: nested('lastResult') == null ? null : LastResult.fromJson(asJson(j['lastResult'])),
    );
  }

  PlayerView? playerById(String? id) {
    if (id == null) return null;
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  PlayerView? get chooser => playerById(chooserId);
  PlayerView? get answering => playerById(answeringPlayerId);

  /// Players by score, highest first; ties keep join order.
  List<PlayerView> get standings {
    final indexed = players.indexed.toList()
      ..sort((a, b) {
        final byScore = b.$2.score.compareTo(a.$2.score);
        return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  /// Number of value rows: the longest category.
  int get boardRows => board.fold(0, (m, c) => c.questions.length > m ? c.questions.length : m);
}
