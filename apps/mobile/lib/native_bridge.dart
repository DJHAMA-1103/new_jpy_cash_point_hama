import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models.dart';

class NativeFailure implements Exception {
  final String message;
  const NativeFailure(this.message);
  @override
  String toString() => message;
}

class NativeStatus {
  final String location;
  final String notifications;
  final bool monitoringAvailable;
  final int monitoredCount;
  final String? lastError;
  NativeStatus._(
    this.location,
    this.notifications,
    this.monitoringAvailable,
    this.monitoredCount,
    this.lastError,
  );

  factory NativeStatus.parse(Object? result) {
    if (result is! Map) throw const NativeFailure('権限状態の応答が不正です。');
    final location = result['location'];
    final notifications = result['notifications'];
    final available = result['monitoringAvailable'];
    final count = result['monitoredCount'];
    final error = result['lastError'];
    if (!const [
          'notDetermined',
          'denied',
          'restricted',
          'whenInUse',
          'always',
        ].contains(location) ||
        !const [
          'notDetermined',
          'denied',
          'authorized',
          'provisional',
        ].contains(notifications) ||
        available is! bool ||
        count is! int ||
        count < 0 ||
        count > 2 ||
        (error != null && error is! String)) {
      throw const NativeFailure('権限状態の応答が不正です。');
    }
    return NativeStatus._(
      location as String,
      notifications as String,
      available,
      count,
      error as String?,
    );
  }
}

class Coordinates {
  final double latitude;
  final double longitude;
  const Coordinates(this.latitude, this.longitude);
}

class NativeBridge {
  VoidCallback? onStateChanged;
  final MethodChannel channel;
  final bool supported;
  NativeBridge({MethodChannel? channel, bool? supported})
    : channel = channel ?? const MethodChannel('jp.cashandpoint/native'),
      supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    if (this.supported) {
      this.channel.setMethodCallHandler((call) async {
        if (call.method == 'stateChanged') onStateChanged?.call();
      });
    }
  }

  Future<Object?> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!supported) {
      throw const NativeFailure('この環境では到着通知・外部アプリ起動を利用できません。iPhoneで確認してください。');
    }
    try {
      return await channel
          .invokeMethod<Object?>(method, arguments)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw const NativeFailure('端末から応答がありません。設定を確認して再試行してください。');
            },
          );
    } on MissingPluginException {
      throw const NativeFailure('iOS連携が利用できません。アプリのビルドを確認してください。');
    } on PlatformException catch (error) {
      throw NativeFailure('端末との連携に失敗しました：${error.message ?? error.code}');
    }
  }

  Future<NativeStatus> status() async =>
      NativeStatus.parse(await _call('status'));
  Future<NativeStatus> requestWhenInUse() async =>
      NativeStatus.parse(await _call('requestWhenInUse'));
  Future<NativeStatus> requestAlways(NativeStatus status) async {
    if (status.location != 'whenInUse') {
      throw const NativeFailure('まず「使用中のみ」の位置情報を許可してください。');
    }
    return NativeStatus.parse(await _call('requestAlways'));
  }

  Future<NativeStatus> requestNotifications() async =>
      NativeStatus.parse(await _call('requestNotifications'));
  Future<NativeStatus> sync(PointData data) async => NativeStatus.parse(
    await _call('syncConfiguration', data.configuration()),
  );

  Future<Coordinates> currentLocation() async {
    final value = await _call('currentLocation');
    if (value is! Map ||
        value['latitude'] is! num ||
        value['longitude'] is! num) {
      throw const NativeFailure('現在地を取得できませんでした。');
    }
    final lat = (value['latitude'] as num).toDouble();
    final lng = (value['longitude'] as num).toDouble();
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      throw const NativeFailure('取得した位置情報が不正です。');
    }
    return Coordinates(lat, lng);
  }

  Future<void> openApp(String appId) async {
    if (!catalog.containsKey(appId)) throw const NativeFailure('未対応のアプリです。');
    if (await _call('openApp', {'appId': appId}) != true) {
      throw const NativeFailure('アプリを開けません。未インストール、または起動方法が未対応です。');
    }
  }

  Future<void> openSettings() async {
    if (await _call('openSettings') != true) {
      throw const NativeFailure('設定を開けませんでした。');
    }
  }

  Future<String?> consumeLaunchError() async {
    final value = await _call('consumeLaunchError');
    if (value != null && value is! String) {
      throw const NativeFailure('アプリ起動結果の応答が不正です。');
    }
    return value as String?;
  }
}
