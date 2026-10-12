import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:point_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_mobile/main.dart';
import 'package:point_mobile/native_bridge.dart';
import 'package:point_mobile/storage.dart';
import 'model_storage_test.dart' show MemoryStore;

class PausableNative extends NativeBridge {
  Completer<void>? refreshGate;
  PausableNative() : super(supported: true);
  NativeStatus get ready => NativeStatus.parse({
    'location': 'always',
    'notifications': 'authorized',
    'monitoringAvailable': true,
    'monitoredCount': 0,
    'lastError': null,
  });
  @override
  Future<NativeStatus> status() async {
    await refreshGate?.future;
    return ready;
  }

  @override
  Future<NativeStatus> sync(PointData data) async => ready;
  @override
  Future<String?> consumeLaunchError() async => null;
}

void main() {
  testWidgets(
    'register, edit and delete a real place while preserving saved apps',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStore(
        jsonEncode(PointData(onboarded: true).toJson()),
      );
      final repo = PointRepository(storage);
      final native = PausableNative();
      await tester.pumpWidget(PointApp(repository: repo, native: native));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'テスト薬局');
      await tester.enterText(fields.at(1), '35.6812');
      await tester.enterText(fields.at(2), '139.7671');
      final target = find.widgetWithText(CheckboxListTile, 'Vポイント');
      await tester.scrollUntilVisible(
        target,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(target);
      await tester.scrollUntilVisible(
        find.text('保存'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      native.refreshGate = Completer<void>();
      native.onStateChanged?.call();
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.data.places, isEmpty);
      native.refreshGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.data.places.single.appIds, ['v_point']);
      final id = repo.data.places.single.id;
      await tester.scrollUntilVisible(
        find.text('編集'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '変更した薬局');
      await tester.scrollUntilVisible(
        find.text('保存'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.data.places.single.id, id);
      expect(repo.data.places.single.name, '変更した薬局');
      final restored = PointRepository(storage);
      await restored.load();
      expect(restored.data.places.single.name, '変更した薬局');
      await tester.scrollUntilVisible(
        find.text('削除'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('削除'),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.data.places, isEmpty);
      expect(repo.data.apps, ['v_point']);
      expect(tester.takeException(), isNull);
    },
  );
}
