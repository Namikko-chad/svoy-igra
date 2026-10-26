// Hand-written models for docs/<lang>/05-protocol.md. No code generation.
// Parsers are lenient: missing keys fall back to neutral values so a
// half-built server never crashes the UI.

typedef Json = Map<String, dynamic>;

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
int? _intOrNull(Object? v) => v is num ? v.toInt() : null;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;
String? _strOrNull(Object? v) => v is String ? v : null;
String? _nonEmpty(Object? v) => v is String && v.isNotEmpty ? v : null;
bool _bool(Object? v) => v == true;
Json _map(Object? v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
Json? _mapOrNull(Object? v) => v is Map ? v.cast<String, dynamic>() : null;
List<String> _strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];
List<T> _list<T>(Object? v, T Function(Json) parse) =>
    v is List ? v.whereType<Map<dynamic, dynamic>>().map((e) => parse(e.cast<String, dynamic>())).toList() : <T>[];

// ---------------------------------------------------------------- REST

class ServerInfo {
  const ServerInfo({required this.name, required this.version, required this.serverNow, this.webUrl});

  final String name;
  final String version;
  final int serverNow;

  /// Public address of the web client, if the server has one configured.
  final String? webUrl;

  factory ServerInfo.fromJson(Json j) => ServerInfo(
        name: _str(j['name'], 'Своя игра'),
        version: _str(j['version']),
        serverNow: _int(j['serverNow']),
        webUrl: _strOrNull(j['webUrl']),
      );
}

class PackSummary {
  const PackSummary({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.locked,
    required this.rounds,
    required this.categories,
    required this.questions,
    required this.mediaCount,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String author;
  final String description;
  final bool locked;
  final int rounds;
  final int categories;
  final int questions;
  final int mediaCount;
  final int sizeBytes;
  final int createdAt;
  final int updatedAt;

  factory PackSummary.fromJson(Json j) => PackSummary(
        id: _str(j['id']),
        title: _str(j['title']),
        author: _str(j['author']),
        description: _str(j['description']),
        locked: _bool(j['locked']),
        rounds: _int(j['rounds']),
        categories: _int(j['categories']),
        questions: _int(j['questions']),
        mediaCount: _int(j['mediaCount']),
        sizeBytes: _int(j['sizeBytes']),
        createdAt: _int(j['createdAt']),
        updatedAt: _int(j['updatedAt']),
      );
}

class Media {
  const Media({required this.name, required this.mime, required this.size, required this.url});

  final String name;
  final String mime;
  final int size;
  final String url;

  factory Media.fromJson(Json j) =>
      Media(name: _str(j['name']), mime: _str(j['mime']), size: _int(j['size']), url: _str(j['url']));
}

class Question {
  Question({
    required this.id,
    required this.categoryId,
    required this.position,
    required this.value,
    required this.question,
    required this.answer,
    required this.comment,
    required this.readingSeconds,
  });

  final int id;
  final int categoryId;
  int position;
  final int value;
  final String question;
  final String answer;
  final String comment;
  final int? readingSeconds;

  factory Question.fromJson(Json j) => Question(
        id: _int(j['id']),
        categoryId: _int(j['categoryId']),
        position: _int(j['position']),
        value: _int(j['value']),
        question: _str(j['question']),
        answer: _str(j['answer']),
        comment: _str(j['comment']),
        readingSeconds: _intOrNull(j['readingSeconds']),
      );
}

class Category {
  Category({required this.id, required this.roundId, required this.position, required this.name, required this.questions});

  final int id;
  final int roundId;
  int position;
  String name;
  final List<Question> questions;

  factory Category.fromJson(Json j) => Category(
        id: _int(j['id']),
        roundId: _int(j['roundId']),
        position: _int(j['position']),
        name: _str(j['name']),
        questions: _list(j['questions'], Question.fromJson),
      );
}

class Round {
  Round({required this.id, required this.position, required this.name, this.isFinal = false, required this.categories});

  final int id;
  int position;
  String name;

  /// `kind: 'final'`: every category is a final theme with exactly one question.
  bool isFinal;
  final List<Category> categories;

  factory Round.fromJson(Json j) => Round(
        id: _int(j['id']),
        position: _int(j['position']),
        name: _str(j['name']),
        isFinal: j['kind'] == 'final',
        categories: _list(j['categories'], Category.fromJson),
      );
}

class Pack {
  Pack({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.locked,
    required this.sizeBytes,
    required this.createdAt,
    required this.updatedAt,
    required this.rounds,
    required this.media,
  });

  final String id;
  String title;
  String author;
  String description;
  bool locked;
  int sizeBytes;
  final int createdAt;
  int updatedAt;
  final List<Round> rounds;
  final List<Media> media;

  factory Pack.fromJson(Json j) => Pack(
        id: _str(j['id']),
        title: _str(j['title']),
        author: _str(j['author']),
        description: _str(j['description']),
        locked: _bool(j['locked']),
        sizeBytes: _int(j['sizeBytes']),
        createdAt: _int(j['createdAt']),
        updatedAt: _int(j['updatedAt']),
        rounds: _list(j['rounds'], Round.fromJson),
        media: _list(j['media'], Media.fromJson),
      );
}

// ---------------------------------------------------------------- Games

enum Role {
  player,
  host,
  admin,
  screen;

  static Role parse(Object? v) => Role.values.firstWhere((r) => r.name == v, orElse: () => Role.player);

  String get label => switch (this) {
        player => 'Игрок',
        host => 'Ведущий',
        admin => 'Администратор',
        screen => 'Экран',
      };
}

/// `GameInfo` (protocol §2.3).
class GameInfo {
  const GameInfo({
    required this.id,
    required this.pin,
    required this.title,
    required this.link,
    required this.phase,
    required this.pack,
    required this.players,
    required this.hostTaken,
    required this.createdAt,
  });

  /// Public id (used by `watch`).
  final String id;

  /// Null in `GET /api/games` and for watch screens — never build a link without it.
  final String? pin;
  final String title;
  final String? link;
  final Phase phase;
  final PackRef? pack;
  final int players;
  final bool hostTaken;
  final int createdAt;

  factory GameInfo.fromJson(Json j) => GameInfo(
        id: _str(j['id']),
        pin: _nonEmpty(j['pin']),
        title: _str(j['title']),
        link: _nonEmpty(j['link']),
        phase: Phase.parse(j['phase']),
        pack: j['pack'] is Map ? PackRef.fromJson(_map(j['pack'])) : null,
        players: _int(j['players']),
        hostTaken: _bool(j['hostTaken']),
        createdAt: _int(j['createdAt']),
      );
}

/// `JoinResult` (protocol §2.3); `/api/auth/me` returns it without `token`.
class JoinResult {
  const JoinResult({required this.token, required this.role, required this.game, this.playerId, this.name});

  final String token;
  final Role role;
  final String? playerId;
  final String? name;
  final GameInfo game;

  factory JoinResult.fromJson(Json j) => JoinResult(
        token: _str(j['token']),
        role: Role.parse(j['role']),
        playerId: _strOrNull(j['playerId']),
        name: _strOrNull(j['name']),
        game: GameInfo.fromJson(_map(j['game'])),
      );
}

// ---------------------------------------------------------------- Game

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

  static Phase parse(Object? v) => switch (v) {
        'board' => board,
        'cat_transfer' => catTransfer,
        'auction' => auction,
        'question' => question,
        'answering' => answering,
        'reveal' => reveal,
        'round_end' => roundEnd,
        'final_themes' => finalThemes,
        'final_bets' => finalBets,
        'final_question' => finalQuestion,
        'final_judging' => finalJudging,
        'final_reveal' => finalReveal,
        'finished' => finished,
        _ => lobby,
      };

  String get label => switch (this) {
        lobby => 'Лобби',
        board => 'Табло',
        catTransfer => 'Кот в мешке',
        auction => 'Аукцион',
        question => 'Вопрос',
        answering => 'Ответ',
        reveal => 'Правильный ответ',
        roundEnd => 'Конец раунда',
        finalThemes => 'Финал: темы',
        finalBets => 'Финал: ставки',
        finalQuestion => 'Финал: вопрос',
        finalJudging => 'Финал: проверка',
        finalReveal => 'Финал: итоги',
        finished => 'Игра окончена',
      };

  bool get isFinal => index >= finalThemes.index && index <= finalReveal.index;
}

/// Special question (protocol §4.5).
enum Modifier {
  cat,
  auction,
  noRisk,
  double;

  static Modifier? parse(Object? v) => switch (v) {
        'cat' => cat,
        'auction' => auction,
        'no_risk' => noRisk,
        'double' => double,
        _ => null,
      };

  String get label => switch (this) {
        cat => 'Кот в мешке',
        auction => 'Аукцион',
        noRisk => 'Вопрос без риска',
        double => 'Двойная стоимость',
      };
}

/// `Settings.modifiers`: how many of each per normal round (0..5).
class ModifierCounts {
  const ModifierCounts({this.cat = 1, this.auction = 1, this.noRisk = 1, this.double = 1});

  final int cat;
  final int auction;
  final int noRisk;
  final int double;

  factory ModifierCounts.fromJson(Json j) => ModifierCounts(
        cat: _int(j['cat'], 1),
        auction: _int(j['auction'], 1),
        noRisk: _int(j['noRisk'], 1),
        double: _int(j['double'], 1),
      );

  int of(Modifier m) => switch (m) {
        Modifier.cat => cat,
        Modifier.auction => auction,
        Modifier.noRisk => noRisk,
        Modifier.double => double,
      };

  /// A copy with [m] set to [n] — as the full object `update_settings` expects.
  Json withCount(Modifier m, int n) => {
        'cat': m == Modifier.cat ? n : cat,
        'auction': m == Modifier.auction ? n : auction,
        'noRisk': m == Modifier.noRisk ? n : noRisk,
        'double': m == Modifier.double ? n : double,
      };
}

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
        turnPlayerId: _strOrNull(j['turnPlayerId']),
        highBid: _int(j['highBid']),
        highBidderId: _str(j['highBidderId']),
        allIn: _bool(j['allIn']),
        passedPlayerIds: _strings(j['passedPlayerIds']),
      );
}

class FinalTheme {
  const FinalTheme({required this.id, required this.name, required this.removed});

  final int id;
  final String name;
  final bool removed;

  factory FinalTheme.fromJson(Json j) =>
      FinalTheme(id: _int(j['id']), name: _str(j['name']), removed: _bool(j['removed']));
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
  final int? bet;
  final bool hasAnswer;
  final String? answer;

  /// Null until the host judged this finalist.
  final bool? correct;

  factory FinalParticipant.fromJson(Json j) => FinalParticipant(
        playerId: _str(j['playerId']),
        hasBet: _bool(j['hasBet']),
        bet: _intOrNull(j['bet']),
        hasAnswer: _bool(j['hasAnswer']),
        answer: _strOrNull(j['answer']),
        correct: j['correct'] is bool ? j['correct'] as bool : null,
      );
}

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

  /// final_question: when answering opened (timer bar start).
  final int? answerStartsAt;
  final int? answerEndsAt;
  final List<FinalParticipant> participants;

  factory FinalView.fromJson(Json j) => FinalView(
        themes: _list(j['themes'], FinalTheme.fromJson),
        removerId: _strOrNull(j['removerId']),
        answerStartsAt: _intOrNull(j['answerStartsAt']),
        answerEndsAt: _intOrNull(j['answerEndsAt']),
        participants: _list(j['participants'], FinalParticipant.fromJson),
      );

  /// The theme left after removals (the final's theme).
  FinalTheme? get remainingTheme {
    final left = themes.where((t) => !t.removed).toList();
    return left.length == 1 ? left.single : null;
  }

  FinalParticipant? participant(String? playerId) {
    for (final p in participants) {
      if (p.playerId == playerId) return p;
    }
    return null;
  }
}

enum BlockType { text, image, video, audio }

class Block {
  const Block.text(this.markdown)
      : type = BlockType.text,
        url = '',
        alt = '';

  const Block.media(this.type, this.url, this.alt) : markdown = '';

  final BlockType type;
  final String markdown;
  final String url;
  final String alt;

  factory Block.fromJson(Json j) {
    final type = switch (j['type']) {
      'image' => BlockType.image,
      'video' => BlockType.video,
      'audio' => BlockType.audio,
      _ => BlockType.text,
    };
    if (type == BlockType.text) return Block.text(_str(j['markdown']));
    return Block.media(type, _str(j['url']), _str(j['alt']));
  }

  @override
  bool operator ==(Object other) =>
      other is Block && other.type == type && other.markdown == markdown && other.url == url && other.alt == alt;

  @override
  int get hashCode => Object.hash(type, markdown, url, alt);

  @override
  String toString() => type == BlockType.text ? 'text($markdown)' : '${type.name}($url, $alt)';
}

class BoardQuestion {
  const BoardQuestion({required this.id, required this.value, required this.played});

  final int id;
  final int value;
  final bool played;

  factory BoardQuestion.fromJson(Json j) =>
      BoardQuestion(id: _int(j['id']), value: _int(j['value']), played: _bool(j['played']));
}

class BoardCategory {
  const BoardCategory({required this.id, required this.name, required this.questions});

  final int id;
  final String name;
  final List<BoardQuestion> questions;

  factory BoardCategory.fromJson(Json j) =>
      BoardCategory(id: _int(j['id']), name: _str(j['name']), questions: _list(j['questions'], BoardQuestion.fromJson));
}

class QuestionView {
  const QuestionView({
    required this.id,
    required this.categoryName,
    required this.value,
    this.modifier,
    int? stake,
    required this.blocks,
    required this.answerBlocks,
    required this.comment,
  }) : stake = stake ?? value;

  final int id;
  final String categoryName;
  final int value;

  /// Revealed when the cell opens; never visible on the board.
  final Modifier? modifier;

  /// What a correct answer earns (value, ×2, or the winning bid; final: 0).
  final int stake;
  final List<Block> blocks;
  final List<Block>? answerBlocks;
  final String? comment;

  factory QuestionView.fromJson(Json j) => QuestionView(
        id: _int(j['id']),
        categoryName: _str(j['categoryName']),
        value: _int(j['value']),
        modifier: Modifier.parse(j['modifier']),
        stake: _intOrNull(j['stake']),
        blocks: _list(j['blocks'], Block.fromJson),
        answerBlocks: j['answerBlocks'] is List ? _list(j['answerBlocks'], Block.fromJson) : null,
        comment: _strOrNull(j['comment']),
      );
}

class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    required this.model,
    required this.os,
    required this.appVersion,
    required this.userAgent,
    required this.screen,
    required this.ip,
  });

  final String platform;
  final String model;
  final String os;
  final String appVersion;
  final String userAgent;
  final String screen;
  final String ip;

  factory DeviceInfo.fromJson(Json j) => DeviceInfo(
        platform: _str(j['platform']),
        model: _str(j['model']),
        os: _str(j['os']),
        appVersion: _str(j['appVersion']),
        userAgent: _str(j['userAgent']),
        screen: _str(j['screen']),
        ip: _str(j['ip']),
      );
}

class PlayerStats {
  const PlayerStats({
    required this.correct,
    required this.wrong,
    required this.buzzes,
    required this.avgReactionMs,
    required this.bestReactionMs,
  });

  final int correct;
  final int wrong;
  final int buzzes;
  final int? avgReactionMs;
  final int? bestReactionMs;

  factory PlayerStats.fromJson(Json j) => PlayerStats(
        correct: _int(j['correct']),
        wrong: _int(j['wrong']),
        buzzes: _int(j['buzzes']),
        avgReactionMs: _intOrNull(j['avgReactionMs']),
        bestReactionMs: _intOrNull(j['bestReactionMs']),
      );
}

class AdminPlayerInfo {
  const AdminPlayerInfo({
    required this.device,
    required this.rttMs,
    required this.rttAvgMs,
    required this.jitterMs,
    required this.lastSeenAt,
    required this.buzzOffsetMs,
    required this.effectiveOffsetMs,
    required this.stats,
  });

  final DeviceInfo device;
  final int? rttMs;
  final int? rttAvgMs;
  final int? jitterMs;
  final int? lastSeenAt;
  final int buzzOffsetMs;
  final int effectiveOffsetMs;
  final PlayerStats stats;

  factory AdminPlayerInfo.fromJson(Json j) => AdminPlayerInfo(
        device: DeviceInfo.fromJson(_map(j['device'])),
        rttMs: _intOrNull(j['rttMs']),
        rttAvgMs: _intOrNull(j['rttAvgMs']),
        jitterMs: _intOrNull(j['jitterMs']),
        lastSeenAt: _intOrNull(j['lastSeenAt']),
        buzzOffsetMs: _int(j['buzzOffsetMs']),
        effectiveOffsetMs: _int(j['effectiveOffsetMs']),
        stats: PlayerStats.fromJson(_map(j['stats'])),
      );
}

class PlayerView {
  const PlayerView({
    required this.id,
    required this.name,
    required this.score,
    required this.connected,
    this.avatarUrl,
    this.admin,
  });

  final String id;
  final String name;
  final int score;
  final bool connected;

  /// Relative URL; null → initials.
  final String? avatarUrl;
  final AdminPlayerInfo? admin;

  factory PlayerView.fromJson(Json j) => PlayerView(
        id: _str(j['id']),
        name: _str(j['name']),
        score: _int(j['score']),
        connected: _bool(j['connected']),
        avatarUrl: _nonEmpty(j['avatarUrl']),
        admin: j['admin'] is Map ? AdminPlayerInfo.fromJson(_map(j['admin'])) : null,
      );
}

enum BuzzerState {
  hidden,
  waiting,
  open,
  answering,
  used,
  closed;

  static BuzzerState parse(Object? v) =>
      BuzzerState.values.firstWhere((e) => e.name == v, orElse: () => BuzzerState.hidden);
}

class MeView {
  const MeView({
    required this.id,
    required this.name,
    required this.score,
    required this.canSelect,
    required this.buzzer,
    required this.buzzOpensAt,
    required this.canType,
    this.canGiveCat = false,
    this.canBid = false,
    this.canRemoveTheme = false,
    this.finalist = false,
    this.canBet = false,
    this.canAnswerFinal = false,
  });

  final String id;
  final String name;
  final int score;
  final bool canSelect;
  final BuzzerState buzzer;
  final int? buzzOpensAt;
  final bool canType;
  final bool canGiveCat;
  final bool canBid;
  final bool canRemoveTheme;
  final bool finalist;
  final bool canBet;
  final bool canAnswerFinal;

  factory MeView.fromJson(Json j) => MeView(
        id: _str(j['id']),
        name: _str(j['name']),
        score: _int(j['score']),
        canSelect: _bool(j['canSelect']),
        buzzer: BuzzerState.parse(j['buzzer']),
        buzzOpensAt: _intOrNull(j['buzzOpensAt']),
        canType: _bool(j['canType']),
        canGiveCat: _bool(j['canGiveCat']),
        canBid: _bool(j['canBid']),
        canRemoveTheme: _bool(j['canRemoveTheme']),
        finalist: _bool(j['finalist']),
        canBet: _bool(j['canBet']),
        canAnswerFinal: _bool(j['canAnswerFinal']),
      );
}

class Settings {
  const Settings({
    required this.readingSeconds,
    required this.buzzSeconds,
    required this.wrongPenalty,
    required this.autoLatencyCompensation,
    this.modifiers = const ModifierCounts(),
    this.finalSeconds = 60,
  });

  final int readingSeconds;
  final int buzzSeconds;
  final bool wrongPenalty;
  final bool autoLatencyCompensation;
  final ModifierCounts modifiers;
  final int finalSeconds;

  factory Settings.fromJson(Json j) => Settings(
        readingSeconds: _int(j['readingSeconds'], 10),
        buzzSeconds: _int(j['buzzSeconds'], 15),
        wrongPenalty: _bool(j['wrongPenalty']),
        autoLatencyCompensation: _bool(j['autoLatencyCompensation']),
        modifiers: ModifierCounts.fromJson(_map(j['modifiers'])),
        finalSeconds: _int(j['finalSeconds'], 60),
      );
}

class PackRef {
  const PackRef({required this.id, required this.title});

  final String id;
  final String title;

  factory PackRef.fromJson(Json j) => PackRef(id: _str(j['id']), title: _str(j['title']));
}

class RoundRef {
  const RoundRef({required this.index, required this.name, required this.total, this.isFinal = false});

  final int index;
  final String name;
  final int total;
  final bool isFinal;

  factory RoundRef.fromJson(Json j) => RoundRef(
        index: _int(j['index']),
        name: _str(j['name']),
        total: _int(j['total']),
        isFinal: j['kind'] == 'final',
      );
}

class LastResult {
  const LastResult({required this.playerId, required this.correct, required this.delta});

  final String playerId;
  final bool correct;
  final int delta;

  factory LastResult.fromJson(Json j) =>
      LastResult(playerId: _str(j['playerId']), correct: _bool(j['correct']), delta: _int(j['delta']));
}

/// `GameView.game`.
class GameRef {
  const GameRef({
    required this.pin,
    required this.title,
    required this.link,
    required this.hostTaken,
    required this.hostConnected,
    this.hostAvatarUrl,
  });

  /// Null for a screen that watches from the public list.
  final String? pin;
  final String title;
  final String? link;
  final bool hostTaken;
  final bool hostConnected;
  final String? hostAvatarUrl;

  factory GameRef.fromJson(Json j) => GameRef(
        pin: _nonEmpty(j['pin']),
        title: _str(j['title']),
        link: _nonEmpty(j['link']),
        hostTaken: _bool(j['hostTaken']),
        hostConnected: _bool(j['hostConnected']),
        hostAvatarUrl: _nonEmpty(j['hostAvatarUrl']),
      );
}

class GameView {
  const GameView({
    required this.serverNow,
    required this.role,
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
    required this.typedAnswer,
    required this.lastResult,
    required this.settings,
    required this.admins,
    required this.me,
  });

  final int serverNow;
  final String role;
  final GameRef game;
  final Phase phase;
  final PackRef? pack;
  final RoundRef? round;
  final List<BoardCategory>? board;
  final List<PlayerView> players;
  final String? chooserId;
  final QuestionView? question;

  /// cat / auction / no_risk: the only player who answers; no buttons.
  final String? soloPlayerId;
  final AuctionView? auction;

  /// `final` in the protocol (a Dart keyword).
  final FinalView? finalView;
  final String? answeringPlayerId;
  final List<String> attemptedPlayerIds;
  final int? readingStartsAt;
  final int? readingEndsAt;
  final int? buzzStartsAt;
  final int? buzzEndsAt;
  final String? typedAnswer;
  final LastResult? lastResult;
  final Settings? settings;

  /// Admin only: open admin sockets.
  final int? admins;
  final MeView? me;

  factory GameView.fromJson(Json j) {
    Json? m(String k) => _mapOrNull(j[k]);
    return GameView(
      serverNow: _int(j['serverNow']),
      role: _str(j['role']),
      game: GameRef.fromJson(_map(j['game'])),
      phase: Phase.parse(j['phase']),
      pack: m('pack') == null ? null : PackRef.fromJson(m('pack')!),
      round: m('round') == null ? null : RoundRef.fromJson(m('round')!),
      board: j['board'] is List ? _list(j['board'], BoardCategory.fromJson) : null,
      players: _list(j['players'], PlayerView.fromJson),
      chooserId: _strOrNull(j['chooserId']),
      question: m('question') == null ? null : QuestionView.fromJson(m('question')!),
      soloPlayerId: _strOrNull(j['soloPlayerId']),
      auction: m('auction') == null ? null : AuctionView.fromJson(m('auction')!),
      finalView: m('final') == null ? null : FinalView.fromJson(m('final')!),
      answeringPlayerId: _strOrNull(j['answeringPlayerId']),
      attemptedPlayerIds: j['attemptedPlayerIds'] is List
          ? (j['attemptedPlayerIds'] as List).whereType<String>().toList()
          : const [],
      readingStartsAt: _intOrNull(j['readingStartsAt']),
      readingEndsAt: _intOrNull(j['readingEndsAt']),
      buzzStartsAt: _intOrNull(j['buzzStartsAt']),
      buzzEndsAt: _intOrNull(j['buzzEndsAt']),
      typedAnswer: _strOrNull(j['typedAnswer']),
      lastResult: m('lastResult') == null ? null : LastResult.fromJson(m('lastResult')!),
      settings: m('settings') == null ? null : Settings.fromJson(m('settings')!),
      admins: _intOrNull(j['admins']),
      me: m('me') == null ? null : MeView.fromJson(m('me')!),
    );
  }

  PlayerView? player(String? id) {
    if (id == null) return null;
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  bool get started => phase != Phase.lobby;
}

/// One-shot cue (`event` message). Kept as the raw map plus typed accessors.
class GameEvent {
  const GameEvent(this.kind, this.data);

  final String kind;
  final Json data;

  String? get playerId => _strOrNull(data['playerId']);
  bool get correct => _bool(data['correct']);
  int get delta => _int(data['delta']);
  int? get reactionMs => _intOrNull(data['reactionMs']);
  Modifier? get modifier => Modifier.parse(data['modifier']);
  String? get toId => _strOrNull(data['toId']);
  int get amount => _int(data['amount']);

  factory GameEvent.fromJson(Json j) => GameEvent(_str(j['kind']), j);
}

class ServerError {
  const ServerError(this.code, this.message, [this.reqId]);

  final String code;
  final String message;
  final String? reqId;
}
