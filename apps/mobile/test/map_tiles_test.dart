import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:point_mobile/place_editor.dart';
import 'package:point_mobile/geoapify.dart';

class StaleCache implements MapCachingProvider {
  @override
  bool get isSupported => true;
  bool refreshed = false;
  @override
  Future<CachedMapTile?> getTile(String url) async => (
    bytes: TileProvider.transparentImage,
    metadata: CachedMapTileMetadata(
      staleAt: DateTime.utc(2000),
      lastModified: null,
      etag: 'cached',
    ),
  );
  @override
  Future<void> putTile({
    required String url,
    required CachedMapTileMetadata metadata,
    Uint8List? bytes,
  }) async {
    refreshed = true;
  }
}

Future<void> resolveTile(SafeTileProvider provider) async {
  final image = provider.getImageWithCancelLoadingSupport(
    const TileCoordinates(1, 1, 2),
    TileLayer(urlTemplate: 'https://example.invalid/{z}/{x}/{y}?apiKey=SECRET'),
    Completer<void>().future,
  );
  final done = Completer<void>();
  late ui.Image received;
  final stream = image.resolve(ImageConfiguration.empty);
  late ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      received = image.image;
      image.dispose();
      stream.removeListener(listener);
      done.complete();
    },
    onError: (Object error, StackTrace? stack) {
      stream.removeListener(listener);
      done.completeError(error);
    },
  );
  stream.addListener(listener);
  await done.future;
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  // Flutter releases cache keep-alive handles after the next frame.
  final binding = TestWidgetsFlutterBinding.instance;
  binding.handleBeginFrame(null);
  binding.handleDrawFrame();
  expect(received.debugGetOpenHandleStackTraces(), isEmpty);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('tap follows camera after selecting a search result', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    const initial = LatLng(35.6812, 139.7671);
    const result = LatLng(35.6917065, 139.7033723);
    LatLng? selected;
    final client = MockClient(
      (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
    );
    await http.runWithClient(() async {
      Widget map(LatLng center) => MaterialApp(
        home: Scaffold(
          body: PlaceMap(
            apiKey: 'test-key',
            center: center,
            pins: [center],
            cachingProvider: const DisabledMapCachingProvider(),
            onSelect: (point) => selected = point,
          ),
        ),
      );
      await tester.pumpWidget(map(initial));
      await tester.pumpAndSettle();
      await tester.pumpWidget(map(result));
      await tester.pumpAndSettle();
      final finder = find.byType(FlutterMap);
      final camera = MapCamera.of(tester.element(find.byType(MarkerLayer)));
      expect(camera.center.latitude, closeTo(result.latitude, 0.000001));
      expect(camera.center.longitude, closeTo(result.longitude, 0.000001));
      final local =
          tester.getSize(finder).center(Offset.zero) + const Offset(30, 0);
      final expected = camera.screenOffsetToLatLng(local);
      await tester.tapAt(tester.getTopLeft(finder) + local);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(selected!.latitude, closeTo(expected.latitude, 0.000001));
      expect(selected!.longitude, closeTo(expected.longitude, 0.000001));
      expect(
        find.ancestor(of: finder, matching: find.byType(ExcludeSemantics)),
        findsOneWidget,
      );
      final centerButton = tester.getSemantics(find.text('地図の中央を登録位置にする'));
      tester
          .element(finder)
          .findRenderObject()!
          .owner!
          .semanticsOwner!
          .performAction(centerButton.id, ui.SemanticsAction.tap);
      await tester.pump();
      expect(selected, camera.center);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    }, () => client);
  });
  test('normal tile releases every image handle', () async {
    final client = MockClient(
      (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
    );
    addTearDown(client.close);
    await resolveTile(
      SafeTileProvider(
        client: client,
        onFailure: () => fail('Unexpected tile failure'),
        cachingProvider: const DisabledMapCachingProvider(),
      ),
    );
  });
  testWidgets('search and map trim the same key', (tester) async {
    var searches = 0;
    var tiles = 0;
    final tileKeys = <String?>[];
    final client = MockClient((request) async {
      if (request.url.path == '/v1/geocode/search') {
        searches++;
        expect(request.url.queryParameters['apiKey'], 'test-key');
        return http.Response('{"results":[]}', 200);
      }
      tiles++;
      tileKeys.add(request.url.queryParameters['apiKey']);
      return http.Response.bytes(TileProvider.transparentImage, 200);
    });
    final search = GeoapifySearch(apiKey: ' test-key ', client: client);
    addTearDown(search.close);
    await http.runWithClient(() async {
      await search.search('Tokyo');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlaceMap(
              apiKey: ' test-key ',
              cachingProvider: DisabledMapCachingProvider(),
              center: LatLng(35, 139),
              pins: [],
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump();
      expect(searches, 1);
      expect(tiles, greaterThan(0));
      expect(tileKeys, everyElement('test-key'));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => client);
  });
  test('304 revalidates stale cached image without failure', () async {
    var failures = 0;
    final cache = StaleCache();
    final client = SafeTileClient(
      MockClient((request) async {
        expect(request.headers['if-none-match'], 'cached');
        return http.Response('', 304);
      }),
      () => failures++,
    );
    await resolveTile(
      SafeTileProvider(
        client: client,
        onFailure: () => failures++,
        cachingProvider: cache,
      ),
    );
    expect(failures, 0);
    expect(cache.refreshed, isTrue);
    client.close();
  });
  for (final body in [false, true]) {
    test('normal abort body=$body', () async {
      var failures = 0;
      final client = SafeTileClient(
        MockClient.streaming((_, _) async {
          if (!body) {
            throw http.RequestAbortedException(
              Uri.parse('https://example.invalid/?apiKey=SECRET'),
            );
          }
          return http.StreamedResponse(
            Stream.error(http.RequestAbortedException()),
            200,
          );
        }),
        () => failures++,
      );
      await resolveTile(
        SafeTileProvider(
          client: client,
          onFailure: () => failures++,
          cachingProvider: const DisabledMapCachingProvider(),
        ),
      );
      expect(failures, 0);
      client.close();
    });
  }
  for (final invalidImage in [false, true]) {
    testWidgets('visible safe error and retry image=$invalidImage', (
      tester,
    ) async {
      var healthy = false;
      var selections = 0;
      final mock = MockClient.streaming(
        (_, _) async => http.StreamedResponse(
          healthy
              ? Stream.value(TileProvider.transparentImage)
              : invalidImage
              ? Stream.value([1, 2, 3])
              : Stream.error(
                  StateError('https://example.invalid/?apiKey=SECRET'),
                ),
          200,
        ),
      );
      await http.runWithClient(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlaceMap(
                apiKey: 'SECRET',
                cachingProvider: DisabledMapCachingProvider(),
                center: const LatLng(35, 139),
                pins: const [],
                onSelect: (_) => selections++,
              ),
            ),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(FlutterMap));
        await tester.pump(const Duration(milliseconds: 300));
        expect(selections, 0);
        healthy = true;
        await tester.tap(find.byType(OutlinedButton));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump();
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(TileLayer), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => mock);
    });
  }
  testWidgets('old attempt failure cannot hide retried map', (tester) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: PlaceMap(
                apiKey: 'SECRET',
                cachingProvider: DisabledMapCachingProvider(),
                center: LatLng(35, 139),
                pins: [],
              ),
            ),
          ),
        );
        final old =
            tester.widget<TileLayer>(find.byType(TileLayer)).tileProvider
                as SafeTileProvider;
        old.onFailure();
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byType(OutlinedButton));
        await tester.pump();
        old.onFailure();
        await tester.pump();
        await tester.pump();
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(TileLayer), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      () => MockClient(
        (_) async => http.Response.bytes(TileProvider.transparentImage, 200),
      ),
    );
  });
}
