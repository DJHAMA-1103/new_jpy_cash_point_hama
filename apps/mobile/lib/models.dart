const catalog = <String, String>{
  'paypay': 'PayPay',
  'rakuten_pay': '楽天ペイ',
  'v_point': 'Vポイント',
  'd_point': 'dポイント',
};

class Place {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final double radius;
  final List<String> appIds;

  Place({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radius = 150,
    required List<String> appIds,
  }) : appIds = List.unmodifiable(appIds) {
    if (id.trim().isEmpty ||
        id.length > 128 ||
        name.trim().isEmpty ||
        name.length > 80 ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !radius.isFinite ||
        radius < 100 ||
        radius > 1000 ||
        appIds.toSet().length != appIds.length ||
        appIds.any((id) => !catalog.containsKey(id))) {
      throw ArgumentError('場所の入力を確認してください。半径は100〜1000mです。');
    }
  }

  Place withoutApp(String appId) => Place(
    id: id,
    name: name,
    latitude: latitude,
    longitude: longitude,
    radius: radius,
    appIds: appIds.where((id) => id != appId).toList(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    'appIds': appIds,
  };

  factory Place.fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('場所データの形式が不正です。');
    }
    final id = value['id'];
    final name = value['name'];
    final lat = value['latitude'];
    final lng = value['longitude'];
    final radius = value['radius'];
    if (id is! String ||
        name is! String ||
        lat is! num ||
        lng is! num ||
        radius is! num) {
      throw const FormatException('場所データの項目が不正です。');
    }
    return Place(
      id: id,
      name: name,
      latitude: lat.toDouble(),
      longitude: lng.toDouble(),
      radius: radius.toDouble(),
      appIds: stringList(value['appIds']),
    );
  }
}

List<String> stringList(Object? value) {
  if (value is! List || value.any((item) => item is! String)) {
    throw const FormatException('アプリ一覧の形式が不正です。');
  }
  return value.cast<String>();
}

class PointData {
  final bool onboarded;
  final List<String> apps;
  final List<Place> places;

  PointData({
    this.onboarded = false,
    List<String> apps = const [],
    List<Place> places = const [],
  }) : apps = List.unmodifiable(apps),
       places = List.unmodifiable(places) {
    if (apps.length > 3 || places.length > 2) {
      throw ArgumentError('無料版は場所2件・アプリ3件までです。追加枠はまだ販売していません。');
    }
    if (apps.toSet().length != apps.length ||
        apps.any((id) => !catalog.containsKey(id)) ||
        places.map((p) => p.id).toSet().length != places.length ||
        places.any((p) => p.appIds.any((id) => !apps.contains(id)))) {
      throw ArgumentError('登録データの関連付けが不正です。');
    }
  }

  PointData finishOnboarding() =>
      PointData(onboarded: true, apps: apps, places: places);

  PointData addApp(String id) {
    if (!catalog.containsKey(id)) throw ArgumentError('未対応のアプリです。');
    if (apps.contains(id)) return this;
    return PointData(onboarded: onboarded, apps: [...apps, id], places: places);
  }

  PointData removeApp(String id) => PointData(
    onboarded: onboarded,
    apps: apps.where((item) => item != id).toList(),
    places: places.map((p) => p.withoutApp(id)).toList(),
  );

  PointData savePlace(Place place) {
    final next = [...places];
    final index = next.indexWhere((p) => p.id == place.id);
    if (index < 0) {
      next.add(place);
    } else {
      next[index] = place;
    }
    return PointData(onboarded: onboarded, apps: apps, places: next);
  }

  PointData removePlace(String id) => PointData(
    onboarded: onboarded,
    apps: apps,
    places: places.where((p) => p.id != id).toList(),
  );

  Map<String, Object?> configuration() => {
    'apps': apps,
    'places': places.map((p) => p.toJson()).toList(),
  };

  Map<String, Object?> toJson() => {
    'version': 1,
    'onboarded': onboarded,
    ...configuration(),
  };

  factory PointData.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['version'] != 1 ||
        value['onboarded'] is! bool ||
        value['places'] is! List) {
      throw const FormatException('保存データの形式またはバージョンが未対応です。');
    }
    return PointData(
      onboarded: value['onboarded'] as bool,
      apps: stringList(value['apps']),
      places: (value['places'] as List).map(Place.fromJson).toList(),
    );
  }
}
