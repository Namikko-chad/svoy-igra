import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_tv/core/theme/app_theme.dart';
import 'package:svoy_igra_tv/core/widgets/stage_scaler.dart';
import 'package:svoy_igra_tv/data/ws/game_socket.dart';
import 'package:svoy_igra_tv/features/display/display_screen.dart';

import 'models_test.dart' show sampleState;
import 'support/fake_channel.dart';

Map<String, dynamic> _state(Map<String, dynamic> patch) {
  final base = (jsonDecode(sampleState) as Map<String, dynamic>)['data'] as Map<String, dynamic>;
  return {...base, ...patch};
}

void main() {
  // Text-only question so no media plugin is needed in the test host.
  final textQuestion = {
    'id': 12,
    'categoryName': 'Кино',
    'value': 200,
    'blocks': [
      {'type': 'text', 'markdown': 'Какой фильм вышел в **1927** году? <b>не HTML</b>'},
    ],
    'answerBlocks': null,
    'comment': null,
  };

  final manyPlayers = [
    for (var i = 1; i <= 8; i++)
      {'id': 'p$i', 'name': 'Игрок с длинным именем $i', 'score': i * 700 - 1500, 'connected': i != 4},
  ];
  List<Map<String, dynamic>> finalists({required bool judged, bool partial = false}) => [
        for (var i = 3; i <= 8; i++)
          {
            'playerId': 'p$i',
            'hasBet': i.isEven,
            'bet': judged && !(partial && i > 5) ? i * 100 : null,
            'hasAnswer': i != 7,
            'answer': judged && !(partial && i > 5) ? 'Очень длинный ответ финалиста номер $i на вопрос' : null,
            'correct': judged && !(partial && i > 5) ? i.isOdd : null,
          },
      ];

  final cases = <String, Map<String, dynamic>>{
    'lobby': {'phase': 'lobby', 'question': null},
    'lobby_watch': {
      'phase': 'lobby',
      'question': null,
      'game': {'pin': null, 'title': 'Пятница', 'link': null, 'hostTaken': true, 'hostConnected': true},
    },
    'board': {
      'phase': 'board',
      'question': null,
      'board': [
        for (var c = 0; c < 10; c++)
          {
            'id': c,
            'name': 'Очень длинное название категории номер $c',
            'questions': [
              for (var q = 0; q < 6; q++) {'id': c * 10 + q, 'value': (q + 1) * 1000, 'played': q == 2},
            ],
          },
      ],
    },
    'question': {
      'phase': 'question',
      'question': textQuestion,
      'readingStartsAt': 1761400000000,
      'readingEndsAt': 1761400000000 + 10000,
      'buzzStartsAt': 1761400000000 + 10000,
      'buzzEndsAt': 1761400000000 + 25000,
    },
    'answering': {'phase': 'answering', 'question': textQuestion, 'answeringPlayerId': 'p_c'},
    'reveal': {
      'phase': 'reveal',
      'question': {
        ...textQuestion,
        'answerBlocks': [
          {'type': 'text', 'markdown': '«Метрополис»'},
        ],
        'comment': 'Фриц Ланг',
      },
    },
    'round_end': {'phase': 'round_end', 'question': null},
    // --- special questions (§4.5) ---
    'cat_transfer': {
      'phase': 'cat_transfer',
      'question': {...textQuestion, 'modifier': 'cat', 'stake': 200, 'blocks': []},
      'chooserId': 'p_a',
    },
    'auction': {
      'phase': 'auction',
      'question': {...textQuestion, 'modifier': 'auction', 'stake': 200, 'blocks': []},
      'players': manyPlayers,
      'auction': {
        'turnPlayerId': 'p3',
        'highBid': 1200,
        'highBidderId': 'p1',
        'allIn': true,
        'passedPlayerIds': ['p2', 'p5'],
      },
    },
    'solo_question': {
      'phase': 'question',
      'question': {...textQuestion, 'modifier': 'no_risk', 'stake': 400},
      'soloPlayerId': 'p_a',
      'readingStartsAt': 1761400000000,
      'readingEndsAt': 1761400000000 + 10000,
    },
    'double_question': {
      'phase': 'question',
      'question': {...textQuestion, 'modifier': 'double', 'stake': 400},
      'readingStartsAt': 1761400000000,
      'readingEndsAt': 1761400000000 + 10000,
      'buzzStartsAt': 1761400000000 + 10000,
      'buzzEndsAt': 1761400000000 + 25000,
    },
    'solo_wrong_reveal': {
      'phase': 'reveal',
      'question': {
        ...textQuestion,
        'modifier': 'cat',
        'answerBlocks': [
          {'type': 'text', 'markdown': 'Ответ'},
        ],
      },
      'soloPlayerId': 'p_b',
      'lastResult': {'playerId': 'p_b', 'correct': false, 'delta': -200},
    },
    // --- final (§4.6) ---
    'final_themes': {
      'phase': 'final_themes',
      'question': null,
      'round': {'index': 2, 'name': 'Суперфинал', 'total': 3, 'kind': 'final'},
      'players': manyPlayers,
      'final': {
        'themes': [
          for (var i = 0; i < 10; i++) {'id': i, 'name': 'Тема финала с длинным названием $i', 'removed': i.isEven},
        ],
        'removerId': 'p2',
        'answerEndsAt': null,
        'participants': finalists(judged: false),
      },
    },
    'final_bets': {
      'phase': 'final_bets',
      'question': null,
      'round': {'index': 2, 'name': '', 'total': 3, 'kind': 'final'},
      'players': manyPlayers,
      'final': {
        'themes': [
          {'id': 1, 'name': 'Литература', 'removed': true},
          {'id': 2, 'name': 'Живопись', 'removed': false},
        ],
        'removerId': null,
        'answerEndsAt': null,
        'participants': finalists(judged: false),
      },
    },
    'final_question': {
      'phase': 'final_question',
      'question': {...textQuestion, 'value': 0, 'stake': 0, 'categoryName': 'Живопись'},
      'round': {'index': 2, 'name': '', 'total': 3, 'kind': 'final'},
      'players': manyPlayers,
      'final': {
        'themes': [
          {'id': 2, 'name': 'Живопись', 'removed': false},
        ],
        'removerId': null,
        'answerEndsAt': 1761400000000 + 60000,
        'participants': finalists(judged: false),
      },
    },
    'final_judging': {
      'phase': 'final_judging',
      'question': {...textQuestion, 'value': 0, 'stake': 0, 'categoryName': 'Живопись'},
      'round': {'index': 2, 'name': '', 'total': 3, 'kind': 'final'},
      'players': manyPlayers,
      'final': {
        'themes': [
          {'id': 2, 'name': 'Живопись', 'removed': false},
        ],
        'removerId': null,
        'answerEndsAt': null,
        'participants': finalists(judged: true, partial: true),
      },
    },
    'final_reveal': {
      'phase': 'final_reveal',
      'question': {
        ...textQuestion,
        'value': 0,
        'stake': 0,
        'categoryName': 'Живопись',
        'answerBlocks': [
          {'type': 'text', 'markdown': '«Чёрный квадрат»'},
        ],
        'comment': 'Казимир Малевич, 1915',
      },
      'round': {'index': 2, 'name': '', 'total': 3, 'kind': 'final'},
      'players': manyPlayers,
      'final': {
        'themes': [
          {'id': 2, 'name': 'Живопись', 'removed': false},
        ],
        'removerId': null,
        'answerEndsAt': null,
        'participants': finalists(judged: true),
      },
    },
    'finished': {'phase': 'finished', 'question': null},
  };

  for (final MapEntry(key: name, value: patch) in cases.entries) {
    testWidgets('renders $name on a 1080p TV without overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2; // a typical TV: 960×540 logical
      addTearDown(tester.view.reset);

      final channel = FakeChannel();
      final socket = GameSocket(
        base: Uri.parse('http://10.0.0.2:3050'),
        token: 'scr_token',
        hello: () async => {},
        connector: (_) => channel,
      )..start();
      socket.handleFrame(jsonEncode({'type': 'welcome', 'data': {'role': 'screen', 'serverNow': 1761400000000}}));
      socket.handleFrame(jsonEncode({'type': 'state', 'data': _state(patch)}));

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) => StageScaler(child: child!),
        home: DisplayScreen(socket: socket, onChangeGame: () {}, onChangeServer: () {}),
      ));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.byType(DisplayScreen), findsOneWidget);
      if (name == 'lobby') {
        expect(find.text('http://quiz.lan/g/123456'), findsOneWidget);
        expect(find.text('123 456'), findsOneWidget);
      }
      final expected = <String, List<String>>{
        'cat_transfer': ['Аня', ' выбирает, кому отдать кота'],
        'auction': ['ВА-БАНК', '1200'],
        'solo_question': ['Вопрос без риска', '400'],
        'double_question': ['Двойная стоимость'],
        'final_themes': ['ФИНАЛ', 'Игрок с длинным именем 2'],
        'final_bets': ['Живопись', '✓ ставка сделана'],
        'final_question': ['60'],
        'final_reveal': ['ПРАВИЛЬНЫЙ ОТВЕТ'],
      }[name];
      for (final text in expected ?? const <String>[]) {
        expect(find.textContaining(text, findRichText: true), findsWidgets, reason: '$name: $text');
      }
      if (name == 'lobby_watch') {
        expect(find.text('Ссылку для входа раздаёт администратор'), findsOneWidget);
        expect(find.textContaining('/g/'), findsNothing);
      }

      await tester.pumpWidget(const SizedBox());
      socket.dispose();
    });
  }
}
