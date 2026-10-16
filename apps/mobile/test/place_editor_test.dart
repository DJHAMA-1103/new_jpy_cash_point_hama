import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:point_mobile/geoapify.dart';
import 'package:point_mobile/models.dart';
import 'package:point_mobile/native_bridge.dart';
import 'package:point_mobile/place_editor.dart';

const chosen = LatLng(34.667, 135.496);
Widget testMap(
  BuildContext context,
  LatLng center,
  LatLng? selected,
  ValueChanged<LatLng> onSelect,
) => SizedBox(
  height: 120,
  child: TextButton(
    onPressed: () => onSelect(chosen),
    child: const Text('テスト地図のピンを選択'),
  ),
);

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> openEditor(
  WidgetTester tester, {
  Place? initial,
  String apiKey = 'test-only',
  PlaceSearch? search,
  PlaceMapBuilder? mapBuilder = testMap,
  List<String> apps = const [],
  Set<String> existingIds = const {},
  required ValueChanged<Place?> onReturn,
}) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('開く'),
            onPressed: () async {
              final result = await Navigator.push<Place>(
                context,
                MaterialPageRoute(
                  builder: (_) => PlaceEditor(
                    initial: initial,
                    apps: apps,
                    existingIds: existingIds,
                    native: NativeBridge(supported: false),
                    apiKey: apiKey,
                    search: search,
                    mapBuilder: mapBuilder,
                  ),
                ),
              );
              onReturn(result);
            },
          ),
        ),
      ),
    ),
  );
  await tapText(tester, '開く');
}

GeoapifyPlace hit(String name) => GeoapifyPlace(
  name: name,
  address: '大阪市中央区',
  latitude: 34.66,
  longitude: 135.49,
);

void main() {
  testWidgets('duplicate keyboard submit sends one pending search', (
    tester,
  ) async {
    final pending = Completer<List<GeoapifyPlace>>();
    var requests = 0;
    await openEditor(
      tester,
      onReturn: (_) {},
      search: (query, {latitude, longitude}) {
        requests++;
        return pending.future;
      },
    );
    await tester.enterText(find.byKey(const Key('place-search')), '店');
    final submit = tester
        .widget<TextField>(find.byKey(const Key('place-search')))
        .onSubmitted!;
    submit('店');
    submit('店');
    await tester.pump();
    expect(requests, 1);
    expect(find.text('検索中…'), findsOneWidget);
    pending.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('検索'), findsOneWidget);
  });

  for (final entry in {
    403: '地図のAPIキーまたは利用制限の設定を確認してください。',
    429: '検索の利用上限に達しました。時間をおいてお試しください。',
  }.entries) {
    testWidgets('HTTP ${entry.key} displays sanitized guidance', (
      tester,
    ) async {
      final service = GeoapifySearch(
        apiKey: 'test-only',
        client: MockClient(
          (_) async => http.Response('private response', entry.key),
        ),
      );
      addTearDown(service.close);
      await openEditor(tester, search: service.search, onReturn: (_) {});
      await tester.enterText(find.byKey(const Key('place-search')), '店');
      await tapText(tester, '検索');
      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('private response'), findsNothing);
    });
  }

  testWidgets('unknown search errors hide raw details', (tester) async {
    await openEditor(
      tester,
      onReturn: (_) {},
      search: (query, {latitude, longitude}) async =>
          throw StateError('private URL'),
    );
    await tester.enterText(find.byKey(const Key('place-search')), '店');
    await tapText(tester, '検索');
    expect(find.text('検索できませんでした。「検索」で再試行してください。'), findsOneWidget);
    expect(find.textContaining('private URL'), findsNothing);
  });

  testWidgets(
    'manual pin saves coordinates with default radius and selected apps',
    (tester) async {
      Place? saved;
      await openEditor(tester, onReturn: (value) => saved = value);
      await tapText(tester, 'テスト地図のピンを選択');
      await tester.enterText(find.byKey(const Key('place-name')), '近所の店');
      await tapText(tester, 'この場所で使うアプリを選ぶ');
      expect(saved, isNull);
      await tapText(tester, 'PayPay');
      await tapText(tester, '保存');
      expect(saved?.latitude, chosen.latitude);
      expect(saved?.longitude, chosen.longitude);
      expect(saved?.radius, 150);
      expect(saved?.appIds, ['paypay']);
    },
  );

  testWidgets('existing radius and ID survive moving the pin', (tester) async {
    final initial = Place(
      id: 'existing',
      name: '店',
      latitude: 35,
      longitude: 139,
      radius: 425,
      appIds: ['v_point'],
    );
    Place? saved;
    await openEditor(
      tester,
      initial: initial,
      apps: ['v_point'],
      existingIds: {'existing'},
      onReturn: (value) => saved = value,
    );
    await tapText(tester, 'テスト地図のピンを選択');
    await tapText(tester, 'この場所で使うアプリを選ぶ');
    await tapText(tester, '保存');
    expect(saved?.id, 'existing');
    expect(saved?.radius, 425);
    expect(saved?.latitude, chosen.latitude);
    expect(saved?.appIds, ['v_point']);
  });

  testWidgets('search result selects exact coordinates and name', (
    tester,
  ) async {
    Place? saved;
    await openEditor(
      tester,
      search: (query, {latitude, longitude}) async {
        expect(query, '店名');
        return [hit('検索の店')];
      },
      onReturn: (value) => saved = value,
    );
    await tester.enterText(find.byKey(const Key('place-search')), '店名');
    await tapText(tester, '検索');
    expect(find.text('大阪市中央区'), findsOneWidget);
    await tapText(tester, '検索の店');
    await tapText(tester, 'この場所で使うアプリを選ぶ');
    await tapText(tester, '保存');
    expect(saved?.latitude, 34.66);
    expect(saved?.longitude, 135.49);
    expect(saved?.name, '検索の店');
  });

  testWidgets('new query and manual selection invalidate late responses', (
    tester,
  ) async {
    final first = Completer<List<GeoapifyPlace>>();
    final second = Completer<List<GeoapifyPlace>>();
    Place? saved;
    await openEditor(
      tester,
      search: (query, {latitude, longitude}) =>
          query == '古い' ? first.future : second.future,
      onReturn: (value) => saved = value,
    );
    await tester.enterText(find.byKey(const Key('place-search')), '古い');
    await tapText(tester, '検索');
    await tester.enterText(find.byKey(const Key('place-search')), '新しい');
    await tester.pump();
    await tapText(tester, '検索');
    first.complete([hit('古い結果')]);
    await tester.pumpAndSettle();
    expect(find.text('古い結果'), findsNothing);
    await tapText(tester, 'テスト地図のピンを選択');
    second.complete([hit('遅い結果')]);
    await tester.pumpAndSettle();
    expect(find.text('遅い結果'), findsNothing);
    await tester.enterText(find.byKey(const Key('place-name')), '手動の店');
    await tapText(tester, 'この場所で使うアプリを選ぶ');
    await tapText(tester, '保存');
    expect(saved?.latitude, chosen.latitude);
  });

  testWidgets(
    'cancel while searching returns no place and ignores disposal response',
    (tester) async {
      final pending = Completer<List<GeoapifyPlace>>();
      var returned = false;
      Place? saved;
      await openEditor(
        tester,
        search: (query, {latitude, longitude}) => pending.future,
        onReturn: (value) {
          returned = true;
          saved = value;
        },
      );
      await tester.enterText(find.byKey(const Key('place-search')), '店');
      await tapText(tester, '検索');
      await tapText(tester, 'キャンセル');
      pending.complete([hit('後から来た店')]);
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(saved, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing key makes no map/search calls but keeps existing editing',
    (tester) async {
      var requests = 0;
      Place? saved;
      final initial = Place(
        id: 'saved',
        name: '既存の店',
        latitude: 35,
        longitude: 139,
        radius: 250,
        appIds: [],
      );
      await openEditor(
        tester,
        initial: initial,
        apiKey: '',
        mapBuilder: null,
        search: (query, {latitude, longitude}) async {
          requests++;
          return [];
        },
        onReturn: (value) => saved = value,
      );
      expect(find.byType(FlutterMap), findsNothing);
      expect(find.textContaining('地図・検索は設定されていない'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byKey(const Key('place-search'))).enabled,
        isFalse,
      );
      await tester.enterText(find.byKey(const Key('place-name')), '更新した店');
      await tapText(tester, 'この場所で使うアプリを選ぶ');
      await tapText(tester, '保存');
      expect(requests, 0);
      expect(saved?.name, '更新した店');
      expect(saved?.radius, 250);
      expect(saved?.latitude, 35);
    },
  );

  testWidgets('global app limit blocks fourth app and back preserves draft', (
    tester,
  ) async {
    var returned = false;
    await openEditor(
      tester,
      apps: ['paypay', 'rakuten_pay', 'v_point'],
      onReturn: (_) => returned = true,
    );
    await tapText(tester, 'テスト地図のピンを選択');
    await tester.enterText(find.byKey(const Key('place-name')), '試験店舗');
    await tapText(tester, 'この場所で使うアプリを選ぶ');
    await tapText(tester, 'dポイント');
    await tapText(tester, '保存');
    expect(returned, isFalse);
    expect(find.textContaining('無料版は合計3アプリまで'), findsOneWidget);
    await tester.tap(find.byTooltip('戻る'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('place-name')))
          .controller
          ?.text,
      '試験店舗',
    );
    await tapText(tester, 'この場所で使うアプリを選ぶ');
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .last
          .value,
      isTrue,
    );
  });
}
