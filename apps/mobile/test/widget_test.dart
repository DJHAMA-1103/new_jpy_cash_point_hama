import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:point_mobile/main.dart';
import 'package:point_mobile/native_bridge.dart';
import 'package:point_mobile/storage.dart';
import 'model_storage_test.dart' show MemoryStore;

void main() {
  testWidgets(
    'first use can skip permissions and navigate to real empty management',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore();
      final repo = PointRepository(store);
      await tester.pumpWidget(
        PointApp(repository: repo, native: NativeBridge(supported: false)),
      );
      await tester.pumpAndSettle();
      expect(find.text('お店に着いたら、使うアプリへ'), findsOneWidget);
      final skip = find.text('今は許可せずに進む');
      await tester.ensureVisible(skip);
      await tester.tap(skip);
      await tester.pumpAndSettle();
      expect(repo.data.onboarded, isTrue);
      expect(repo.data.places, isEmpty);
      expect(repo.data.apps, isEmpty);
      expect(find.textContaining('まだ場所がありません'), findsOneWidget);
      await tester.tap(find.text('アプリ').last);
      await tester.pumpAndSettle();
      expect(find.text('PayPayを登録'), findsOneWidget);
      await tester.tap(find.text('PayPayを登録'));
      await tester.pumpAndSettle();
      expect(repo.data.apps, ['paypay']);
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('位置情報：未確認'), findsOneWidget);
      expect(find.textContaining('この環境はiOS連携に未対応'), findsOneWidget);
      final restored = PointRepository(store);
      await restored.load();
      expect(restored.data.onboarded, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'corrupt startup has retry rather than empty state or endless progress',
    (tester) async {
      final store = MemoryStore('invalid json');
      await tester.pumpWidget(
        PointApp(
          repository: PointRepository(store),
          native: NativeBridge(supported: false),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('読み込みを再試行'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(store.writes, 0);
      await tester.tap(find.text('読み込みを再試行'));
      await tester.pumpAndSettle();
      expect(find.text('読み込みを再試行'), findsOneWidget);
      expect(store.value, 'invalid json');
      expect(store.writes, 0);
    },
  );
}
