import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

abstract class LocalStore {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesStore implements LocalStore {
  static const key = 'point.configuration.v1';
  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, value)) {
      throw StateError('端末に保存できませんでした。');
    }
  }
}

class PointRepository {
  final LocalStore store;
  PointData _data = PointData();
  bool _loaded = false;
  Future<void> _tail = Future<void>.value();
  PointRepository(this.store);
  PointData get data => _data;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> load() => _serial(() async {
    _loaded = false;
    final raw = await store.read();
    try {
      final decoded = raw == null
          ? PointData()
          : PointData.fromJson(jsonDecode(raw));
      _data = decoded;
      _loaded = true;
    } catch (_) {
      throw const FormatException('保存データを読み込めません。元のデータは上書きしていません。');
    }
  });

  Future<void> update(PointData Function(PointData) change) =>
      _serial(() async {
        if (!_loaded) throw StateError('読み込みが完了していないため保存できません。');
        final next = change(_data);
        await store.write(jsonEncode(next.toJson()));
        _data = next;
      });
}
