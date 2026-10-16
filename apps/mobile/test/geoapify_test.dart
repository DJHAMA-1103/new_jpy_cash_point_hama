import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:point_mobile/geoapify.dart';

Map<String, Object?> place({
  Object? lat = 35.69,
  Object? lon = 139.70,
  String name = '薬局 新宿店',
}) => {'name': name, 'formatted': '東京都新宿区', 'lat': lat, 'lon': lon};

http.Response results(List<Object?> rows) => http.Response(
  jsonEncode({'results': rows}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Matcher errorContaining(String text) => isA<GeoapifySearchException>()
    .having((error) => error.message, 'message', contains(text))
    .having(
      (error) => error.toString(),
      'sanitized',
      isNot(contains('secret-key')),
    );

void main() {
  test(
    'explicit search encodes Japanese text, Japan filter and lon/lat bias',
    () async {
      var calls = 0;
      final service = GeoapifySearch(
        apiKey: 'secret-key',
        client: MockClient((request) async {
          calls++;
          expect(request.url.host, 'api.geoapify.com');
          expect(request.url.path, '/v1/geocode/search');
          expect(request.url.queryParameters, {
            'text': '薬局 & 新宿',
            'lang': 'ja',
            'filter': 'countrycode:jp',
            'limit': '5',
            'format': 'json',
            'apiKey': 'secret-key',
            'bias': 'proximity:139.7,35.69',
          });
          return results([place()]);
        }),
      );
      addTearDown(service.close);
      expect(calls, 0);
      final found = await service.search(
        ' 薬局 & 新宿 ',
        latitude: 35.69,
        longitude: 139.7,
      );
      expect(calls, 1);
      expect(found.single.name, '薬局 新宿店');
      expect(found.single.address, '東京都新宿区');
      expect(found.single.latitude, 35.69);
      expect(found.single.longitude, 139.7);
    },
  );

  test('missing key and blank query do not send requests', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return results([]);
    });
    final missing = GeoapifySearch(apiKey: ' ', client: client);
    final configured = GeoapifySearch(apiKey: 'secret-key', client: client);
    addTearDown(configured.close);
    await expectLater(missing.search('薬局'), throwsA(errorContaining('APIキー')));
    expect(await configured.search('  '), isEmpty);
    expect(calls, 0);
  });

  test('invalid or incomplete bias is rejected without a request', () async {
    var calls = 0;
    final service = GeoapifySearch(
      apiKey: 'secret-key',
      client: MockClient((_) async {
        calls++;
        return results([]);
      }),
    );
    addTearDown(service.close);
    for (final pair in <(double?, double?)>[
      (91, 139),
      (35, 181),
      (double.nan, 139),
      (35, double.infinity),
      (35, null),
      (null, 139),
    ]) {
      await expectLater(
        service.search('薬局', latitude: pair.$1, longitude: pair.$2),
        throwsA(errorContaining('基準位置')),
      );
    }
    expect(calls, 0);
  });

  test('no bias is sent by default and empty results stay empty', () async {
    final service = GeoapifySearch(
      apiKey: 'secret-key',
      client: MockClient((request) async {
        expect(request.url.queryParameters.containsKey('bias'), isFalse);
        return results([]);
      }),
    );
    addTearDown(service.close);
    expect(await service.search('未登録の店'), isEmpty);
  });

  test(
    'deduplicates names at identical coordinates and caps results at five',
    () async {
      final service = GeoapifySearch(
        apiKey: 'secret-key',
        client: MockClient(
          (_) async => results([
            place(),
            place(),
            for (var i = 0; i < 6; i++) place(name: '支店$i'),
          ]),
        ),
      );
      addTearDown(service.close);
      final found = await service.search('薬局');
      expect(found, hasLength(5));
      expect(found.where((p) => p.name == '薬局 新宿店'), hasLength(1));
    },
  );

  test(
    'address searches use provider address text when name is absent',
    () async {
      final row = place()..remove('name');
      final service = GeoapifySearch(
        apiKey: 'secret-key',
        client: MockClient((_) async => results([row])),
      );
      addTearDown(service.close);
      expect((await service.search('東京都新宿区')).single.name, '東京都新宿区');
    },
  );

  for (final status in [401, 403, 429, 500]) {
    test(
      'HTTP $status errors are Japanese and never include response or key',
      () async {
        final service = GeoapifySearch(
          apiKey: 'secret-key',
          client: MockClient(
            (_) async =>
                http.Response('secret-key private server details', status),
          ),
        );
        addTearDown(service.close);
        await expectLater(
          service.search('薬局'),
          throwsA(
            errorContaining(
              status == 429
                  ? '利用上限'
                  : status == 500
                  ? '検索サービス'
                  : 'APIキー',
            ),
          ),
        );
      },
    );
  }

  test('transport exception URL is not exposed', () async {
    final service = GeoapifySearch(
      apiKey: 'secret-key',
      client: MockClient((request) async {
        throw http.ClientException('secret-key', request.url);
      }),
    );
    addTearDown(service.close);
    await expectLater(service.search('薬局'), throwsA(errorContaining('通信環境')));
  });

  testWidgets('a stalled request times out after twelve seconds', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final service = GeoapifySearch(
      apiKey: 'secret-key',
      client: MockClient((_) => pending.future),
    );
    addTearDown(service.close);
    final check = expectLater(
      service.search('薬局'),
      throwsA(errorContaining('タイムアウト')),
    );
    await tester.pump(const Duration(seconds: 12));
    await check;
    pending.complete(results([]));
    await tester.pump();
  });

  test('invalid payloads and out-of-range coordinates fail safely', () async {
    for (final payload in [
      'secret-key',
      '{}',
      '{"results":null}',
      '{"results":[null]}',
      jsonEncode({
        'results': [place(lat: 91)],
      }),
      jsonEncode({
        'results': [place(lon: -181)],
      }),
      jsonEncode({
        'results': [place(lat: '35.69')],
      }),
      jsonEncode({
        'results': [place()..remove('formatted')],
      }),
      '{"results":[{"lat":1e999,"lon":139,"name":"店","formatted":"住所"}]}',
    ]) {
      final service = GeoapifySearch(
        apiKey: 'secret-key',
        client: MockClient((_) async => http.Response.bytes(utf8.encode(payload), 200)),
      );
      await expectLater(
        service.search('薬局'),
        throwsA(errorContaining('読み取れません')),
      );
      service.close();
    }
  });
}
