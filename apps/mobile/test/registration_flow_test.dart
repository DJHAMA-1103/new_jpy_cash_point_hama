import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:point_mobile/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_mobile/main.dart';
import 'package:point_mobile/native_bridge.dart';
import 'package:point_mobile/storage.dart';
import 'package:point_mobile/place_editor.dart';
import 'place_editor_test.dart' show testMap, chosen, tapText;
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
      await tester.pumpWidget(
        PointApp(
          repository: repo,
          native: native,
          placeEditorBuilder: (editor) => PlaceEditor(
            initial: editor.initial,
            apps: editor.apps,
            native: editor.native,
            existingIds: editor.existingIds,
            apiKey: 'test-only',
            mapBuilder: testMap,
            search: (query, {latitude, longitude}) async => [],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tapText(tester, 'テスト地図のピンを選択');
      await tester.enterText(find.byKey(const Key('place-name')), 'テスト薬局');
      await tapText(tester, 'この場所で使うアプリを選ぶ');
      expect(repo.data.places, isEmpty);
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
      expect(repo.data.places.single.latitude, chosen.latitude);
      expect(repo.data.places.single.longitude, chosen.longitude);
      final id = repo.data.places.single.id;
      await tester.scrollUntilVisible(
        find.text('編集'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('編集'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('place-name')), '変更した薬局');
      await tapText(tester, 'この場所で使うアプリを選ぶ');
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
