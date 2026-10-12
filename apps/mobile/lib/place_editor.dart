import 'package:flutter/material.dart';
import 'models.dart';
import 'native_bridge.dart';

class PlaceEditor extends StatefulWidget {
  final Place? initial;
  final List<String> apps;
  final NativeBridge native;
  final Set<String> existingIds;
  const PlaceEditor({
    super.key,
    this.initial,
    required this.apps,
    required this.native,
    required this.existingIds,
  });
  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late final TextEditingController _radius;
  late final Set<String> _apps;
  bool _locating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final place = widget.initial;
    _name = TextEditingController(text: place?.name ?? '');
    _lat = TextEditingController(text: place?.latitude.toString() ?? '');
    _lng = TextEditingController(text: place?.longitude.toString() ?? '');
    _radius = TextEditingController(text: (place?.radius ?? 150).toString());
    _apps = {...?place?.appIds};
  }

  @override
  void dispose() {
    for (final controller in [_name, _lat, _lng, _radius]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _number(String? text, double min, double max) {
    final number = double.tryParse(text?.trim() ?? '');
    return number == null || !number.isFinite || number < min || number > max
        ? '$min〜$maxの数値を入力してください'
        : null;
  }

  Future<void> _capture() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final position = await widget.native.currentLocation();
      if (!mounted) return;
      _lat.text = position.latitude.toString();
      _lng.text = position.longitude.toString();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    try {
      if ({...widget.apps, ..._apps}.length > 3) {
        throw ArgumentError('無料版は合計3アプリまでです。不要なアプリは管理画面で削除してください。');
      }
      var id =
          widget.initial?.id ??
          'place_${DateTime.now().microsecondsSinceEpoch}';
      while (widget.initial == null && widget.existingIds.contains(id)) {
        id = '${id}_';
      }
      final place = Place(
        id: id,
        name: _name.text.trim(),
        latitude: double.parse(_lat.text.trim()),
        longitude: double.parse(_lng.text.trim()),
        radius: double.parse(_radius.text.trim()),
        appIds: catalog.keys.where(_apps.contains).toList(),
      );
      Navigator.of(context).pop(place);
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initial == null ? '場所を追加' : '場所を編集')),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('店名と位置を登録してください。地図・店舗検索はまだ利用できません。'),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '場所の名前'),
              maxLength: 80,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '名前を入力してください' : null,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _locating ? null : _capture,
              icon: const Icon(Icons.my_location),
              label: Text(_locating ? '現在地を取得中…' : '現在地を1回取得'),
            ),
            const Text('現在地の取得には位置情報の許可が必要です。設定画面から選択できます。手入力も可能です。'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lat,
              decoration: const InputDecoration(labelText: '緯度（例：35.6812）'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (v) => _number(v, -90, 90),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lng,
              decoration: const InputDecoration(labelText: '経度（例：139.7671）'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              validator: (v) => _number(v, -180, 180),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _radius,
              decoration: const InputDecoration(labelText: '検知半径（m）'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (v) => _number(v, 100, 1000),
            ),
            const SizedBox(height: 24),
            Text('この場所で使うアプリ', style: Theme.of(context).textTheme.titleMedium),
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
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFF9C2020)),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _locating ? null : _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    ),
  );
}
