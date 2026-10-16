import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'geoapify.dart';
import 'models.dart';
import 'native_bridge.dart';

typedef PlaceSearch =
    Future<List<GeoapifyPlace>> Function(
      String query, {
      double? latitude,
      double? longitude,
    });
typedef PlaceMapBuilder =
    Widget Function(
      BuildContext context,
      LatLng center,
      LatLng? selected,
      ValueChanged<LatLng> onSelect,
    );

const _tokyo = LatLng(35.6812, 139.7671);

class PlaceEditor extends StatefulWidget {
  final Place? initial;
  final List<String> apps;
  final NativeBridge native;
  final Set<String> existingIds;
  final String apiKey;
  final PlaceSearch? search;
  final PlaceMapBuilder? mapBuilder;
  const PlaceEditor({
    super.key,
    this.initial,
    required this.apps,
    required this.native,
    required this.existingIds,
    this.apiKey = geoapifyApiKey,
    this.search,
    this.mapBuilder,
  });
  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> {
  final _form = GlobalKey<FormState>();
  final _query = TextEditingController();
  late final TextEditingController _name;
  late final Set<String> _apps;
  GeoapifySearch? _service;
  LatLng? _selected;
  late LatLng _center;
  List<GeoapifyPlace> _results = [];
  String? _address;
  String? _error;
  String? _searchMessage;
  bool _searching = false;
  bool _locating = false;
  bool _choosingApps = false;
  bool _returned = false;
  int _revision = 0;
  bool get _configured => widget.apiKey.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final place = widget.initial;
    _name = TextEditingController(text: place?.name ?? '');
    _apps = {...?place?.appIds};
    _selected = place == null ? null : LatLng(place.latitude, place.longitude);
    _center = _selected ?? _tokyo;
  }

  @override
  void dispose() {
    _revision++;
    _query.dispose();
    _name.dispose();
    _service?.close();
    super.dispose();
  }

  void _invalidate() {
    _revision++;
    _searching = false;
    _locating = false;
    _results = [];
    _searchMessage = null;
  }

  void _select(LatLng point, {GeoapifyPlace? result}) {
    setState(() {
      _invalidate();
      _selected = point;
      _center = point;
      _address = result?.address;
      if (result != null) _name.text = result.name;
      _error = null;
    });
  }

  Future<void> _search() async {
    if (!_configured || _searching || _query.text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final query = _query.text.trim();
    final revision = ++_revision;
    setState(() {
      _locating = false;
      _searching = true;
      _results = [];
      _selected = null;
      _address = null;
      _searchMessage = null;
      _error = null;
    });
    try {
      final search =
          widget.search ??
          (_service ??= GeoapifySearch(apiKey: widget.apiKey)).search;
      final results = await search(
        query,
        latitude: _center.latitude,
        longitude: _center.longitude,
      );
      if (!mounted || revision != _revision) return;
      setState(() {
        _results = results;
        _searchMessage = results.isEmpty
            ? '店舗が見つかりません。住所で検索するか、地図をタップしてください。'
            : '${results.length}件の候補。名前と住所を確認してください。';
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(
        () => _searchMessage = error is GeoapifySearchException
            ? error.message
            : '検索できませんでした。「検索」で再試行してください。',
      );
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _capture() async {
    final revision = ++_revision;
    setState(() {
      _locating = true;
      _searching = false;
      _results = [];
      _searchMessage = null;
      _error = null;
    });
    try {
      final position = await widget.native.currentLocation();
      if (!mounted || revision != _revision) return;
      _select(LatLng(position.latitude, position.longitude));
    } catch (_) {
      if (mounted && revision == _revision) {
        setState(
          () => _error = '現在地を取得できませんでした。位置情報の許可は設定で確認できます。検索や地図での選択も利用できます。',
        );
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _locating = false);
      }
    }
  }

  void _save() {
    if (_returned || _selected == null) return;
    if ({...widget.apps, ..._apps}.length > 3) {
      setState(() => _error = '無料版は合計3アプリまでです。不要なアプリは管理画面で削除してください。');
      return;
    }
    if (widget.initial == null && widget.existingIds.length >= 2) {
      setState(() => _error = '無料で登録できる店舗は2件までです。');
      return;
    }
    try {
      var id =
          widget.initial?.id ??
          'place_${DateTime.now().microsecondsSinceEpoch}';
      while (widget.initial == null && widget.existingIds.contains(id)) {
        id = '${id}_';
      }
      final place = Place(
        id: id,
        name: _name.text.trim(),
        latitude: _selected!.latitude,
        longitude: _selected!.longitude,
        radius: widget.initial?.radius ?? 150,
        appIds: catalog.keys.where(_apps.contains).toList(),
      );
      _returned = true;
      Navigator.of(context).pop(place);
    } catch (_) {
      setState(() => _error = '場所の名前と位置を確認してください。');
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_choosingApps,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _choosingApps) setState(() => _choosingApps = false);
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _choosingApps
              ? '使うアプリを選択'
              : widget.initial == null
              ? '場所を追加'
              : '場所を編集',
        ),
        leading: IconButton(
          tooltip: '戻る',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_choosingApps) {
              setState(() => _choosingApps = false);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              _invalidate();
              Navigator.pop(context);
            },
            child: const Text('キャンセル'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (!_choosingApps) ...[
                const Text('お店や住所を検索し、位置を確認してください。見つからない場所は地図をタップして指定できます。'),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('place-search'),
                  controller: _query,
                  enabled: _configured,
                  decoration: const InputDecoration(labelText: '店舗名・住所で検索'),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  onChanged: (_) => setState(() {
                    _invalidate();
                    _selected = null;
                    _address = null;
                  }),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _configured && !_searching ? _search : null,
                  icon: const Icon(Icons.search),
                  label: Text(_searching ? '検索中…' : '検索'),
                ),
                if (_searchMessage != null)
                  Semantics(liveRegion: true, child: Text(_searchMessage!)),
                for (final result in _results)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(result.name),
                    subtitle: Text(result.address),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _select(
                      LatLng(result.latitude, result.longitude),
                      result: result,
                    ),
                  ),
                const SizedBox(height: 12),
                if (_configured && widget.mapBuilder != null)
                  widget.mapBuilder!(context, _center, _selected, _select)
                else
                  PlaceMap(
                    apiKey: widget.apiKey,
                    center: _center,
                    pins: _selected == null ? [] : [_selected!],
                    onSelect: _select,
                  ),
                if (_configured) ...[
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _capture,
                    icon: const Icon(Icons.my_location),
                    label: Text(_locating ? '現在地を取得中…' : '現在地を1回取得'),
                  ),
                  const Text('現在地の取得には位置情報の許可が必要です。検索は許可なしで利用できます。'),
                ],
                const SizedBox(height: 16),
                if (_selected != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _address == null
                          ? 'ピンの位置を選択中。店舗の名前と位置を確認してください。'
                          : '選択した住所：$_address',
                    ),
                  ),
                TextFormField(
                  key: const Key('place-name'),
                  controller: _name,
                  decoration: const InputDecoration(labelText: '場所の名前'),
                  maxLength: 80,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '名前を入力してください'
                      : null,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _selected == null || _locating
                      ? null
                      : () {
                          if (!_form.currentState!.validate()) return;
                          setState(() {
                            _invalidate();
                            _choosingApps = true;
                            _error = null;
                          });
                        },
                  child: const Text('この場所で使うアプリを選ぶ'),
                ),
                const Text('次の画面で「保存」を押すまで登録されません。'),
              ] else ...[
                Text(_name.text, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                const Text('利用できるかは店舗で確認してください。登録は加盟店での利用を保証するものではありません。'),
                const Text('選んだアプリは、この場所と一緒に登録されます。'),
                for (final id in catalog.keys)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(catalog[id]!),
                    subtitle: Text(
                      id == 'v_point' ? '公式起動リンク対応・端末で動作確認が必要です' : '自動起動は未対応です',
                    ),
                    value: _apps.contains(id),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        _apps.add(id);
                      } else {
                        _apps.remove(id);
                      }
                    }),
                  ),
                Text(
                  _apps.length > 1
                      ? '複数アプリの選択方法は検討中のため、この場所の自動到着通知は無効です。'
                      : _apps.isEmpty
                      ? 'アプリ未選択のため、この場所の自動到着通知は無効です。'
                      : '到着通知には位置情報「常に」と通知の許可が必要です。',
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: _save, child: const Text('保存')),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFFFB4AB)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// Shared by the editor and overview; no geocoding or permission requests here.
class PlaceMap extends StatefulWidget {
  final String apiKey;
  final LatLng center;
  final List<LatLng> pins;
  final ValueChanged<LatLng>? onSelect;
  final MapCachingProvider? cachingProvider;
  const PlaceMap({
    super.key,
    this.apiKey = geoapifyApiKey,
    required this.center,
    required this.pins,
    this.onSelect,
    this.cachingProvider,
  });
  @override
  State<PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<PlaceMap> {
  final _controller = MapController();
  SafeTileClient? _client;
  SafeTileProvider? _provider;
  bool _failed = false;
  bool _ready = false;
  int _attempt = 0;

  @override
  void didUpdateWidget(PlaceMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_ready && oldWidget.center != widget.center) {
      _controller.move(widget.center, 16);
    }
  }

  void _tileFailed(int attempt) {
    if (_failed || !mounted || attempt != _attempt) return;
    _failed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && attempt == _attempt) setState(() {});
    });
  }

  @override
  void dispose() {
    _client?.close();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _link(String url) async {
    try {
      if (await launchUrl(Uri.parse(url))) return;
    } catch (_) {
      /* Show the same safe message for unsupported platforms. */
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('出典のページを開けませんでした。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.apiKey.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text('地図・検索は設定されていないため利用できません。登録済みの場所は名前とアプリを編集できます。'),
      );
    }
    final query = Uri(queryParameters: {'apiKey': widget.apiKey.trim()}).query;
    final attempt = _attempt;
    _client ??= SafeTileClient(http.Client(), () => _tileFailed(attempt));
    _provider ??= SafeTileProvider(
      client: _client!,
      cachingProvider: widget.cachingProvider,
      onFailure: () => _tileFailed(attempt),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 280,
            // Semantic taps have no pointer position; use the center button instead.
            child: ExcludeSemantics(
              child: FlutterMap(
                mapController: _controller,
                options: MapOptions(
                  initialCameraFit:
                      widget.onSelect == null && widget.pins.length > 1
                      ? CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(widget.pins),
                          padding: const EdgeInsets.all(48),
                          maxZoom: 16,
                        )
                      : null,
                  initialCenter: widget.center,
                  initialZoom: 15,
                  minZoom: 3,
                  maxZoom: 19,
                  onMapReady: () => _ready = true,
                  onTap: (_, point) {
                    if (!_failed) widget.onSelect?.call(point);
                  },
                ),
                children: [
                  if (!_failed)
                    TileLayer(
                      key: ValueKey(_attempt),
                      urlTemplate:
                          'https://maps.geoapify.com/v1/tile/osm-bright/{z}/{x}/{y}.png?$query',
                      userAgentPackageName: 'jp.cashandpoint',
                      tileProvider: _provider,
                      panBuffer: 0,
                      maxNativeZoom: 19,
                      errorTileCallback: (_, __, ___) => _tileFailed(attempt),
                    ),
                  MarkerLayer(
                    markers: [
                      for (final point in widget.pins)
                        Marker(
                          point: point,
                          width: 48,
                          height: 48,
                          alignment: Alignment.topCenter,
                          child: Semantics(
                            label: '登録位置のピン',
                            child: const Icon(
                              Icons.location_pin,
                              size: 48,
                              color: Color(0xFF111111),
                              shadows: [
                                Shadow(color: Color(0xFFFFD83D), blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_failed)
                    const Center(
                      child: ColoredBox(
                        color: Color(0xFF202020),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            '地図を読み込めませんでした。',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.onSelect != null)
          TextButton(
            onPressed: _failed
                ? null
                : () {
                    if (_ready) {
                      widget.onSelect?.call(_controller.camera.center);
                    }
                  },
            child: const Text('地図の中央を登録位置にする'),
          ),
        if (_failed)
          OutlinedButton(
            onPressed: () => setState(() {
              _client?.close();
              _client = null;
              _provider = null;
              _attempt++;
              _failed = false;
            }),
            child: const Text('地図を再試行'),
          ),
        Wrap(
          children: [
            TextButton(
              onPressed: () => _link('https://www.geoapify.com/'),
              child: const Text('© Geoapify'),
            ),
            TextButton(
              onPressed: () => _link('https://www.openstreetmap.org/copyright'),
              child: const Text('© OpenStreetMap contributors'),
            ),
          ],
        ),
      ],
    );
  }
}

// Keep flutter_map caching/abort semantics, but keep URL-bearing diagnostics private.
class SafeTileClient extends http.BaseClient {
  final http.Client _inner;
  final VoidCallback onFailure;
  SafeTileClient(this._inner, this.onFailure);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 304 &&
          (response.statusCode < 200 || response.statusCode >= 300)) {
        onFailure();
      }
      return http.StreamedResponse(
        _body(response.stream),
        response.statusCode,
        headers: response.headers,
        contentLength: response.contentLength,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
      );
    } on http.RequestAbortedException {
      throw http.RequestAbortedException();
    } catch (_) {
      onFailure();
      throw http.ClientException('Map tile unavailable');
    }
  }

  Stream<List<int>> _body(Stream<List<int>> stream) async* {
    try {
      await for (final bytes in stream.timeout(const Duration(seconds: 15))) {
        yield bytes;
      }
    } on http.RequestAbortedException {
      throw http.RequestAbortedException();
    } catch (_) {
      onFailure();
      throw http.ClientException('Map tile unavailable');
    }
  }

  @override
  void close() => _inner.close();
}

class SafeTileProvider extends NetworkTileProvider {
  final VoidCallback onFailure;
  SafeTileProvider({
    required http.Client client,
    required this.onFailure,
    super.cachingProvider,
  }) : super(httpClient: client, silenceExceptions: true);

  @override
  ImageProvider getImageWithCancelLoadingSupport(
    TileCoordinates coordinates,
    TileLayer options,
    Future<void> cancelLoading,
  ) => _SafeTileImage(
    super.getImageWithCancelLoadingSupport(coordinates, options, cancelLoading),
    onFailure,
  );
}

class _SafeTileImage extends ImageProvider<_SafeTileImage> {
  final ImageProvider delegate;
  final VoidCallback onFailure;
  const _SafeTileImage(this.delegate, this.onFailure);

  @override
  Future<_SafeTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _SafeTileImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load(delegate, decode));

  Future<ImageInfo> _load<T extends Object>(
    ImageProvider<T> provider,
    ImageDecoderCallback decode,
  ) async {
    try {
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final stream = provider.loadImage(key, (buffer, {getTargetSize}) async {
        try {
          return await decode(buffer, getTargetSize: getTargetSize);
        } catch (_) {
          // Even a corrupt cache tile must make the map visibly unavailable.
          onFailure();
          rethrow;
        }
      });
      final result = Completer<ImageInfo>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (image, _) {
          try {
            if (!result.isCompleted) result.complete(image.clone());
          } finally {
            image.dispose();
            stream.removeListener(listener);
          }
        },
        onError: (Object error, StackTrace? stack) {
          onFailure();
          if (!result.isCompleted) {
            result.completeError(StateError('Map tile unavailable'));
          }
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      return await result.future;
    } catch (_) {
      onFailure();
      throw StateError('Map tile unavailable');
    }
  }
}
