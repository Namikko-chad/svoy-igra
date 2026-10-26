import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'models.dart';

typedef Progress = void Function(int sent, int total);

/// A REST failure with the protocol's `{error:{code,message}}` body.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.status});

  final String code;
  final String message;
  final int? status;

  /// Russian text for the user.
  String get text => describeError(code, message);

  @override
  String toString() => text;
}

const _errorTexts = {
  'network': 'Нет связи с сервером',
  'invalid_admin_pin': 'Неверный PIN администратора',
  'invalid_title': 'Название игры — не длиннее 60 символов',
  'too_many_games': 'На сервере слишком много игр, попробуйте позже',
  'game_not_found': 'Игра не найдена',
  'invalid_role': 'Неверная роль',
  'host_taken': 'Ведущий уже подключён к этой игре',
  'pack_locked': 'Пакет заблокирован — отредактируйте копию',
  'invalid_image': 'Это не картинка (нужен PNG, JPEG, WebP или GIF)',
  'too_large': 'Файл слишком большой',
  'final_one_question': 'В теме финала может быть только один вопрос',
  'unauthorized': 'Нужно войти заново',
  'forbidden': 'Недостаточно прав',
  'not_found': 'Не найдено',
  'invalid_name': 'Имя должно быть от 1 до 32 символов',
  'name_taken': 'Это имя уже занято',
  'invalid_pack': 'Файл пакета повреждён или не поддерживается',
  'pack_in_use': 'Пакет загружен в одну из игр',
  'too_many_categories': 'В раунде не может быть больше 10 тем',
  'invalid_game_file': 'Неверный файл игры',
  'pack_missing': 'Пакета из файла игры нет в библиотеке',
  'wrong_phase': 'Сейчас это действие недоступно',
  'invalid': 'Неверные данные',
  'internal_error': 'Ошибка сервера',
};

String describeError(String code, String message) => _errorTexts[code] ?? (message.isNotEmpty ? message : code);

/// A downloaded file.
class Download {
  const Download(this.fileName, this.bytes);

  final String fileName;
  final Uint8List bytes;
}

/// Thin wrapper over the REST API (protocol §2). One instance per server
/// and token.
class Api {
  Api(this.baseUrl, {this.token})
      : _dio = Dio(BaseOptions(
          baseUrl: '$baseUrl/api',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 10),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = token;
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }));
  }

  final String baseUrl;
  String? token;
  final Dio _dio;

  /// Absolute URL for a server-relative one (`/api/packs/...`).
  String absolute(String url) => url.startsWith('/') ? '$baseUrl$url' : url;

  Future<T> _call<T>(Future<Response<dynamic>> Function() run, T Function(dynamic data) parse) async {
    try {
      final res = await run();
      return parse(res.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  static ApiException _toApiException(DioException e) {
    final res = e.response;
    if (res == null) return const ApiException('network', '');
    var data = res.data;
    if (data is List<int>) {
      try {
        data = jsonDecode(utf8.decode(data));
      } catch (_) {}
    } else if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiException('${err['code'] ?? 'error'}', '${err['message'] ?? ''}', status: res.statusCode);
    }
    return ApiException('http_${res.statusCode}', 'HTTP ${res.statusCode}', status: res.statusCode);
  }

  static Json _json(dynamic d) => d is Map ? d.cast<String, dynamic>() : <String, dynamic>{};

  // ------------------------------------------------------------ public

  Future<ServerInfo> info() => _call(() => _dio.get('/info'), (d) => ServerInfo.fromJson(_json(d)));

  /// Every live game, newest first.
  Future<List<GameInfo>> listGames() => _call(
        () => _dio.get('/games'),
        (d) => d is List ? d.map((e) => GameInfo.fromJson(_json(e))).toList() : <GameInfo>[],
      );

  /// Creates a game; the creator becomes its admin.
  Future<JoinResult> createGame(String adminPin, {String? title}) => _call(
        () => _dio.post('/games', data: {'adminPin': adminPin, 'title': ?title}),
        (d) => JoinResult.fromJson(_json(d)),
      );

  Future<GameInfo> gameInfo(String pin) =>
      _call(() => _dio.get('/games/${Uri.encodeComponent(pin)}'), (d) => GameInfo.fromJson(_json(d)));

  Future<JoinResult> joinGame(String pin, Role role, {String? name, String? adminPin}) => _call(
        () => _dio.post('/games/${Uri.encodeComponent(pin)}/join', data: {
          'role': role.name,
          'name': ?name,
          'adminPin': ?adminPin,
        }),
        (d) => JoinResult.fromJson(_json(d)),
      );

  /// Watch a game from the public list as a screen (no PIN, no link).
  Future<JoinResult> watchGame(String gameId) => _call(
        () => _dio.post('/games/${Uri.encodeComponent(gameId)}/watch'),
        (d) => JoinResult.fromJson(_json(d)),
      );

  /// What the current token is (JoinResult without `token`).
  Future<JoinResult> me() => _call(() => _dio.get('/auth/me'), (d) => JoinResult.fromJson(_json(d)));

  // ------------------------------------------------------------ avatars

  /// Uploads my avatar (player or host token); returns its relative URL.
  Future<String> uploadAvatar(Uint8List jpeg) => _call(
        () => _dio.post('/avatar', data: FormData.fromMap({'file': MultipartFile.fromBytes(jpeg, filename: 'avatar.jpg')})),
        (d) => _json(d)['avatarUrl'] as String,
      );

  Future<void> deleteAvatar() => _call(() => _dio.delete('/avatar'), (_) {});

  // ------------------------------------------------------------ packs

  Future<List<PackSummary>> listPacks() => _call(
        () => _dio.get('/packs'),
        (d) => (d as List).map((e) => PackSummary.fromJson(_json(e))).toList(),
      );

  Future<Pack> createPack(String title) =>
      _call(() => _dio.post('/packs', data: {'title': title}), (d) => Pack.fromJson(_json(d)));

  Future<Pack> getPack(String id) => _call(() => _dio.get('/packs/${Uri.encodeComponent(id)}'), (d) => Pack.fromJson(_json(d)));

  Future<PackSummary> updatePack(String id, {String? title, String? author, String? description}) => _call(
        () => _dio.patch('/packs/${Uri.encodeComponent(id)}', data: {
          'title': ?title,
          'author': ?author,
          'description': ?description,
        }),
        (d) => PackSummary.fromJson(_json(d)),
      );

  /// An unlocked copy (with media); works on locked packs.
  Future<Pack> copyPack(String id, String title) => _call(
        () => _dio.post('/packs/${Uri.encodeComponent(id)}/copy', data: {'title': title}),
        (d) => Pack.fromJson(_json(d)),
      );

  /// Irreversible through the API.
  Future<PackSummary> lockPack(String id) =>
      _call(() => _dio.post('/packs/${Uri.encodeComponent(id)}/lock'), (d) => PackSummary.fromJson(_json(d)));

  Future<void> deletePack(String id) => _call(() => _dio.delete('/packs/${Uri.encodeComponent(id)}'), (_) {});

  Future<PackSummary> importPack(MultipartFile file, {Progress? onProgress}) => _call(
        () => _dio.post('/packs/import', data: FormData.fromMap({'file': file}), onSendProgress: onProgress),
        (d) => PackSummary.fromJson(_json(d)),
      );

  Future<Download> exportPack(String id, {Progress? onProgress}) async {
    try {
      final res = await _dio.get<List<int>>(
        '/packs/${Uri.encodeComponent(id)}/export',
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      final name = _fileName(res.headers.value('content-disposition')) ?? 'pack.dub';
      return Download(name, Uint8List.fromList(res.data ?? const []));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  String _p(String packId) => '/packs/${Uri.encodeComponent(packId)}';

  Future<Round> createRound(String packId, String name, {bool isFinal = false}) => _call(
        () => _dio.post('${_p(packId)}/rounds', data: {'name': name, 'kind': isFinal ? 'final' : 'normal'}),
        (d) => Round.fromJson(_json(d)),
      );

  Future<Round> updateRound(String packId, int roundId, {String? name, int? position, bool? isFinal}) => _call(
        () => _dio.patch('${_p(packId)}/rounds/$roundId', data: {
          'name': ?name,
          'position': ?position,
          'kind': ?(isFinal == null ? null : (isFinal ? 'final' : 'normal')),
        }),
        (d) => Round.fromJson(_json(d)),
      );

  Future<void> deleteRound(String packId, int roundId) => _call(() => _dio.delete('${_p(packId)}/rounds/$roundId'), (_) {});

  Future<Category> createCategory(String packId, int roundId, String name) => _call(
        () => _dio.post('${_p(packId)}/rounds/$roundId/categories', data: {'name': name}),
        (d) => Category.fromJson(_json(d)),
      );

  Future<Category> updateCategory(String packId, int categoryId, {String? name, int? position}) => _call(
        () => _dio.patch('${_p(packId)}/categories/$categoryId', data: {'name': ?name, 'position': ?position}),
        (d) => Category.fromJson(_json(d)),
      );

  Future<void> deleteCategory(String packId, int categoryId) =>
      _call(() => _dio.delete('${_p(packId)}/categories/$categoryId'), (_) {});

  /// [input] is a `QuestionInput` map (protocol §2.3).
  Future<Question> createQuestion(String packId, int categoryId, Json input) => _call(
        () => _dio.post('${_p(packId)}/categories/$categoryId/questions', data: input),
        (d) => Question.fromJson(_json(d)),
      );

  Future<Question> updateQuestion(String packId, int questionId, Json patch) => _call(
        () => _dio.patch('${_p(packId)}/questions/$questionId', data: patch),
        (d) => Question.fromJson(_json(d)),
      );

  Future<void> deleteQuestion(String packId, int questionId) =>
      _call(() => _dio.delete('${_p(packId)}/questions/$questionId'), (_) {});

  Future<Media> uploadMedia(String packId, MultipartFile file, {String? name, Progress? onProgress}) => _call(
        () => _dio.post(
          '${_p(packId)}/media',
          data: FormData.fromMap({'name': ?name, 'file': file}),
          onSendProgress: onProgress,
        ),
        (d) => Media.fromJson(_json(d)),
      );

  Future<void> deleteMedia(String packId, String name) =>
      _call(() => _dio.delete('${_p(packId)}/media/${Uri.encodeComponent(name)}'), (_) {});

  // ------------------------------------------------------------ game file

  Future<Download> exportGame() async {
    try {
      final res = await _dio.get<List<int>>('/game/export', options: Options(responseType: ResponseType.bytes));
      final name = _fileName(res.headers.value('content-disposition')) ?? 'game.json';
      return Download(name, Uint8List.fromList(res.data ?? const []));
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  Future<void> importGame(Uint8List bytes) => _call(
        () => _dio.post(
          '/game/import',
          data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: 'game.json')}),
        ),
        (_) {},
      );

  static String? _fileName(String? disposition) {
    if (disposition == null) return null;
    final star = RegExp(r"filename\*=(?:UTF-8'')?([^;]+)", caseSensitive: false).firstMatch(disposition);
    if (star != null) return Uri.decodeComponent(star.group(1)!.trim().replaceAll('"', ''));
    final plain = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(disposition);
    return plain?.group(1);
  }
}
