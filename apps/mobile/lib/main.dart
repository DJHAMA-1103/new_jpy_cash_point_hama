import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'models.dart';
import 'native_bridge.dart';
import 'place_editor.dart';
import 'storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PointApp());
}

class PointApp extends StatelessWidget {
  final PointRepository? repository;
  final NativeBridge? native;
  const PointApp({super.key, this.repository, this.native});
  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    debugShowCheckedModeBanner: false,
    title: 'POINT',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF080808),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFFFD83D),
        onPrimary: Colors.black,
        secondary: Color(0xFFFFD83D),
        onSecondary: Colors.black,
        surface: Color(0xFF202020),
        onSurface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF080808),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    ),
    home: PointHome(
      repository: repository ?? PointRepository(PreferencesStore()),
      native: native ?? NativeBridge(),
    ),
  );
}

class PointHome extends StatefulWidget {
  final PointRepository repository;
  final NativeBridge native;
  const PointHome({super.key, required this.repository, required this.native});
  @override
  State<PointHome> createState() => _PointHomeState();
}

class _PointHomeState extends State<PointHome> with WidgetsBindingObserver {
  bool _loading = true;
  bool _busy = false;
  Future<void> _idle = Future<void>.value();
  bool _resumePending = false;
  bool _settings = false;
  bool _synced = false;
  int _tab = 0;
  String? _loadError;
  String? _error;
  NativeStatus? _status;
  PointData get _data => widget.repository.data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.native.onStateChanged = () {
      if (!mounted || _loading || _loadError != null) return;
      if (_busy) {
        _resumePending = true;
      } else {
        _run(_refresh);
      }
    };
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.native.onStateChanged = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading && _loadError == null) {
      if (_busy) {
        _resumePending = true;
      } else {
        _run(_refresh);
      }
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await widget.repository.load();
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (mounted && _loadError == null) await _run(_refresh);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!mounted) return;
    if (_busy) {
      await _idle;
      return _run(action);
    }
    final finished = Completer<void>();
    _idle = finished.future;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      finished.complete();
      if (mounted) {
        setState(() => _busy = false);
        if (_resumePending) {
          _resumePending = false;
          await _run(_refresh);
        }
      }
    }
  }

  Future<void> _refresh() async {
    _synced = false;
    _status = null;
    if (!widget.native.supported) return;
    final failures = <String>[];
    try {
      _status = await widget.native.status();
      _status = await widget.native.sync(_data);
      _synced = true;
      if (_status!.lastError != null) failures.add(_status!.lastError!);
    } catch (error) {
      failures.add('$error');
    }
    if (widget.native.supported) {
      try {
        final launchError = await widget.native.consumeLaunchError();
        if (launchError != null) failures.add(launchError);
      } catch (error) {
        failures.add('$error');
      }
    }
    if (failures.isNotEmpty) throw NativeFailure(failures.join('\n'));
  }

  Future<void> _save(PointData Function(PointData) change) => _run(() async {
    await widget.repository.update(change);
    if (mounted) setState(() {});
    try {
      await _refresh();
    } catch (error) {
      throw NativeFailure('端末内への保存は完了しました。到着通知の同期状態を確認してください。\n$error');
    }
  });

  Future<void> _permission(Future<NativeStatus> Function() request) =>
      _run(() async {
        _status = await request();
        await _refresh();
      });

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _edit([Place? place]) async {
    if (_busy) return;
    if (place == null && _data.places.length >= 2) {
      setState(() => _error = '無料版は場所2件までです。追加枠はまだ販売していません。');
      return;
    }
    final result = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceEditor(
          initial: place,
          apps: _data.apps,
          native: widget.native,
          existingIds: _data.places.map((p) => p.id).toSet(),
        ),
      ),
    );
    if (result != null && mounted) {
      await _save((data) {
        var next = data;
        for (final id in result.appIds) {
          next = next.addApp(id);
        }
        return next.savePlace(result);
      });
    }
  }

  String _locationLabel() => switch (_status?.location) {
    'notDetermined' => '未選択',
    'denied' => '許可なし',
    'restricted' => '制限あり',
    'whenInUse' => '使用中のみ',
    'always' => '常に',
    _ => '未確認',
  };
  String _notificationLabel() => switch (_status?.notifications) {
    'notDetermined' => '未選択',
    'denied' => '許可なし',
    'authorized' => '許可',
    'provisional' => '仮許可',
    _ => '未確認',
  };

  List<Widget> _permissionControls() => [
    Text('位置情報：${_locationLabel()}'),
    Text('通知：${_notificationLabel()}'),
    const SizedBox(height: 12),
    OutlinedButton(
      onPressed: _busy || !widget.native.supported
          ? null
          : () => _permission(widget.native.requestWhenInUse),
      child: const Text('使用中の位置情報を選択'),
    ),
    if (_status?.location == 'whenInUse')
      OutlinedButton(
        onPressed: _busy
            ? null
            : () => _permission(() => widget.native.requestAlways(_status!)),
        child: const Text('到着通知のため「常に」を選択'),
      ),
    OutlinedButton(
      onPressed: _busy || !widget.native.supported
          ? null
          : () => _permission(widget.native.requestNotifications),
      child: const Text('通知の許可を選択'),
    ),
    if (!widget.native.supported)
      const Text('この環境はiOS連携に未対応です。場所・アプリの管理のみ利用できます。'),
  ];

  Widget _onboarding() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Card(
        margin: const EdgeInsets.all(20),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.near_me_outlined, size: 40),
            const SizedBox(height: 16),
            Text(
              'お店に着いたら、使うアプリへ',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              '登録した場所への到着を検知するため位置情報を使います。バックグラウンドでの到着通知には「常に」の許可が必要です。通知をタップするとPOINTを経由して登録アプリを開きます。',
            ),
            const SizedBox(height: 12),
            const Text(
              '許可は任意です。あとで設定から変更できます。インストール済みアプリの一覧は取得しません。通知の時刻やアプリの起動速度は保証されません。',
            ),
            const SizedBox(height: 20),
            ..._permissionControls(),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _save((d) => d.finishOnboarding()),
              child: const Text('管理画面へ進む'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _save((d) => d.finishOnboarding()),
              child: const Text('今は許可せずに進む'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _settingsView() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('権限と到着通知', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const Text('登録した場所への到着検知には位置情報「常に」と通知の許可を使います。許可は任意で、端末設定から変更できます。'),
      const SizedBox(height: 16),
      ..._permissionControls(),
      const SizedBox(height: 16),
      Text('端末への設定同期：${_synced ? '完了' : '未確認・要再試行'}'),
      Text(
        '監視機能：${_status == null
            ? '未確認'
            : _status!.monitoringAvailable
            ? '利用可能'
            : '利用不可'}',
      ),
      Text('監視中の場所：${_synced ? '${_status?.monitoredCount ?? 0}件' : '未確認'}'),
      OutlinedButton(
        onPressed: _busy ? null : () => _run(_refresh),
        child: const Text('状態を再確認・再同期'),
      ),
      OutlinedButton(
        onPressed: _busy || !widget.native.supported
            ? null
            : () => _run(widget.native.openSettings),
        child: const Text('端末の設定を開く'),
      ),
      const SizedBox(height: 20),
      const Text('複数アプリまたはアプリ未選択の場所は、自動到着通知の対象外です。登録直後にその場所の内側にいても通知しません。'),
      const SizedBox(height: 12),
      const Text(
        'OSの状態、位置情報の精度、省電力設定や強制終了などにより、通知が遅れる・届かない場合があります。到着だけで外部アプリを自動起動しません。',
      ),
      const SizedBox(height: 12),
      const Text('無料版：場所2件・アプリ3件。買い切りの追加枠はまだ販売していません。'),
    ],
  );

  String _placeState(Place place) {
    if (place.appIds.isEmpty) return '通知無効：アプリ未選択';
    if (place.appIds.length > 1) return '通知無効：複数アプリの選択方法は検討中';
    if (!_synced) return '通知状態は未確認：設定から再同期してください';
    if (_status?.location != 'always' ||
        !const ['authorized', 'provisional'].contains(_status?.notifications)) {
      return '通知には位置情報「常に」と通知の許可が必要です';
    }
    return '到着通知の対象（監視状況は設定で確認）';
  }

  Widget _placesView() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '登録した場所',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '位置の模式表示・実際の地図ではありません',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            if (_data.places.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Icon(
                  Icons.location_on_outlined,
                  color: Color(0xFFFFD83D),
                  size: 48,
                ),
              ),
            for (final p in _data.places)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.place, color: Color(0xFFFFD83D)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.name,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFD83D),
                foregroundColor: Colors.black,
              ),
              onPressed: _busy ? null : () => _edit(),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('場所を追加・現在地を登録'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        'マイスポット  ${_data.places.length}/2',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      if (_data.places.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('まだ場所がありません。よく行くお店と、そこで使うアプリを登録しましょう。'),
        ),
      for (final place in _data.places)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(place.name, style: Theme.of(context).textTheme.titleLarge),
                Text('半径 ${place.radius.toStringAsFixed(0)}m'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final id in place.appIds)
                      ActionChip(
                        avatar: const Icon(Icons.open_in_new, size: 16),
                        label: Text(catalog[id]!),
                        tooltip: '${catalog[id]}を開く',
                        onPressed: _busy
                            ? null
                            : () => _run(() => widget.native.openApp(id)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_placeState(place)),
                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _edit(place),
                      child: const Text('編集'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirm(
                                    '場所を削除しますか？',
                                    '${place.name}の登録と通知設定を削除します。',
                                  ) &&
                                  mounted) {
                                await _save(
                                  (data) => data.removePlace(place.id),
                                );
                              }
                            },
                      child: const Text('削除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      const Text('登録アプリの店舗での利用可否は、ご自身で確認してください。'),
    ],
  );

  Widget _appsView() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'マイアプリ  ${_data.apps.length}/3',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text('自分が使うアプリを選んで登録してください。インストール状況は自動取得しません。'),
      const SizedBox(height: 16),
      for (final entry in catalog.entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.value,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                if (_data.apps.contains(entry.key))
                  Wrap(
                    spacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  _run(() => widget.native.openApp(entry.key)),
                        child: const Text('開く'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (await _confirm(
                                      'アプリ登録を削除しますか？',
                                      'すべての場所から${entry.value}の関連付けも外れます。アプリ本体は削除されません。',
                                    ) &&
                                    mounted) {
                                  await _save(
                                    (data) => data.removeApp(entry.key),
                                  );
                                }
                              },
                        child: const Text('登録を削除'),
                      ),
                    ],
                  )
                else
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _save((data) => data.addApp(entry.key)),
                    child: Text('${entry.value}を登録'),
                  ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        '無料版は合計3アプリまでです。追加枠はまだ販売していません。登録しても、アプリの起動や店舗での利用を保証するものではありません。',
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Text(
            'POINT',
            style: TextStyle(
              color: Color(0xFFFFD83D),
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('POINT')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('読み込みを再試行')),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_settings ? '設定' : 'POINT'),
        leading: _settings
            ? IconButton(
                tooltip: '管理画面へ戻る',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _settings = false),
              )
            : null,
        actions: _data.onboarded && !_settings
            ? [
                IconButton(
                  tooltip: '設定',
                  onPressed: () => setState(() => _settings = true),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ]
            : [],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(semanticsLabel: '処理中'),
            if (_error != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .28,
                ),
                child: Material(
                  color: const Color(0xFFFFE9E5),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Semantics(
                              liveRegion: true,
                              child: Text(_error!),
                            ),
                          ),
                          IconButton(
                            tooltip: 'メッセージを閉じる',
                            onPressed: () => setState(() => _error = null),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: !_data.onboarded
                  ? _onboarding()
                  : _settings
                  ? _settingsView()
                  : _tab == 0
                  ? _placesView()
                  : _appsView(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !_data.onboarded || _settings
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        selected: _tab == 0,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _tab = 0),
                          icon: const Icon(Icons.place_outlined),
                          label: const Text('場所'),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 64,
                      height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFFFFD83D),
                          foregroundColor: Colors.black,
                        ),
                        onPressed: _busy ? null : () => _edit(),
                        child: Semantics(
                          label: '場所を追加',
                          child: const Icon(Icons.add, size: 30),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Semantics(
                        selected: _tab == 1,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _tab = 1),
                          icon: const Icon(Icons.apps),
                          label: const Text('アプリ'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
