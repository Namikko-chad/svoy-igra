import 'package:flutter_test/flutter_test.dart';
import 'package:svoy_igra_client/data/deeplink.dart';

void main() {
  GameLink? p(String s) => parseGameLink(Uri.parse(s));

  test('custom scheme', () {
    expect(p('svoyigra://join?server=http%3A%2F%2F192.168.1.10%3A3050&pin=123456'),
        const GameLink(server: 'http://192.168.1.10:3050', pin: '123456'));
    expect(p('svoyigra://join?server=http://192.168.1.10:3050/&pin=123456'),
        const GameLink(server: 'http://192.168.1.10:3050', pin: '123456'));
    expect(p('svoyigra://join?server=https://igra.example.com&pin=654321'),
        const GameLink(server: 'https://igra.example.com', pin: '654321'));
  });

  test('custom scheme rejects bad input', () {
    expect(p('svoyigra://join?server=http://x&pin=12345'), isNull);
    expect(p('svoyigra://join?pin=123456'), isNull);
    expect(p('svoyigra://join?server=ftp://x&pin=123456'), isNull);
    expect(p('svoyigra://other?server=http://x&pin=123456'), isNull);
  });

  test('app links use the link origin', () {
    expect(p('https://igra.example.com/g/123456'), const GameLink(server: 'https://igra.example.com', pin: '123456'));
    expect(p('http://192.168.1.10:3050/g/123456/'), const GameLink(server: 'http://192.168.1.10:3050', pin: '123456'));
    expect(p('https://igra.example.com/g/12ab56'), isNull);
    expect(p('https://igra.example.com/x/123456'), isNull);
    expect(p('https://igra.example.com/g/123456/extra'), isNull);
    expect(p('mailto:a@b.c'), isNull);
  });
}
