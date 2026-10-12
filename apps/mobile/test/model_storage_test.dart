import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_mobile/models.dart';
import 'package:point_mobile/storage.dart';

class MemoryStore implements LocalStore {
  String? value;
  bool fail = false;
  int writes = 0;
  MemoryStore([this.value]);
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    writes++;
    await Future<void>.delayed(Duration.zero);
    if (fail) throw StateError('disk full');
    value = next;
  }
}

Place place(String id, {List<String> apps = const []}) =>
    Place(id: id, name: '店舗$id', latitude: 35, longitude: 139, appIds: apps);

void main() {
  test(
    'new app and place commit together, including storage failure',
    () async {
      final store = MemoryStore();
      final repo = PointRepository(store);
      await repo.load();
      PointData addBoth(PointData data) =>
          data.addApp('v_point').savePlace(place('new', apps: ['v_point']));
      store.fail = true;
      await expectLater(repo.update(addBoth), throwsStateError);
      expect(repo.data.apps, isEmpty);
      expect(repo.data.places, isEmpty);
      expect(store.value, isNull);
      store.fail = false;
      await repo.update(addBoth);
      final reloaded = PointRepository(store);
      await reloaded.load();
      expect(reloaded.data.apps, ['v_point']);
      expect(reloaded.data.places.single.appIds, ['v_point']);
    },
  );
  test('free limits apply globally; existing places remain editable', () {
    final data = PointData(
      apps: ['paypay', 'rakuten_pay', 'v_point'],
      places: [place('a'), place('b')],
    );
    expect(() => data.addApp('d_point'), throwsArgumentError);
    expect(() => data.savePlace(place('c')), throwsArgumentError);
    expect(data.savePlace(place('a')).places.length, 2);
    expect(data.addApp('paypay').apps.length, 3);
  });

  test('reject invalid finite ranges, IDs, references and duplicates', () {
    for (final latitude in [double.nan, double.infinity, 91.0]) {
      expect(
        () => Place(
          id: 'a',
          name: '店',
          latitude: latitude,
          longitude: 0,
          appIds: [],
        ),
        throwsArgumentError,
      );
    }
    for (final radius in [99.0, 1001.0]) {
      expect(
        () => Place(
          id: 'a',
          name: '店',
          latitude: 0,
          longitude: 0,
          radius: radius,
          appIds: [],
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => Place(id: 'a', name: ' ', latitude: 0, longitude: 0, appIds: []),
      throwsArgumentError,
    );
    expect(
      () => Place(id: 'a', name: '店', latitude: 0, longitude: -181, appIds: []),
      throwsArgumentError,
    );
    expect(() => PointData(apps: ['unknown']), throwsArgumentError);
    expect(() => PointData(apps: ['paypay', 'paypay']), throwsArgumentError);
    expect(
      () => PointData(places: [place('a'), place('a')]),
      throwsArgumentError,
    );
    expect(
      () => PointData(
        places: [
          place('a', apps: ['paypay']),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => PointData.fromJson({
        'version': 99,
        'onboarded': true,
        'apps': [],
        'places': [],
      }),
      throwsFormatException,
    );
  });

  test('deleting an app unlinks every place without deleting places', () {
    final data = PointData(
      apps: ['paypay', 'd_point'],
      places: [
        place('a', apps: ['paypay', 'd_point']),
        place('b', apps: ['paypay']),
      ],
    );
    final next = data.removeApp('paypay');
    expect(next.apps, ['d_point']);
    expect(next.places.first.appIds, ['d_point']);
    expect(next.places.last.appIds, isEmpty);
    expect(data.places.first.appIds, ['paypay', 'd_point']);
  });

  test('round trip preserves IDs, onboarding and multi-app configuration', () {
    final data = PointData(
      onboarded: true,
      apps: ['paypay', 'v_point'],
      places: [
        place('stable', apps: ['paypay', 'v_point']),
      ],
    );
    final restored = PointData.fromJson(jsonDecode(jsonEncode(data.toJson())));
    expect(restored.toJson(), data.toJson());
    expect(() => restored.apps.add('d_point'), throwsUnsupportedError);
  });

  test('serialized mutations derive from the last committed state', () async {
    final store = MemoryStore();
    final repo = PointRepository(store);
    await repo.load();
    await Future.wait([
      repo.update((d) => d.addApp('paypay')),
      repo.update((d) => d.addApp('v_point')),
      repo.update((d) => d.finishOnboarding()),
    ]);
    expect(repo.data.apps, ['paypay', 'v_point']);
    final reloaded = PointRepository(store);
    await reloaded.load();
    expect(reloaded.data.apps, repo.data.apps);
    expect(reloaded.data.onboarded, isTrue);
  });

  test(
    'write failure preserves committed memory and allows later retry',
    () async {
      final store = MemoryStore();
      final repo = PointRepository(store);
      await repo.load();
      await repo.update((d) => d.addApp('paypay'));
      final oldValue = store.value;
      store.fail = true;
      await expectLater(
        repo.update((d) => d.addApp('v_point')),
        throwsStateError,
      );
      expect(repo.data.apps, ['paypay']);
      expect(store.value, oldValue);
      store.fail = false;
      await repo.update((d) => d.addApp('d_point'));
      expect(repo.data.apps, ['paypay', 'd_point']);
    },
  );

  test(
    'corrupt JSON blocks mutations without overwriting original bytes',
    () async {
      final store = MemoryStore('{broken');
      final repo = PointRepository(store);
      await expectLater(repo.load(), throwsFormatException);
      await expectLater(
        repo.update((d) => d.finishOnboarding()),
        throwsStateError,
      );
      expect(store.writes, 0);
      expect(store.value, '{broken');
    },
  );
}
