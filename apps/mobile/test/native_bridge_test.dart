import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_mobile/models.dart';
import 'package:point_mobile/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jp.cashandpoint/native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final status = <String, Object?>{
    'location': 'whenInUse',
    'notifications': 'authorized',
    'monitoringAvailable': true,
    'monitoredCount': 0,
    'lastError': null,
  };
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'native state changes notify Flutter without a permission request',
    () async {
      final bridge = NativeBridge(channel: channel, supported: true);
      var changes = 0;
      bridge.onStateChanged = () => changes++;
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('stateChanged'),
        ),
        (_) {},
      );
      expect(changes, 1);
      bridge.onStateChanged = null;
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('stateChanged'),
        ),
        (_) {},
      );
      expect(changes, 1);
    },
  );

  test(
    'non-iOS operations report unsupported and never invoke native',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return true;
      });
      final bridge = NativeBridge(channel: channel, supported: false);
      await expectLater(bridge.status(), throwsA(isA<NativeFailure>()));
      await expectLater(
        bridge.openApp('paypay'),
        throwsA(isA<NativeFailure>()),
      );
      expect(calls, 0);
    },
  );

  test('missing channel is a visible failure', () async {
    final bridge = NativeBridge(channel: channel, supported: true);
    await expectLater(bridge.status(), throwsA(isA<NativeFailure>()));
  });

  test('sync sends only the exact native configuration shape', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return status;
    });
    final data = PointData(
      onboarded: true,
      apps: ['paypay'],
      places: [
        Place(
          id: 'a',
          name: '店',
          latitude: 35,
          longitude: 139,
          appIds: ['paypay'],
        ),
      ],
    );
    await NativeBridge(channel: channel, supported: true).sync(data);
    expect(received!.method, 'syncConfiguration');
    expect(received!.arguments, data.configuration());
    expect((received!.arguments as Map).containsKey('onboarded'), isFalse);
  });

  test('false launch result and malformed coordinates are failures', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'openApp'
          ? false
          : {'latitude': 200.0, 'longitude': 0.0},
    );
    final bridge = NativeBridge(channel: channel, supported: true);
    await expectLater(bridge.openApp('paypay'), throwsA(isA<NativeFailure>()));
    await expectLater(bridge.currentLocation(), throwsA(isA<NativeFailure>()));
  });

  test(
    'Always request is prevented until whenInUse; no URL is accepted',
    () async {
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        calls++;
        return status;
      });
      final bridge = NativeBridge(channel: channel, supported: true);
      final denied = NativeStatus.parse({...status, 'location': 'denied'});
      await expectLater(
        bridge.requestAlways(denied),
        throwsA(isA<NativeFailure>()),
      );
      await expectLater(
        bridge.openApp('https://example.com'),
        throwsA(isA<NativeFailure>()),
      );
      expect(calls, 0);
      await bridge.requestAlways(NativeStatus.parse(status));
      expect(calls, 1);
    },
  );
}
