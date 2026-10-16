import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const geoapifyApiKey = String.fromEnvironment('GEOAPIFY_API_KEY');

class GeoapifyPlace {
  final String name, address;
  final double latitude, longitude;

  const GeoapifyPlace({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });
}

class GeoapifySearchException implements Exception {
  final String message;
  const GeoapifySearchException(this.message);

  @override
  String toString() => message;
}

class GeoapifySearch {
  final String _apiKey;
  final http.Client _client;

  // The service owns the supplied client too; close it when the editor closes.
  GeoapifySearch({String apiKey = geoapifyApiKey, http.Client? client})
    : _apiKey = apiKey.trim(),
      _client = client ?? http.Client();

  Future<List<GeoapifyPlace>> search(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    if (_apiKey.isEmpty) {
      throw const GeoapifySearchException('地図のAPIキーが設定されていません。');
    }
    final text = query.trim();
    if (text.isEmpty) return [];
    if ((latitude != null || longitude != null) &&
        !_validCoordinates(latitude, longitude)) {
      throw const GeoapifySearchException('検索の基準位置を確認してください。');
    }

    final uri = Uri.https('api.geoapify.com', '/v1/geocode/search', {
      'text': text,
      'lang': 'ja',
      'filter': 'countrycode:jp',
      'limit': '5',
      'format': 'json',
      'apiKey': _apiKey,
      if (latitude != null && longitude != null)
        'bias': 'proximity:$longitude,$latitude',
    });
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const GeoapifySearchException('検索がタイムアウトしました。もう一度お試しください。');
    } catch (_) {
      // Transport errors can contain the request URL, including the API key.
      throw const GeoapifySearchException('検索に接続できません。通信環境を確認してください。');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const GeoapifySearchException('地図のAPIキーまたは利用制限の設定を確認してください。');
    }
    if (response.statusCode == 429) {
      throw const GeoapifySearchException('検索の利用上限に達しました。時間をおいてお試しください。');
    }
    if (response.statusCode != 200) {
      throw const GeoapifySearchException('検索サービスを利用できません。時間をおいてお試しください。');
    }
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map<String, dynamic> || body['results'] is! List) {
        throw const FormatException();
      }
      final places = <GeoapifyPlace>[];
      final seen = <(String, double, double)>{};
      for (final row in body['results'] as List) {
        if (row is! Map<String, dynamic>) throw const FormatException();
        final lat = row['lat'];
        final lon = row['lon'];
        if (lat is! num ||
            lon is! num ||
            !_validCoordinates(lat.toDouble(), lon.toDouble())) {
          throw const FormatException();
        }
        final address = _text(row['formatted']);
        final name =
            _text(row['name']) ?? _text(row['address_line1']) ?? address;
        if (name == null || address == null) throw const FormatException();
        final latitude = lat.toDouble();
        final longitude = lon.toDouble();
        if (seen.add((name, latitude, longitude))) {
          places.add(
            GeoapifyPlace(
              name: name,
              address: address,
              latitude: latitude,
              longitude: longitude,
            ),
          );
        }
      }
      return places.take(5).toList();
    } catch (_) {
      throw const GeoapifySearchException('検索結果を読み取れませんでした。もう一度お試しください。');
    }
  }

  void close() => _client.close();
}

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

bool _validCoordinates(double? latitude, double? longitude) =>
    latitude != null &&
    longitude != null &&
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;
