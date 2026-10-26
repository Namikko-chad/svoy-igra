import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeSink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  @override
  void add(dynamic data) => sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
  @override
  Future<void> get done => Future.value();
}

class FakeChannel with StreamChannelMixin<dynamic> implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  @override
  final FakeSink sink = FakeSink();
  @override
  Stream<dynamic> get stream => incoming.stream;

  /// The server closes the socket with [code].
  Future<void> serverClose(int code) async {
    closeCode = code;
    await incoming.close();
  }
  @override
  Future<void> get ready => Future.value();
  @override
  String? get protocol => null;
  /// Set before closing [incoming] to simulate a server close code.
  @override
  int? closeCode;
  @override
  String? get closeReason => null;
}

